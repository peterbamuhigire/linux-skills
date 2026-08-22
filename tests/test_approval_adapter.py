import json
import unittest
from pathlib import Path


class ApprovalAdapterTests(unittest.TestCase):
    def test_privileged_linux_actions_are_l3(self):
        payload = json.loads((Path(__file__).parents[1] / "docs" / "approval-adapter.json").read_text(encoding="utf-8"))
        self.assertEqual(payload["engine"], "linux")
        actions = {item["action_type"]: item for item in payload["actions"]}
        for action_type in ("linux.privileged.command.apply", "linux.firewall.change", "linux.secret.change"):
            action = actions[action_type]
            self.assertEqual(action["class"], "L3")
            self.assertTrue(action["requires_dual_approval"])
            self.assertTrue(action["rollback"] and action["verification"])


if __name__ == "__main__":
    unittest.main()
