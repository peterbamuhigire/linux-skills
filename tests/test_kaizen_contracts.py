"""Synthetic B33 Kaizen contracts; never contact a host or execute fixture text."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "kaizen"


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class KaizenContractTests(unittest.TestCase):
    def test_operation_schedule_normal_and_failure_boundaries(self):
        data = load("scheduled-run-boundaries.json")
        self.assertFalse(data["host_mutation"])
        self.assertEqual(data["normal"]["schedule"]["missed_run"], "skip")
        failures = {item["case"]: item for item in data["failure_cases"]}
        self.assertEqual(failures["path-escape"]["expected"], "BLOCKED_PATH_ESCAPE")
        self.assertFalse(failures["path-escape"]["opened"])
        self.assertEqual(failures["duplicate-trigger"]["simulated_runs"], 0)
        self.assertEqual(failures["partial-output"]["expected"], "PARTIAL")

    def test_business_recovery_requires_key_and_application_evidence(self):
        data = load("recovery-failure-domains.json")
        self.assertEqual(data["restore_test"]["status"], "SIMULATED")
        failures = {item["case"]: item for item in data["failure_cases"]}
        self.assertEqual(failures["unavailable-key"]["expected"], "FAILED")
        self.assertFalse(failures["unavailable-key"]["secret_exposed"])
        self.assertEqual(failures["catalogue-only"]["expected"], "NOT_ASSESSED")

    def test_event_review_preserves_count_window_and_redaction(self):
        data = load("agent-event-review.json")
        self.assertEqual(data["aggregation"]["count"], 2)
        self.assertEqual(len(data["aggregation"]["source_locators"]), 2)
        self.assertTrue(data["capture"]["redacted"])
        self.assertFalse(data["redaction"]["trace_echo"])

    def test_runtime_experiment_rejects_tail_and_incomparable_modes(self):
        data = load("runtime-experiment.json")
        self.assertTrue(data["guardrail"]["tail_regression"])
        self.assertEqual(data["guardrail"]["decision"], "REJECT_TREATMENT")
        self.assertEqual(data["comparability_failure"]["decision"], "INCOMPARABLE")
        self.assertEqual(data["evidence_status"]["live_performance"], "NOT_ASSESSED")


if __name__ == "__main__":
    unittest.main()
