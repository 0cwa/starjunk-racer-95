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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--timeout", type=float, default=90.0)
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
        url,
    ]
    if os.geteuid() == 0:
        flags.append("--no-sandbox")

    browser = subprocess.Popen(
        flags,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    cdp: CDP | None = None
    try:
        ws_url = wait_for_page(debug_port, 15.0)
        cdp = CDP(ws_url)
        cdp.call("Runtime.enable")

        adapter_probe = cdp.evaluate(
            """(async () => {
                const result = {has_navigator_gpu: !!navigator.gpu, adapter: false, info: {}};
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
                return result;
            })()""",
            await_promise=True,
            timeout=20.0,
        )
        if not adapter_probe or not adapter_probe.get("adapter"):
            raise RuntimeError(f"WebGPU adapter unavailable: {adapter_probe}")

        deadline = time.monotonic() + args.timeout
        benchmark = None
        while time.monotonic() < deadline:
            benchmark = cdp.evaluate("window.__STARJUNK_PERF_RESULT__ || null")
            if benchmark is not None:
                break
            time.sleep(0.5)
        if benchmark is None:
            raise TimeoutError("Godot WebGPU benchmark did not publish a result")

        renderer = str(benchmark.get("renderer", "")).lower()
        driver = str(benchmark.get("rendering_driver", "")).lower()
        if renderer != "mobile":
            raise RuntimeError(f"Expected Mobile renderer, got {renderer!r}")
        if "webgpu" not in driver:
            raise RuntimeError(f"Expected WebGPU rendering driver, got {driver!r}")
        if benchmark.get("profile") != "browser_smoke":
            raise RuntimeError(f"Expected browser_smoke profile, got {benchmark.get('profile')!r}")

        result = {
            "schema_version": 1,
            "authoritative_performance": False,
            "purpose": "browser_webgpu_smoke",
            "browser": Path(chrome).name,
            "adapter_probe": adapter_probe,
            "benchmark": benchmark,
        }
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(result, indent=2))
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
        server.shutdown()
        server.server_close()
        shutil.rmtree(profile_dir, ignore_errors=True)
        if browser.returncode not in (None, 0, -15):
            stderr = browser.stderr.read() if browser.stderr else ""
            print("Chromium stderr:\n" + stderr[-8000:])


if __name__ == "__main__":
    raise SystemExit(main())
