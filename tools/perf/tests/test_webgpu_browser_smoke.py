import json
import unittest

from tools.perf.webgpu_browser_smoke import (
    RESULT_CONSOLE_PREFIXES,
    WEBGPU_EVENT_CONSOLE_PREFIX,
    console_json_from_event,
    extract_browser_events,
    find_console_json,
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
