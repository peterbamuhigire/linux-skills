"""Static guard: shipped scripts may source only the shared library by variable.

A script run as root that ``source``s a path held in a variable hands root to whoever
can write that path. Configuration files go through ``sk_source_trusted_config`` in
scripts/lib/common.sh, which refuses symlinks and files or directories that group or
others can write. This test fails when a shipped script sources any other variable path.

The unit tests for the helper itself are in scripts/tests/common-sh.test.sh.

Author: Peter Bamuhigire <techguypeter.com> +256784464178
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_VARIABLES = {"SK_LIB"}

# `source "$X"`, `. "$X"`, `source ${X}` at the start of a command, including after
# `;`, `&&`, `||`, `then`, `do` or an opening parenthesis.
DYNAMIC_SOURCE = re.compile(
    r"""(?:^|[;&|(]|\bthen\b|\bdo\b)\s*(?:source|\.)\s+["']?\$\{?([A-Za-z_][A-Za-z0-9_]*)"""
)


def shipped_scripts() -> list[Path]:
    paths = set(ROOT.glob("scripts/*.sh"))
    paths.add(ROOT / "scripts" / "install-skills-bin")
    paths.update(ROOT.glob("*/*/scripts/*.sh"))
    return sorted(path for path in paths if path.is_file())


def dynamic_sources(text: str) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    for number, line in enumerate(text.splitlines(), start=1):
        if line.lstrip().startswith("#"):
            continue
        for match in DYNAMIC_SOURCE.finditer(line):
            found.append((number, match.group(1)))
    return found


class ScriptTrustBoundaryTests(unittest.TestCase):
    def test_scan_covers_the_shipped_scripts(self) -> None:
        names = {path.name for path in shipped_scripts()}
        for expected in ("sk-mysql-backup.sh", "sk-pg-backup.sh", "install-skills-bin", "sk-nft-apply.sh"):
            self.assertIn(expected, names)

    def test_detector_finds_the_patterns_it_guards_against(self) -> None:
        samples = [
            'source "$CONFIG_FILE"',
            '    . "$CONFIG_FILE"',
            'if [[ -f "$F" ]]; then source "$F"; fi',
            "[[ -r $CONF ]] && source ${CONF}",
        ]
        for sample in samples:
            with self.subTest(sample=sample):
                self.assertTrue(dynamic_sources(sample), sample)
        self.assertEqual(dynamic_sources('source "$SK_LIB" || exit 5'), [(1, "SK_LIB")])
        self.assertEqual(dynamic_sources("# source $CONFIG_FILE in a comment"), [])

    def test_no_script_sources_a_variable_path_other_than_the_library(self) -> None:
        offenders: list[str] = []
        for path in shipped_scripts():
            text = path.read_text(encoding="utf-8")
            for number, variable in dynamic_sources(text):
                if variable not in ALLOWED_VARIABLES:
                    offenders.append(f"{path.relative_to(ROOT)}:{number}: sources ${variable}")
        self.assertEqual(
            offenders,
            [],
            "Load configuration with sk_source_trusted_config, not source: " + "; ".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()
