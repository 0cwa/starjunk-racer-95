import base64
import json
from pathlib import Path
import tempfile
import unittest

from tools.perf.webgpu_browser_smoke import (
    RESULT_CONSOLE_PREFIXES,
    SPIRV_DUMP_CONSOLE_PREFIX,
    WEBGPU_EVENT_CONSOLE_PREFIX,
    console_json_from_event,
    extract_browser_events,
    find_console_json,
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


class WebGPUBrowserSmokeParsingTests(unittest.TestCase):
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
