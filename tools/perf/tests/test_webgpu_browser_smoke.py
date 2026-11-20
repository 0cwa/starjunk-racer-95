import base64
from contextlib import contextmanager
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tools.perf.webgpu_browser_smoke import (
    BrowserRuntimeError,
    RESULT_CONSOLE_PREFIXES,
    SPIRV_DUMP_CONSOLE_PREFIX,
    WEBGPU_EVENT_CONSOLE_PREFIX,
    console_json_from_event,
    extract_browser_events,
    find_console_json,
    main,
    renderer_identity_errors,
    summarize_cdp_events,
    wait_for_console_json,
    write_spirv_dumps,
)


def console_event(value: str) -> dict:
    return {
        "method": "Runtime.consoleAPICalled",
        "params": {
            "type": "log",
            "args": [{"type": "string", "value": value}],
        },
    }


def wasm_exception_event() -> dict:
    return {
        "method": "Runtime.exceptionThrown",
        "params": {
            "exceptionDetails": {
                "text": "Uncaught",
                "exception": {
                    "description": (
                        "RuntimeError: memory access out of bounds\n"
                        "    at wasm://wasm/13fa770e:wasm-function[4842]:0x4d5f18"
                    ),
                },
                "stackTrace": {"callFrames": [{"functionName": "wasm-function[4842]"}]},
            },
        },
    }


class FakeCDP:
    def __init__(self, pending: list[dict], buffered: list[dict] | None = None):
        self.events = list(buffered or [])
        self.pending = list(pending)
        self.received = 0

    def call(self, *args, **kwargs):
        return {}

    def evaluate(self, expression, **kwargs):
        if "document.readyState" in expression:
            return {"ready": "complete", "href": "http://127.0.0.1:18080/index.html"}
        return {"adapter": True}

    def receive_event(self, timeout):
        if not self.pending:
            raise AssertionError("Smoke waited after its terminal event")
        event = self.pending.pop(0)
        self.events.append(event)
        self.received += 1
        return event

    def close(self):
        pass


class WebGPUBrowserSmokeFailureTests(unittest.TestCase):
    playable = {
        "profile": "playable",
        "renderer": "mobile",
        "rendering_driver": "webgpu",
        "frames": 30,
        "vehicle_ready": True,
        "checkpoint_count": 8,
    }

    @contextmanager
    def smoke_run(self, pending, buffered=None):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "index.html").write_text("<!doctype html>", encoding="utf-8")
            output = root / "result.json"
            cdp = FakeCDP(pending, buffered)
            args = [
                "webgpu_browser_smoke.py", "--root", str(root), "--output", str(output),
                "--result-global", "__STARJUNK_PLAYABLE_RESULT__",
                "--expected-profile", "playable",
                "--required-console-prefix", "STARJUNK_SPRITELY_READY_JSON:",
            ]
            module = "tools.perf.webgpu_browser_smoke"
            with (
                mock.patch("sys.argv", args),
                mock.patch(f"{module}.free_port", side_effect=[18080, 18081]),
                mock.patch(f"{module}.http.server.ThreadingHTTPServer"),
                mock.patch(f"{module}.threading.Thread"),
                mock.patch(f"{module}.find_chrome", return_value="chromium"),
                mock.patch(f"{module}.subprocess.Popen") as process,
                mock.patch(f"{module}.wait_for_page", return_value="ws://unused"),
                mock.patch(f"{module}.CDP", return_value=cdp),
                mock.patch("builtins.print"),
            ):
                process.return_value.returncode = -15
                yield output, cdp

    def test_wasm_crash_writes_artifact_without_waiting_for_timeout(self):
        with self.smoke_run([
            wasm_exception_event(),
            console_event("STARJUNK_PLAYABLE_JSON:" + json.dumps(self.playable)),
        ]) as (output, cdp):
            with self.assertRaisesRegex(BrowserRuntimeError, "memory access out of bounds"):
                main()
            self.assertEqual(cdp.received, 1)
            result = json.loads(output.read_text())
            self.assertEqual(result["failure_kind"], "runtime_exception")
            self.assertIn("wasm-function[4842]", result["error"])
            self.assertNotIn("Timed out", result["error"])
            self.assertIsNone(result["payload"])
            self.assertEqual(len(result["cdp_events"]["exceptions"]), 1)
            self.assertFalse(result["authoritative_performance"])

    def test_playable_and_spritely_success_still_pass(self):
        with self.smoke_run([
            console_event("Starting PrototypeRace"),
            console_event("STARJUNK_PLAYABLE_JSON:" + json.dumps(self.playable)),
            console_event('STARJUNK_SPRITELY_READY_JSON:{"ready":true}'),
        ]) as (output, cdp):
            self.assertEqual(main(), 0)
            result = json.loads(output.read_text())
            self.assertEqual(result["payload"], self.playable)
            self.assertEqual(
                result["required_console_results"]["STARJUNK_SPRITELY_READY_JSON:"],
                {"ready": True},
            )
            self.assertNotIn("error", result)
            self.assertEqual(cdp.received, 3)

    def test_buffered_crash_cannot_be_hidden_by_later_success(self):
        events = [wasm_exception_event()]
        events.extend(console_event(f"shader {index}") for index in range(600))
        events.append(console_event("STARJUNK_PLAYABLE_JSON:" + json.dumps(self.playable)))
        cdp = FakeCDP([], events)
        with self.assertRaisesRegex(BrowserRuntimeError, "memory access out of bounds"):
            wait_for_console_json(cdp, "STARJUNK_PLAYABLE_JSON:", 60)
        self.assertEqual(cdp.received, 0)

    def test_error_and_unhandled_rejection_signals_stop_console_wait(self):
        for event_type in ("error", "unhandledrejection"):
            with self.subTest(event_type=event_type):
                event = console_event(WEBGPU_EVENT_CONSOLE_PREFIX + json.dumps({
                    "type": event_type, "message": "Wasm crashed", "stack": "Wasm trap stack",
                }))
                cdp = FakeCDP([event])
                with self.assertRaisesRegex(BrowserRuntimeError, "Wasm trap stack"):
                    wait_for_console_json(cdp, "STARJUNK_PLAYABLE_JSON:", 60)

    def test_summary_retains_startup_and_early_failures_after_shader_noise(self):
        error = console_event("WebGPU pipeline validation failed")
        error["params"]["type"] = "error"
        events = [console_event("Godot starting"), error, wasm_exception_event()]
        events.extend(console_event(f"shader {index}") for index in range(600))
        summary = summarize_cdp_events(events)
        self.assertEqual(summary["console_first"][0]["values"], ["Godot starting"])
        self.assertEqual(summary["console"][-1]["values"], ["shader 599"])
        self.assertEqual(len(summary["console"]), 120)
        self.assertEqual(len(summary["console_first"]), 40)
        self.assertEqual(summary["renderer_errors"], ["WebGPU pipeline validation failed"])
        self.assertIn("memory access out of bounds", summary["exceptions"][0]["description"])
        self.assertEqual(
            summary["exceptions"][0]["stack_trace"]["callFrames"][0]["functionName"],
            "wasm-function[4842]",
        )

    def test_early_renderer_validation_error_still_fails_success_payload(self):
        error = console_event("Invalid bind group")
        error["params"]["type"] = "error"
        buffered = [error] + [console_event(f"shader {index}") for index in range(600)]
        with self.smoke_run([
            console_event("STARJUNK_PLAYABLE_JSON:" + json.dumps(self.playable)),
            console_event('STARJUNK_SPRITELY_READY_JSON:{"ready":true}'),
        ], buffered) as (output, _cdp):
            with self.assertRaisesRegex(RuntimeError, "Renderer validation errors observed"):
                main()
            result = json.loads(output.read_text())
            self.assertEqual(result["payload"], self.playable)
            self.assertIn("Invalid bind group", result["error"])


class WebGPUBrowserSmokeParsingTests(unittest.TestCase):
    def test_renderer_identity_accepts_webgpu_and_compatibility_profiles(self):
        self.assertEqual(
            renderer_identity_errors(
                {"renderer": "mobile", "rendering_driver": "webgpu"},
                "mobile",
                "webgpu",
            ),
            [],
        )
        self.assertEqual(
            renderer_identity_errors(
                {"renderer": "gl_compatibility", "rendering_driver": "opengl3"},
                "gl_compatibility",
                "opengl3",
            ),
            [],
        )

    def test_renderer_identity_reports_mismatches_once(self):
        self.assertEqual(
            renderer_identity_errors(
                {"renderer": "mobile", "rendering_driver": "webgpu"},
                "gl_compatibility",
                "opengl3",
            ),
            [
                "Expected renderer 'gl_compatibility', got 'mobile'",
                "Expected rendering driver 'opengl3', got 'webgpu'",
            ],
        )

    def test_playable_result_prefix_is_registered(self):
        self.assertEqual(
            RESULT_CONSOLE_PREFIXES["__STARJUNK_PLAYABLE_RESULT__"],
            "STARJUNK_PLAYABLE_JSON:",
        )

    def test_reconstructs_chunked_spirv_dump(self):
        raw = b"\x03\x02#\x07" + bytes(range(32))
        encoded = base64.b64encode(raw).decode("ascii")
        midpoint = len(encoded) // 2
        prefix = "SceneForwardMobileShaderRD:0|1|raw"
        events = [
            console_event(
                f"{SPIRV_DUMP_CONSOLE_PREFIX}{prefix}|1|2|{encoded[midpoint:]}"
            ),
            console_event(
                f"{SPIRV_DUMP_CONSOLE_PREFIX}{prefix}|0|2|{encoded[:midpoint]}"
            ),
        ]
        with tempfile.TemporaryDirectory() as temp_dir:
            summaries = write_spirv_dumps(events, Path(temp_dir))
            self.assertEqual(len(summaries), 1)
            self.assertTrue(summaries[0]["complete"])
            self.assertEqual(summaries[0]["size_bytes"], len(raw))
            dumped = Path(temp_dir, summaries[0]["file"]).read_bytes()
            self.assertEqual(dumped, raw)

    def test_finds_structured_boot_result_from_console(self):
        payload = {
            "profile": "boot",
            "renderer": "mobile",
            "rendering_driver": "webgpu",
            "frames": 8,
        }
        events = [
            console_event("unrelated"),
            console_event("STARJUNK_WEBGPU_BOOT_JSON:" + json.dumps(payload)),
        ]
        self.assertEqual(
            find_console_json(events, "STARJUNK_WEBGPU_BOOT_JSON:"),
            payload,
        )

    def test_ignores_malformed_prefixed_console_json(self):
        event = console_event("STARJUNK_WEBGPU_BOOT_JSON:{not-json")
        self.assertIsNone(
            console_json_from_event(event, "STARJUNK_WEBGPU_BOOT_JSON:")
        )

    def test_reconstructs_spaced_godot_print_line_spirv_dump(self):
        raw = b"\x03\x02#\x07" + bytes(range(16))
        encoded = base64.b64encode(raw).decode("ascii")
        event = console_event(
            f"{SPIRV_DUMP_CONSOLE_PREFIX} SceneForwardMobileShaderRD:0 | 1 | raw | 0 | 1 | {encoded}"
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            summaries = write_spirv_dumps([event], Path(temp_dir))
            self.assertEqual(len(summaries), 1)
            self.assertTrue(summaries[0]["complete"])
            self.assertEqual(summaries[0]["shader"], "SceneForwardMobileShaderRD:0")
            self.assertEqual(summaries[0]["kind"], "raw")
            dumped = Path(temp_dir, summaries[0]["file"]).read_bytes()
            self.assertEqual(dumped, raw)

    def test_extracts_structured_webgpu_events(self):
        validation = {
            "type": "webgpu_validation_error",
            "method": "createRenderPipeline",
            "label": "SceneShader",
            "message": "bad layout",
        }
        warning = {
            "type": "webgpu_shader_compilation",
            "severity": "warning",
            "message": "diagnostic",
        }
        events = [
            console_event(WEBGPU_EVENT_CONSOLE_PREFIX + json.dumps(validation)),
            console_event("noise"),
            console_event(WEBGPU_EVENT_CONSOLE_PREFIX + json.dumps(warning)),
        ]
        self.assertEqual(extract_browser_events(events), [validation, warning])


if __name__ == "__main__":
    unittest.main()
