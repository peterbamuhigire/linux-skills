"""Regression tests for the contract validator's machine-readable result.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
"""

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate_skills.py"


def test_baseline_count_mismatch_is_reported_as_a_failure(tmp_path: Path) -> None:
    root = tmp_path / "empty-engine"
    root.mkdir()
    baseline = tmp_path / "baseline.json"
    baseline.write_text(
        json.dumps(
            {
                "expected_active_skill_count": 1,
                "expected_template_count": 0,
                "failure_counts": {},
            }
        ),
        encoding="utf-8",
    )

    result = subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "--root",
            str(root),
            "--baseline",
            str(baseline),
            "--json",
        ],
        capture_output=True,
        text=True,
        check=False,
    )

    report = json.loads(result.stdout)
    assert result.returncode == 1
    assert report["baseline_match"] is False
    assert report["failure_counts"] == {"active-count": 1}

