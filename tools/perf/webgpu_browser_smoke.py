#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import re
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request



class BenchmarkHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
    }

    def log_message(self, fmt: str, *args: object) -> None:
        print("http:", fmt % args)


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def find_chrome() -> str:
    for name in ("google-chrome-stable", "google-chrome", "chromium", "chromium-browser"):
        path = shutil.which(name)
        if path:
            return path
    raise SystemExit("Chrome/Chromium not found on runner")


class CDP:
    def __init__(self, url: str) -> None:
        import websocket as websocket_client

        self.websocket = websocket_client
        self.ws = websocket_client.create_connection(url, timeout=5)
        self.next_id = 1
        self.events: list[dict] = []

    def close(self) -> None:
        self.ws.close()

    def call(self, method: str, params: dict | None = None, timeout: float = 15.0) -> dict:
        call_id = self.next_id
        self.next_id += 1
        self.ws.send(json.dumps({"id": call_id, "method": method, "params": params or {}}))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            remaining = max(0.1, deadline - time.monotonic())
            self.ws.settimeout(remaining)
            try:
                message = json.loads(self.ws.recv())
            except self.websocket.WebSocketTimeoutException:
                break
            if message.get("id") == call_id:
                if "error" in message:
                    raise RuntimeError(f"CDP {method} failed: {message['error']}")
                return message.get("result", {})
            self.events.append(message)
        raise TimeoutError(f"Timed out waiting for CDP {method}")

    def receive_event(self, timeout: float = 0.5) -> dict | None:
        self.ws.settimeout(max(0.05, timeout))
        try:
            message = json.loads(self.ws.recv())
        except self.websocket.WebSocketTimeoutException:
            return None
        self.events.append(message)
        return message

    def evaluate(self, expression: str, await_promise: bool = False, timeout: float = 15.0):
        result = self.call(
            "Runtime.evaluate",
            {
                "expression": expression,
                "awaitPromise": await_promise,
                "returnByValue": True,
            },
            timeout=timeout,
        )
        remote = result.get("result", {})
        if remote.get("subtype") == "error":
            raise RuntimeError(remote.get("description", "JavaScript evaluation failed"))
        return remote.get("value")


def wait_for_page(debug_port: int, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    endpoint = f"http://127.0.0.1:{debug_port}/json/list"
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(endpoint, timeout=1) as response:
                targets = json.load(response)
            for target in targets:
                if target.get("type") == "page" and target.get("webSocketDebuggerUrl"):
                    return str(target["webSocketDebuggerUrl"])
        except Exception:
            pass
        time.sleep(0.25)
    raise TimeoutError("Chromium DevTools page target did not appear")


WEBGPU_EVENT_CONSOLE_PREFIX = "STARJUNK_WEBGPU_EVENT_JSON:"
SPIRV_DUMP_CONSOLE_PREFIX = "STARJUNK_SPIRV_DUMP:"
RESULT_CONSOLE_PREFIXES = {
    "__STARJUNK_BOOT_RESULT__": "STARJUNK_WEBGPU_BOOT_JSON:",
    "__STARJUNK_PERF_RESULT__": "STARJUNK_PERF_JSON:",
    "__STARJUNK_PLAYABLE_RESULT__": "STARJUNK_PLAYABLE_JSON:",
}


def renderer_identity_errors(
    payload: dict, expected_renderer: str, expected_driver: str
) -> list[str]:
    renderer = str(payload.get("renderer", "")).lower()
    driver = str(payload.get("rendering_driver", "")).lower()
    errors: list[str] = []
    if renderer != expected_renderer:
        errors.append(f"Expected renderer {expected_renderer!r}, got {renderer!r}")
    if driver != expected_driver:
        errors.append(f"Expected rendering driver {expected_driver!r}, got {driver!r}")
    return errors


def console_values(event: dict) -> list[object]:
    if event.get("method") != "Runtime.consoleAPICalled":
        return []
    values: list[object] = []
    for arg in event.get("params", {}).get("args", [])[:12]:
        values.append(arg.get("value", arg.get("description", arg.get("type", ""))))
    return values


def console_json_from_event(event: dict, prefix: str):
    for value in console_values(event):
        if not isinstance(value, str) or not value.startswith(prefix):
            continue
        encoded = value[len(prefix):].strip()
        if not encoded:
            continue
        try:
            return json.loads(encoded)
        except json.JSONDecodeError:
            continue
    return None


def find_console_json(events: list[dict], prefix: str):
    for event in reversed(events):
        payload = console_json_from_event(event, prefix)
        if payload is not None:
            return payload
    return None


def wait_for_console_json(cdp: CDP, prefix: str, timeout: float):
    payload = find_console_json(cdp.events, prefix)
    if payload is not None:
        return payload

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = max(0.05, min(0.5, deadline - time.monotonic()))
        event = cdp.receive_event(remaining)
        if event is None:
            continue
        payload = console_json_from_event(event, prefix)
        if payload is not None:
            return payload
    return None


def extract_browser_events(events: list[dict]) -> list[dict]:
    parsed: list[dict] = []
    for event in events:
        payload = console_json_from_event(event, WEBGPU_EVENT_CONSOLE_PREFIX)
        if isinstance(payload, dict):
            parsed.append(payload)
    return parsed


def write_spirv_dumps(events: list[dict], dump_dir: Path | None) -> list[dict]:
    groups: dict[tuple[str, int, str], dict] = {}
    for event in events:
        for value in console_values(event):
            if not isinstance(value, str) or not value.startswith(SPIRV_DUMP_CONSOLE_PREFIX):
                continue
            encoded = value[len(SPIRV_DUMP_CONSOLE_PREFIX):]
            parts = encoded.split("|", 5)
            if len(parts) != 6:
                continue
            shader_name, stage_text, kind, chunk_text, total_text, chunk_data = parts
            # Godot print_line() inserts spaces between Variant arguments. Accept
            # both the current spaced console form and a future concatenated
            # emitter without letting formatting whitespace corrupt base64.
            shader_name = shader_name.strip()
            kind = kind.strip()
            chunk_data = chunk_data.strip()
            try:
                stage = int(stage_text)
                chunk_index = int(chunk_text)
                total_chunks = int(total_text)
            except ValueError:
                continue
            if chunk_index < 0 or total_chunks <= 0 or chunk_index >= total_chunks:
                continue
            key = (shader_name, stage, kind)
            group = groups.setdefault(
                key,
                {"total": total_chunks, "chunks": {}, "shader": shader_name, "stage": stage, "kind": kind},
            )
            if group["total"] != total_chunks:
                continue
            group["chunks"][chunk_index] = chunk_data

    summaries: list[dict] = []
    if dump_dir is not None:
        dump_dir.mkdir(parents=True, exist_ok=True)
    for (_, _, _), group in sorted(groups.items()):
        total = int(group["total"])
        chunks = group["chunks"]
        complete = len(chunks) == total and all(i in chunks for i in range(total))
        summary = {
            "shader": group["shader"],
            "stage": group["stage"],
            "kind": group["kind"],
            "chunks": len(chunks),
            "expected_chunks": total,
            "complete": complete,
        }
        if complete:
            try:
                raw = base64.b64decode("".join(chunks[i] for i in range(total)), validate=True)
            except Exception as exc:
                summary["decode_error"] = str(exc)
                complete = False
                summary["complete"] = False
            else:
                digest = hashlib.sha256(raw).hexdigest()
                summary["size_bytes"] = len(raw)
                summary["sha256"] = digest
                if dump_dir is not None:
                    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", str(group["shader"])).strip("_") or "shader"
                    filename = f"{safe}_stage{group['stage']}_{group['kind']}.spv"
                    path = dump_dir / filename
                    path.write_bytes(raw)
                    summary["file"] = filename
        summaries.append(summary)
    return summaries


def tail_text(path: Path, limit: int = 12000) -> str:
    try:
        data = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return data[-limit:]


def summarize_cdp_events(events: list[dict]) -> dict:
    console: list[dict] = []
    exceptions: list[dict] = []
    network_failures: list[dict] = []
    log_entries: list[dict] = []
    renderer_errors: list[str] = []

    for event in events[-500:]:
        method = event.get("method")
        params = event.get("params", {})
        if method == "Runtime.consoleAPICalled":
            values = []
            for arg in params.get("args", [])[:12]:
                values.append(arg.get("value", arg.get("description", arg.get("type", ""))))
            console_type = params.get("type", "")
            console.append({
                "type": console_type,
                "values": values,
                "timestamp": params.get("timestamp"),
            })
            for value in values:
                message = str(value)
                translation_failure = "[WGPU] WGSL compilation " in message
                if (console_type == "error" or translation_failure) and message and message not in renderer_errors:
                    renderer_errors.append(message)
        elif method == "Runtime.exceptionThrown":
            details = params.get("exceptionDetails", {})
            exception = details.get("exception", {})
            exceptions.append({
                "text": details.get("text", ""),
                "description": exception.get("description", ""),
                "url": details.get("url", ""),
                "line": details.get("lineNumber"),
                "column": details.get("columnNumber"),
            })
        elif method == "Network.loadingFailed":
            network_failures.append({
                "request_id": params.get("requestId", ""),
                "type": params.get("type", ""),
                "error_text": params.get("errorText", ""),
                "canceled": params.get("canceled", False),
                "blocked_reason": params.get("blockedReason", ""),
            })
        elif method == "Log.entryAdded":
            entry = params.get("entry", {})
            log_entry = {
                "source": entry.get("source", ""),
                "level": entry.get("level", ""),
                "text": entry.get("text", ""),
                "url": entry.get("url", ""),
                "line": entry.get("lineNumber"),
            }
            log_entries.append(log_entry)
            if log_entry["source"] == "rendering" and log_entry["level"] in ("error", "warning"):
                message = str(log_entry["text"])
                if message and message not in renderer_errors:
                    renderer_errors.append(message)

    return {
        "console": console[-120:],
        "console_first": console[:40],
        "exceptions": exceptions[-80:],
        "network_failures": network_failures[-80:],
        "log_entries": log_entries[-120:],
        "log_entries_first": log_entries[:40],
        "renderer_errors": renderer_errors[:80],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--result-global", default="__STARJUNK_PERF_RESULT__")
    parser.add_argument("--purpose", default="browser_webgpu_smoke")
    parser.add_argument("--expected-profile", default="")
    parser.add_argument("--expected-renderer", default="mobile")
    parser.add_argument("--expected-driver", default="webgpu")
    parser.add_argument("--spirv-dump-dir", default="")
    parser.add_argument(
        "--required-console-prefix",
        action="append",
        default=[],
        help="Require an additional JSON console signal with this prefix.",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    output = Path(args.output).resolve()
    if not (root / "index.html").is_file():
        raise SystemExit(f"Missing exported index.html in {root}")

    http_port = free_port()
    debug_port = free_port()
    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", http_port),
        lambda *handler_args, **handler_kwargs: BenchmarkHandler(
            *handler_args, directory=str(root), **handler_kwargs
        ),
    )
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()

    chrome = find_chrome()
    profile_dir = tempfile.mkdtemp(prefix="starjunk-chrome-")
    profile_path = Path(profile_dir)
    stdout_path = profile_path / "chrome.stdout.log"
    stderr_path = profile_path / "chrome.stderr.log"
    stdout_handle = stdout_path.open("w", encoding="utf-8")
    stderr_handle = stderr_path.open("w", encoding="utf-8")

    url = f"http://127.0.0.1:{http_port}/index.html"
    flags = [
        chrome,
        "--headless=new",
        f"--remote-debugging-port={debug_port}",
        "--remote-allow-origins=*",
        f"--user-data-dir={profile_dir}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-networking",
        "--disable-default-apps",
        "--disable-extensions",
        "--disable-dev-shm-usage",
        "--disable-gpu-sandbox",
        "--ignore-gpu-blocklist",
        "--enable-unsafe-webgpu",
        "--enable-unsafe-swiftshader",
        "--enable-features=Vulkan,WebGPUDeveloperFeatures",
        "--use-angle=swiftshader",
        "--use-vulkan=swiftshader",
        "--window-size=1280,720",
        "about:blank",
    ]
    if os.geteuid() == 0:
        flags.append("--no-sandbox")

    browser = subprocess.Popen(
        flags,
        stdout=stdout_handle,
        stderr=stderr_handle,
        text=True,
    )
    cdp: CDP | None = None
    try:
        ws_url = wait_for_page(debug_port, 30.0)
        cdp = CDP(ws_url)
        for domain in ("Runtime", "Log", "Network", "Page"):
            cdp.call(f"{domain}.enable")

        cdp.call(
            "Page.addScriptToEvaluateOnNewDocument",
            {
                "source": """
window.__STARJUNK_BROWSER_EVENTS__ = [];

(() => {
    const pushWebGPUEvent = (kind, detail) => {
        try {
            const payload = {
                type: kind,
                ...detail
            };
            window.__STARJUNK_BROWSER_EVENTS__.push(payload);
            console.log('STARJUNK_WEBGPU_EVENT_JSON:' + JSON.stringify(payload));
        } catch (_) {}
    };

    if (typeof GPUDevice !== 'undefined' && GPUDevice.prototype) {
        const wrapValidation = (methodName) => {
            const original = GPUDevice.prototype[methodName];
            if (typeof original !== 'function') return;
            GPUDevice.prototype[methodName] = function (...args) {
                const descriptor = args.length > 0 && args[0] && typeof args[0] === 'object' ? args[0] : {};
                const label = String(descriptor.label || '');
                this.pushErrorScope('validation');
                let value;
                try {
                    value = original.apply(this, args);
                } catch (error) {
                    this.popErrorScope().catch(() => {});
                    pushWebGPUEvent('webgpu_validation_throw', {
                        method: methodName,
                        label,
                        message: String(error && error.message ? error.message : error),
                        stack: error && error.stack ? String(error.stack) : ''
                    });
                    throw error;
                }
                this.popErrorScope().then((error) => {
                    if (!error) return;
                    pushWebGPUEvent('webgpu_validation_error', {
                        method: methodName,
                        label,
                        message: String(error.message || error)
                    });
                }).catch((error) => {
                    pushWebGPUEvent('webgpu_validation_scope_error', {
                        method: methodName,
                        label,
                        message: String(error && error.message ? error.message : error)
                    });
                });
                return value;
            };
        };

        for (const method of [
            'createBindGroupLayout',
            'createPipelineLayout',
            'createRenderPipeline',
            'createComputePipeline'
        ]) {
            wrapValidation(method);
        }

        const originalCreateShaderModule = GPUDevice.prototype.createShaderModule;
        if (typeof originalCreateShaderModule === 'function') {
            GPUDevice.prototype.createShaderModule = function (...args) {
                const descriptor = args.length > 0 && args[0] && typeof args[0] === 'object' ? args[0] : {};
                const label = String(descriptor.label || '');
                const module = originalCreateShaderModule.apply(this, args);
                if (module && typeof module.getCompilationInfo === 'function') {
                    module.getCompilationInfo().then((info) => {
                        for (const message of info.messages || []) {
                            if (message.type !== 'error' && message.type !== 'warning') continue;
                            pushWebGPUEvent('webgpu_shader_compilation', {
                                label,
                                severity: String(message.type || ''),
                                message: String(message.message || ''),
                                line_num: Number(message.lineNum || 0),
                                line_pos: Number(message.linePos || 0),
                                offset: Number(message.offset || 0),
                                length: Number(message.length || 0)
                            });
                        }
                    }).catch((error) => {
                        pushWebGPUEvent('webgpu_shader_compilation_info_error', {
                            label,
                            message: String(error && error.message ? error.message : error)
                        });
                    });
                }
                return module;
            };
        }
    }
})();

window.addEventListener('error', (event) => {
    window.__STARJUNK_BROWSER_EVENTS__.push({
        type: 'error',
        message: String(event.message || ''),
        filename: String(event.filename || ''),
        line: event.lineno || 0,
        column: event.colno || 0,
        stack: event.error && event.error.stack ? String(event.error.stack) : ''
    });
});
window.addEventListener('unhandledrejection', (event) => {
    const reason = event.reason;
    window.__STARJUNK_BROWSER_EVENTS__.push({
        type: 'unhandledrejection',
        message: String(reason && reason.message ? reason.message : reason),
        stack: reason && reason.stack ? String(reason.stack) : ''
    });
});
"""
            },
        )
        cdp.call("Page.navigate", {"url": url})

        load_deadline = time.monotonic() + 20.0
        while time.monotonic() < load_deadline:
            state = cdp.evaluate(
                "({ready: document.readyState, href: location.href, engine: typeof Engine, godot: typeof Godot})"
            )
            if state and state.get("href") == url and state.get("ready") == "complete":
                break
            time.sleep(0.1)

        adapter_probe = cdp.evaluate(
            """(async () => {
                const result = {
                    has_navigator_gpu: !!navigator.gpu,
                    adapter: false,
                    info: {},
                    features: [],
                    limits: {}
                };
                if (!navigator.gpu) return result;
                const adapter = await navigator.gpu.requestAdapter();
                if (!adapter) return result;
                result.adapter = true;
                try {
                    const info = adapter.info || {};
                    result.info = {
                        vendor: info.vendor || "",
                        architecture: info.architecture || "",
                        device: info.device || "",
                        description: info.description || ""
                    };
                } catch (_) {}
                try {
                    result.features = Array.from(adapter.features || []).sort();
                } catch (_) {}
                try {
                    const limits = adapter.limits || {};
                    for (const key of [
                        "maxBindGroups",
                        "maxSampledTexturesPerShaderStage",
                        "maxSamplersPerShaderStage",
                        "maxStorageBuffersPerShaderStage",
                        "maxStorageTexturesPerShaderStage",
                        "maxUniformBuffersPerShaderStage",
                        "maxBufferSize",
                        "maxTextureDimension2D",
                        "maxTextureArrayLayers",
                        "maxColorAttachments"
                    ]) {
                        if (limits[key] !== undefined) {
                            result.limits[key] = Number(limits[key]);
                        }
                    }
                } catch (_) {}
                return result;
            })()""",
            await_promise=True,
            timeout=20.0,
        )
        if args.expected_driver == "webgpu" and (
            not adapter_probe or not adapter_probe.get("adapter")
        ):
            raise RuntimeError(f"WebGPU adapter unavailable: {adapter_probe}")

        result_console_prefix = RESULT_CONSOLE_PREFIXES.get(args.result_global, "")
        payload = None
        if result_console_prefix:
            # Once Godot's Wasm main loop starts, Runtime.evaluate can be delayed
            # indefinitely by a busy browser main thread. The benchmark scenes
            # already print structured JSON, so consume that console event
            # directly instead of polling JavaScript state.
            payload = wait_for_console_json(cdp, result_console_prefix, args.timeout)
        else:
            deadline = time.monotonic() + args.timeout
            result_expression = f"window[{json.dumps(args.result_global)}] || null"
            while time.monotonic() < deadline:
                try:
                    payload = cdp.evaluate(result_expression, timeout=2.0)
                except TimeoutError:
                    payload = None
                if payload is not None:
                    break
                time.sleep(0.5)

        browser_events = extract_browser_events(cdp.events)
        spirv_dump_dir = Path(args.spirv_dump_dir).resolve() if args.spirv_dump_dir else None
        spirv_dumps = write_spirv_dumps(cdp.events, spirv_dump_dir)
        if payload is None:
            stdout_handle.flush()
            stderr_handle.flush()
            failure_result = {
                "schema_version": 3,
                "authoritative_performance": False,
                "purpose": args.purpose,
                "browser": Path(chrome).name,
                "adapter_probe": adapter_probe,
                "diagnostics": {
                    "result_global": args.result_global,
                    "result_console_prefix": result_console_prefix,
                    "browser_events": browser_events[-120:],
            "spirv_dumps": spirv_dumps,
                },
                "cdp_events": summarize_cdp_events(cdp.events),
                "chromium_stdout_tail": tail_text(stdout_path),
                "chromium_stderr_tail": tail_text(stderr_path),
                "spirv_dumps": spirv_dumps,
                "error": (
                    f"Timed out waiting for console result {result_console_prefix!r}"
                    if result_console_prefix
                    else f"Timed out waiting for window.{args.result_global}"
                ),
            }
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(failure_result, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(failure_result, indent=2))
            raise TimeoutError(f"Godot WebGPU result {args.result_global!r} was not published")

        required_console_results: dict[str, object] = {}
        missing_console_prefixes: list[str] = []
        for prefix in args.required_console_prefix:
            required_payload = find_console_json(cdp.events, prefix)
            if required_payload is None:
                required_payload = wait_for_console_json(
                    cdp, prefix, min(args.timeout, 20.0)
                )
            if required_payload is None:
                missing_console_prefixes.append(prefix)
            else:
                required_console_results[prefix] = required_payload

        browser_events = extract_browser_events(cdp.events)
        event_summary = summarize_cdp_events(cdp.events)

        result = {
            "schema_version": 3,
            "authoritative_performance": False,
            "purpose": args.purpose,
            "browser": Path(chrome).name,
            "adapter_probe": adapter_probe,
            "payload": payload,
            "cdp_events": event_summary,
            "browser_events": browser_events[-120:],
            "required_console_results": required_console_results,
            "spirv_dumps": spirv_dumps,
        }

        validation_errors = renderer_identity_errors(
            payload, args.expected_renderer, args.expected_driver
        )
        for prefix in missing_console_prefixes:
            validation_errors.append(
                f"Required browser console signal {prefix!r} was not observed"
            )

        renderer_errors = list(event_summary.get("renderer_errors", []))
        for event in browser_events:
            event_type = str(event.get("type", ""))
            if event_type not in (
                "webgpu_validation_error",
                "webgpu_validation_throw",
                "webgpu_shader_compilation",
            ):
                continue
            severity = str(event.get("severity", ""))
            if event_type == "webgpu_shader_compilation" and severity != "error":
                continue
            message = (
                f"{event_type} {event.get('method', '')} "
                f"{event.get('label', '')}: {event.get('message', '')}"
            ).strip()
            if message and message not in renderer_errors:
                renderer_errors.append(message)
        if renderer_errors:
            validation_errors.append(
                "Renderer validation errors observed: " + " | ".join(renderer_errors[:3])
            )

        if args.expected_profile and payload.get("profile") != args.expected_profile:
            validation_errors.append(
                f"Expected profile {args.expected_profile!r}, got {payload.get('profile')!r}"
            )

        if validation_errors:
            result["error"] = "; ".join(validation_errors)

        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, indent=2))

        if validation_errors:
            raise RuntimeError(result["error"])
        return 0
    finally:
        if cdp is not None:
            cdp.close()
        browser.terminate()
        try:
            browser.wait(timeout=5)
        except subprocess.TimeoutExpired:
            browser.kill()
            browser.wait(timeout=5)
        stdout_handle.close()
        stderr_handle.close()
        server.shutdown()
        server.server_close()
        if browser.returncode not in (None, 0, -15):
            print("Chromium stderr:\n" + tail_text(stderr_path))
        shutil.rmtree(profile_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
