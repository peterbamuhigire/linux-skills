"""A procedure that names a Debian-only service unit must have its RHEL counterpart in the skill's matrix.

The matrix gate (scripts/tests/check-distro-matrix.sh) asks only that a `## Distro support` section exists.
This test closes one gap it left open: a skill whose commands run `systemctl <verb> ssh` (or `apache2`, `cron`,
`systemd-timesyncd`) while its matrix never names `sshd` (`httpd`, `crond`, `chronyd`). On the RHEL family
those commands fail with `Unit ... not found`, and a reader who substitutes through the matrix finds no row to
substitute from. Found by the 2026-10-31 lab wave: `systemctl reload ssh` exits 5 on Fedora 44.
"""
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Debian-family unit name -> pattern for the RHEL-family counterpart that the matrix must name.
COUNTERPARTS = {
    "ssh": r"\bsshd\b",
    "apache2": r"\bhttpd\b",
    "cron": r"\bcrond\b",
    "systemd-timesyncd": r"\bchronyd?\b",
}
SYSTEMCTL = re.compile(
    r"systemctl\s+(?:--now\s+)?(?:reload|restart|start|stop|status|enable|disable|is-active|is-enabled)"
    r"\s+(?:--now\s+)?([a-z0-9._-]+)"
)
DISTRO_SECTION = re.compile(r"^## Distro support\s*$(.*?)(?=^## )", re.S | re.M)


def fenced_lines(path: Path) -> list[tuple[int, str]]:
    lines, inside = [], False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip().startswith("```"):
            inside = not inside
        elif inside:
            lines.append((number, line))
    return lines


def parity_violations(root: Path) -> list[str]:
    problems: list[str] = []
    for skill_file in sorted(root.glob("[0-9][0-9]-*/linux-*/SKILL.md")):
        section = DISTRO_SECTION.search(skill_file.read_text(encoding="utf-8"))
        if not section:
            continue  # the matrix gate reports a missing section
        skill_dir = skill_file.parent
        used: dict[str, str] = {}
        for document in [skill_file, *sorted(skill_dir.glob("references/*.md"))]:
            for number, line in fenced_lines(document):
                for match in SYSTEMCTL.finditer(line):
                    unit = match.group(1).removesuffix(".service")
                    if unit in COUNTERPARTS:
                        used.setdefault(unit, f"{document.relative_to(root)}:{number}")
        for unit, where in used.items():
            if not re.search(COUNTERPARTS[unit], section.group(1)):
                problems.append(
                    f"{skill_dir.name}: `systemctl ... {unit}` at {where}, but its Distro support section "
                    f"does not name the RHEL-family unit ({COUNTERPARTS[unit]})"
                )
    return problems


class DistroParityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="distro-parity-")
        self.root = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def skill(self, matrix_row: str, reference: str) -> None:
        directory = self.root / "01-test" / "linux-sample"
        (directory / "references").mkdir(parents=True)
        (directory / "SKILL.md").write_text(
            "---\nname: linux-sample\n---\n## Distro support\n\n"
            "| Topic | Debian/Ubuntu | RHEL family |\n|---|---|---|\n"
            f"{matrix_row}\n\n## Workflow\nDo it.\n",
            encoding="utf-8",
        )
        (directory / "references" / "steps.md").write_text(reference, encoding="utf-8")

    def test_debian_only_unit_without_counterpart_is_a_violation(self) -> None:
        self.skill("| Package | apt | dnf |", "```bash\nsudo systemctl reload ssh\n```\n")
        problems = parity_violations(self.root)
        self.assertEqual(len(problems), 1)
        self.assertIn("steps.md:2", problems[0])
        self.assertIn("sshd", problems[0])

    def test_matrix_row_naming_the_rhel_unit_clears_it(self) -> None:
        self.skill("| SSH unit | ssh | sshd |", "```bash\nsudo systemctl reload ssh\n```\n")
        self.assertEqual(parity_violations(self.root), [])

    def test_sshd_config_filename_is_not_the_unit_name(self) -> None:
        self.skill("| SSH files | /etc/ssh/sshd_config | identical |", "```bash\nsudo systemctl reload ssh\n```\n")
        self.assertEqual(len(parity_violations(self.root)), 1)

    def test_prose_outside_a_fenced_block_is_not_a_command(self) -> None:
        self.skill("| Package | apt | dnf |", "Run `systemctl reload ssh` on Debian.\n")
        self.assertEqual(parity_violations(self.root), [])

    def test_the_rhel_unit_alone_needs_no_counterpart(self) -> None:
        self.skill("| Package | apt | dnf |", "```bash\nsudo systemctl reload sshd\n```\n")
        self.assertEqual(parity_violations(self.root), [])

    def test_real_engine_has_no_unpaired_service_units(self) -> None:
        self.assertEqual(parity_violations(ROOT), [])


if __name__ == "__main__":
    unittest.main()
