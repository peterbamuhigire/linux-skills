import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "validate_safe_operation_fixture.py"
SPEC = importlib.util.spec_from_file_location("safe_operation_fixture_validator", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class SafeOperationFixtureTests(unittest.TestCase):
    def load_fixture(self):
        fixture_path = ROOT / "tests" / "fixtures" / "safe-operation-evidence.json"
        return json.loads(fixture_path.read_text(encoding="utf-8"))

    def test_fixture_is_valid_and_covers_representative_domains(self):
        self.assertEqual(MODULE.validate_data(self.load_fixture()), [])

    def test_host_mutation_is_rejected(self):
        fixture = copy.deepcopy(self.load_fixture())
        fixture["scenarios"][0]["host_mutation"] = True
        errors = MODULE.validate_data(fixture)
        self.assertTrue(any("host_mutation must be false" in error for error in errors))

    def test_system_and_production_evidence_remain_unassessed(self):
        fixture = self.load_fixture()
        self.assertEqual(fixture["evidence_status"]["system"], "NOT ASSESSED")
        self.assertEqual(fixture["evidence_status"]["production"], "NOT ASSESSED")


if __name__ == "__main__":
    unittest.main()
