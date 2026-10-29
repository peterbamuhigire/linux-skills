"""Negative tests for the two-family specialist matrix gate."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "tests" / "check-distro-matrix.sh"


class DistroMatrixTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="distro-matrix-")
        self.root = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_skill(self, path: str, body: str) -> None:
        target = self.root / path / "SKILL.md"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding="utf-8")

    def run_checker(self) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["SKILLS_ROOT"] = str(self.root)
        return subprocess.run(
            ["bash", str(CHECKER)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
            timeout=5,
        )

    def valid_matrix(self) -> str:
        return """---
name: linux-sample
---
## Distro support

| Topic | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package | apt | dnf |

## Workflow
Do the work.
"""

    def valid_bash_matrix(self) -> str:
        return """---
name: linux-bash-scripting
---
## Distro support

This meta-skill covers Debian/Ubuntu and the RHEL family.

| Need | Don't hardcode | Use this primitive |
|---|---|---|
| Detect | parse os-release | detect_distro via common.sh |
| Install | apt or dnf | pkg_install |
| Query | dpkg or rpm | pkg_is_installed |
| Service | hardcoded name | svc_name |
| Firewall | ufw or firewalld | firewall_allow |
| Web paths | distro-specific | web_conf_dir and web_reload |
| Gate | distro ID | require_family |

## Use When
Review portable scripts.
"""

    def test_real_engine_has_nonempty_two_family_catalogue(self) -> None:
        result = subprocess.run(
            ["bash", str(CHECKER)], capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("passed: 41", result.stdout)
        self.assertIn("failed: 0", result.stdout)

    def test_empty_catalogue_fails_instead_of_passing_vacuously(self) -> None:
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no Linux skill contracts found", result.stdout)

    def test_well_formed_family_table_passes_and_appliance_is_outside_scope(self) -> None:
        self.write_skill("01-test/linux-sample", self.valid_matrix())
        self.write_skill("linux-sysadmin", "---\nname: linux-sysadmin\n---\n## Use When\nRoute work.\n")
        self.write_skill("16-network-equipment/cisco-ios-patterns", "---\nname: cisco-ios-patterns\n---\n## Vendor support\nCisco only.\n")
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("family comparison table", result.stdout)
        self.assertIn("exempt: routing hub", result.stdout)

    def test_missing_matrix_fails(self) -> None:
        self.write_skill("01-test/linux-sample", "---\nname: linux-sample\n---\n## Use When\nWork.\n")
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("must be the exact first H2", result.stdout)

    def test_matrix_after_another_h2_fails(self) -> None:
        body = "---\nname: linux-sample\n---\n## Workflow\nDo work.\n## Distro support\n" + self.valid_matrix().split("## Distro support\n", 1)[1]
        self.write_skill("01-test/linux-sample", body)
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("must be the exact first H2", result.stdout)

    def test_text_mentions_both_families_but_without_a_matrix_fails(self) -> None:
        self.write_skill(
            "01-test/linux-sample",
            "---\nname: linux-sample\n---\n## Distro support\n"
            "Supports Debian/Ubuntu and Fedora/RHEL.\n",
        )
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("needs table rows", result.stdout)

    def test_family_names_outside_the_section_do_not_satisfy_the_gate(self) -> None:
        self.write_skill(
            "01-test/linux-sample",
            "---\nname: linux-sample\n---\n## Distro support\n"
            "| Topic | Family |\n|---|---|\n| Package | native |\n"
            "## Notes\nDebian/Ubuntu and RHEL are discussed below.\n",
        )
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("needs table rows", result.stdout)

    def test_family_words_in_pipe_text_without_a_markdown_table_fail(self) -> None:
        self.write_skill(
            "01-test/linux-sample",
            "---\nname: linux-sample\n---\n## Distro support\n"
            "Debian/Ubuntu | a comparison note\nRHEL family | another note\n"
            "Not a table | just prose\n",
        )
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("needs table rows", result.stdout)

    def test_bash_scripting_primitive_mapping_is_a_valid_special_matrix(self) -> None:
        self.write_skill("10-automation-and-scripting/linux-bash-scripting", self.valid_bash_matrix())
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("common.sh primitive map", result.stdout)

    def test_bash_scripting_missing_a_required_primitive_fails(self) -> None:
        body = self.valid_bash_matrix().replace("| Firewall | ufw or firewalld | firewall_allow |\n", "")
        self.write_skill("10-automation-and-scripting/linux-bash-scripting", body)
        result = self.run_checker()
        self.assertEqual(result.returncode, 1)
        self.assertIn("retain both families and the common.sh primitive map", result.stdout)


if __name__ == "__main__":
    unittest.main()
