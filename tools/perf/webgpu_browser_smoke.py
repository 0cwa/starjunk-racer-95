#!/usr/bin/env python3
from __future__ import annotations

import argparse
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

import websocket


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
        self.ws = websocket.create_connection(url, timeout=5)
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
            message = json.loads(self.ws.recv())
            if message.get("id") == call_id:
                if "error" in message:
                    raise RuntimeError(f"CDP {method} failed: {message['error']}")
                return message.get("result", {})
            self.events.append(message)
        raise TimeoutError(f"Timed out waiting for CDP {method}")

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

    for event in events[-500:]:
        method = event.get("method")
        params = event.get("params", {})
        if method == "Runtime.consoleAPICalled":
            values = []
            for arg in params.get("args", [])[:12]:
                values.append(arg.get("value", arg.get("description", arg.get("type", ""))))
            console.append({
                "type": params.get("type", ""),
                "values": values,
                "timestamp": params.get("timestamp"),
            })
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
            log_entries.append({
                "source": entry.get("source", ""),
                "level": entry.get("level", ""),
                "text": entry.get("text", ""),
                "url": entry.get("url", ""),
                "line": entry.get("lineNumber"),
            })

    return {
        "console": console[-120:],
        "exceptions": exceptions[-80:],
        "network_failures": network_failures[-80:],
        "log_entries": log_entries[-120:],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=90.0)
    parser.add_argument("--result-global", default="__STARJUNK_PERF_RESULT__")
    parser.add_argument("--purpose", default="browser_webgpu_smoke")
    parser.add_argument("--expected-profile", default="")
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
        ws_url = wait_for_page(debug_port, 15.0)
        cdp = CDP(ws_url)
        for domain in ("Runtime", "Log", "Network", "Page"):
            cdp.call(f"{domain}.enable")

        cdp.call(
            "Page.addScriptToEvaluateOnNewDocument",
            {
                "source": """
window.__STARJUNK_BROWSER_EVENTS__ = [];
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
        if not adapter_probe or not adapter_probe.get("adapter"):
            raise RuntimeError(f"WebGPU adapter unavailable: {adapter_probe}")

        deadline = time.monotonic() + args.timeout
        payload = None
        result_expression = f"window[{json.dumps(args.result_global)}] || null"
        while time.monotonic() < deadline:
            payload = cdp.evaluate(result_expression)
            if payload is not None:
                break
            time.sleep(0.5)

        if payload is None:
            diagnostics = cdp.evaluate("""({
                ready_state: document.readyState,
                title: document.title,
                location: location.href,
                body_text: (document.body && document.body.innerText || "").slice(0, 4000),
                body_html: (document.body && document.body.innerHTML || "").slice(0, 12000),
                engine_type: typeof Engine,
                godot_type: typeof Godot,
                godot_config: (typeof GODOT_CONFIG !== 'undefined') ? GODOT_CONFIG : null,
                cross_origin_isolated: self.crossOriginIsolated,
                secure_context: self.isSecureContext,
                starjunk_globals: Object.keys(window).filter(k => k.includes("STARJUNK")).sort(),
                canvas: Array.from(document.querySelectorAll('canvas')).map(c => ({
                    id: c.id, width: c.width, height: c.height,
                    client_width: c.clientWidth, client_height: c.clientHeight
                })),
                status: (() => {
                    const root = document.getElementById('status');
                    const notice = document.getElementById('status-notice');
                    const progress = document.getElementById('status-progress');
                    return {
                        exists: !!root,
                        visibility: root ? getComputedStyle(root).visibility : '',
                        notice_text: notice ? notice.innerText : '',
                        notice_display: notice ? getComputedStyle(notice).display : '',
                        progress_display: progress ? getComputedStyle(progress).display : ''
                    };
                })(),
                scripts: Array.from(document.scripts).map(s => s.src || '[inline]'),
                resources: performance.getEntriesByType('resource').map(r => ({
                    name: r.name,
                    initiator_type: r.initiatorType,
                    duration_ms: r.duration,
                    transfer_size: r.transferSize,
                    decoded_body_size: r.decodedBodySize
                })).slice(-80),
                browser_events: window.__STARJUNK_BROWSER_EVENTS__ || []
            })""")
            stdout_handle.flush()
            stderr_handle.flush()
            failure_result = {
                "schema_version": 2,
                "authoritative_performance": False,
                "purpose": args.purpose,
                "browser": Path(chrome).name,
                "adapter_probe": adapter_probe,
                "diagnostics": diagnostics,
                "cdp_events": summarize_cdp_events(cdp.events),
                "chromium_stdout_tail": tail_text(stdout_path),
                "chromium_stderr_tail": tail_text(stderr_path),
                "error": f"Timed out waiting for window.{args.result_global}",
            }
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(failure_result, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(failure_result, indent=2))
            raise TimeoutError(f"Godot WebGPU result {args.result_global!r} was not published")

        renderer = str(payload.get("renderer", "")).lower()
        driver = str(payload.get("rendering_driver", "")).lower()
        rendering_api = str(payload.get("rendering_api", "")).lower()

        result = {
            "schema_version": 2,
            "authoritative_performance": False,
            "purpose": args.purpose,
            "browser": Path(chrome).name,
            "adapter_probe": adapter_probe,
            "payload": payload,
            "cdp_events": summarize_cdp_events(cdp.events),
        }

        validation_errors: list[str] = []
        if renderer != "mobile":
            validation_errors.append(f"Expected Mobile renderer, got {renderer!r}")
        if "webgpu" not in rendering_api:
            validation_errors.append(
                f"Expected WebGPU RenderingDevice API, got {rendering_api!r} "
                f"(OS rendering driver label: {driver!r})"
            )
        if driver != "webgpu":
            validation_errors.append(
                f"Expected Web rendering driver label 'webgpu', got {driver!r}"
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
