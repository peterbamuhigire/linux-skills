"""Debian automatic security updates: the Ubuntu origin pattern must not be presented as Debian's.

`"${distro_id}:${distro_codename}-security"` matches Ubuntu, whose security suite is named after the
release. On Debian the same pattern expands to `o=Debian,a=bookworm-security`, but `a=` is the Suite
(`oldstable-security` or `stable-security`), so nothing matches and `unattended-upgrade --dry-run` says
`No packages found that can be upgraded unattended` while security updates wait. Found by the
2026-10-31 lab wave in a Debian 12 container (tests/labs/unattended_upgrades_lab.sh proves it live).
This static test keeps the three procedures from regressing without needing a container.
"""
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UBUNTU_PATTERN = '"${distro_id}:${distro_codename}-security"'
DEBIAN_PATTERN = "label=Debian-Security"

PROCEDURES = {
    "provisioning": (
        ROOT / "01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md",
        "## 5. Unattended security upgrades",
    ),
    "hardening checklist": (
        ROOT / "07-security-and-hardening/linux-server-hardening/references/hardening-checklist.md",
        "## Unattended-upgrades",
    ),
    "reference": (
        ROOT / "01-provisioning-and-bootstrap/linux-package-management/references/unattended-upgrades-reference.md",
        "## Allowed-Origins: which suites get patched",
    ),
}


def sections(text: str) -> list[str]:
    """H2 sections of a Markdown document, ignoring '## ' lines inside fenced blocks."""
    parts: list[list[str]] = [[]]
    inside = False
    for line in text.splitlines():
        if line.strip().startswith("```"):
            inside = not inside
        if not inside and line.startswith("## "):
            parts.append([])
        parts[-1].append(line)
    return ["\n".join(part) for part in parts]


def unscoped_ubuntu_patterns(text: str) -> list[str]:
    """Sections that show the Ubuntu pattern without naming Ubuntu anywhere in the same section."""
    return [
        section.splitlines()[0]
        for section in sections(text)
        if UBUNTU_PATTERN in section and "Ubuntu" not in section.replace("${distro_id}", "")
    ]


def section_named(text: str, heading: str) -> str:
    return next(section for section in sections(text) if section.startswith(heading))


class UnattendedUpgradesDocsTests(unittest.TestCase):
    def test_ubuntu_pattern_in_a_section_that_never_names_ubuntu_is_flagged(self) -> None:
        text = f"## Setup\n\n```text\nUnattended-Upgrade::Allowed-Origins {{\n    {UBUNTU_PATTERN};\n}};\n```\n"
        self.assertEqual(unscoped_ubuntu_patterns(text), ["## Setup"])

    def test_ubuntu_pattern_in_a_section_that_names_ubuntu_is_not_flagged(self) -> None:
        text = f"## Setup\n\nUbuntu only:\n\n```text\n{UBUNTU_PATTERN};\n```\n"
        self.assertEqual(unscoped_ubuntu_patterns(text), [])

    def test_a_heading_inside_a_fence_does_not_split_a_section(self) -> None:
        text = f"## Setup\n\nUbuntu:\n\n```bash\n## not a heading\n{UBUNTU_PATTERN};\n```\n"
        self.assertEqual(unscoped_ubuntu_patterns(text), [])

    def test_every_procedure_scopes_the_ubuntu_pattern(self) -> None:
        for name, (path, _heading) in PROCEDURES.items():
            with self.subTest(procedure=name):
                self.assertEqual(unscoped_ubuntu_patterns(path.read_text(encoding="utf-8")), [])

    def test_every_procedure_gives_debian_a_pattern_that_matches_its_security_archive(self) -> None:
        for name, (path, heading) in PROCEDURES.items():
            with self.subTest(procedure=name):
                section = section_named(path.read_text(encoding="utf-8"), heading)
                self.assertIn(DEBIAN_PATTERN, section)
                self.assertIn("Origins-Pattern", section)

    def test_verify_steps_do_not_cut_off_the_allowed_origins_line(self) -> None:
        # `unattended-upgrade --dry-run --debug` prints about 35 lines and the origins line is near the top,
        # so `| tail -N` drops exactly the line the operator needs.
        for name, (path, heading) in PROCEDURES.items():
            section = section_named(path.read_text(encoding="utf-8"), heading)
            for line in section.splitlines():
                if re.search(r"unattended-upgrade\s+--dry-run.*\|\s*tail\b", line):
                    self.fail(f"{name}: dry-run output piped to tail: {line.strip()}")


if __name__ == "__main__":
    unittest.main()
