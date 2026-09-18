import unittest

from tools.perf.compare import compare

class CompareTests(unittest.TestCase):
    def setUp(self):
        self.identity = {
            "scenario": "renderer_torture",
            "scenario_version": 1,
            "profile": "default",
            "renderer": "mobile",
            "rendering_driver": "vulkan",
            "runner_id": "gpu-a",
            "settings_hash": "abc",
        }
        self.budgets = {
            "metrics": {
                "frame_ms_p95": {"max_relative_regression": 0.08},
                "frame_ms_p99": {"max_relative_regression": 0.12},
            }
        }

    def result(self, p95=10.0, p99=12.0):
        return {**self.identity, "frame_ms_p95": p95, "frame_ms_p99": p99}

    def test_equal_passes(self):
        self.assertEqual(compare(self.result(), self.result(), self.budgets), [])

    def test_small_change_passes(self):
        self.assertEqual(compare(self.result(), self.result(10.7, 13.0), self.budgets), [])

    def test_regression_fails(self):
        failures = compare(self.result(), self.result(11.0, 12.0), self.budgets)
        self.assertEqual(len(failures), 1)

    def test_identity_mismatch_refuses_comparison(self):
        current = self.result()
        current["runner_id"] = "gpu-b"
        with self.assertRaises(ValueError):
            compare(self.result(), current, self.budgets)

    def test_missing_metric_fails(self):
        current = self.result()
        del current["frame_ms_p99"]
        self.assertEqual(len(compare(self.result(), current, self.budgets)), 1)

if __name__ == "__main__":
    unittest.main()
