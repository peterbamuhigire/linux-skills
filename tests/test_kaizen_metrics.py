"""Unit tests for bounded routing and documentation metrics."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
METRICS_PATH = ROOT / "scripts" / "kaizen_metrics.py"
SPEC = importlib.util.spec_from_file_location("kaizen_metrics_tests", METRICS_PATH)
assert SPEC is not None and SPEC.loader is not None
METRICS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(METRICS)


class KaizenMetricsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="kaizen-metrics-")
        self.root = Path(self.tempdir.name)
        (self.root / "scripts").mkdir()
        (self.root / "tests" / "fixtures").mkdir(parents=True)
        (self.root / "docs" / "sources").mkdir(parents=True)
        (self.root / "scripts" / "routing_smoke_test.py").write_text(
            (ROOT / "scripts" / "routing_smoke_test.py").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        self.write_skill(
            "alpha",
            """---
name: linux-alpha
description: Alpha procedures for blue widgets and calibration.
---
## Use When
Handle blue widgets and calibration.

## Workflow
Inspect the setting.

## References
[missing](missing.md) [anchor](#not-here) [absolute](/home/example/skill.md) [external](https://example.invalid/x)

## References
Second reference section.

## Worked Example
First paragraph line one.
line two.

Second paragraph.
""",
        )
        self.write_skill(
            "beta",
            """---
name: linux-beta
description: Beta procedures for green widgets and alignment.
---
## Distro support
| Topic | Debian/Ubuntu | RHEL family |
|---|---|---|
| package | apt | dnf |
## Worked Example
One concise example.
""",
        )
        self.write_fixtures(
            [
                {"id": "p1", "kind": "positive", "expected": "linux-alpha", "prompt": "blue widgets calibration"},
                {"id": "p2", "kind": "positive", "expected": "linux-alpha", "prompt": "calibrate blue widget"},
                {"id": "p3", "kind": "positive", "expected": "linux-alpha", "prompt": "blue widgets and calibration steps"},
                {"id": "n1", "kind": "negative", "expected": "linux-beta", "forbidden": ["linux-alpha"], "prompt": "green widgets alignment"},
                {"id": "n2", "kind": "negative", "expected": "linux-beta", "forbidden": ["linux-alpha"], "prompt": "align a green widget"},
                {"id": "n3", "kind": "negative", "expected": "linux-alpha", "forbidden": ["linux-beta"], "prompt": "blue widgets calibration"},
                {"id": "n4", "kind": "negative", "expected": "linux-alpha", "forbidden": ["linux-beta"], "prompt": "calibrate a blue widget"},
            ]
        )

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_skill(self, name: str, body: str) -> None:
        path = self.root / "01-test" / f"linux-{name}" / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")

    def write_fixtures(self, fixtures: list[dict[str, object]]) -> None:
        (self.root / "tests" / "fixtures" / "routing.json").write_text(
            json.dumps(fixtures), encoding="utf-8"
        )

    def test_routing_reports_precision_at_1_and_3_separately_and_owned_coverage(self) -> None:
        skills = METRICS.active_skill_files(self.root)
        result = METRICS.routing_metrics(self.root, skills)
        self.assertEqual(result["expected_target_at_1"]["total"], 7)
        self.assertEqual(result["expected_target_at_3"]["total"], 7)
        self.assertEqual(result["owned_negatives"]["fixture_count"], 4)
        self.assertEqual(result["coverage"]["skills_meeting_3_positive_and_2_owned_negative"], 1)
        self.assertEqual(result["coverage"]["per_skill"]["linux-alpha"], {"positive": 3, "owned_negative": 2})

    def test_worked_example_paragraphs_and_duplicate_contract_heading_are_counted(self) -> None:
        skills = METRICS.active_skill_files(self.root)
        examples, duplicates = METRICS.worked_examples_and_duplicates(skills, self.root)
        self.assertEqual(examples["skills_with_example"], 2)
        alpha = next(row for row in examples["per_skill"] if row["skill"] == "linux-alpha")
        self.assertEqual(alpha["paragraphs"], 2)
        self.assertEqual(alpha["nonblank_lines"], 3)
        self.assertEqual(duplicates["skills_with_duplicates"], 1)
        self.assertEqual(duplicates["records"][0]["headings"], {"references": 2})

    def test_local_links_distinguish_broken_targets_absolute_paths_and_external(self) -> None:
        result = METRICS.link_metrics(self.root)
        self.assertEqual(result["machine_specific_absolute_count"], 1)
        self.assertEqual(result["dangling_local_path_count"], 1)
        self.assertEqual(result["dangling_local_anchor_count"], 1)
        self.assertEqual(result["external_links"], 1)
        self.assertEqual(result["external_reachability"], "NOT_ASSESSED")

    def test_expired_source_review_date_is_scoped_to_source_record(self) -> None:
        path = self.root / "docs" / "sources" / "register.md"
        path.write_text(
            "| S1 | reviewed; next review 2026-10-28 |\n"
            "| S2 | reviewed; next review 2026-11-01 |\n"
            "| S3 | advisory due date 2026-10-01 |\n",
            encoding="utf-8",
        )
        result = METRICS.source_review_metrics(self.root, date(2026, 10, 29))
        self.assertEqual(result["dated_source_records"], 2)
        self.assertEqual(result["expired_source_records"], 1)

    def test_duplicate_fixture_ids_are_visible_to_metrics(self) -> None:
        fixtures = json.loads((self.root / "tests" / "fixtures" / "routing.json").read_text(encoding="utf-8"))
        fixtures.append(dict(fixtures[0]))
        self.write_fixtures(fixtures)
        result = METRICS.routing_metrics(self.root, METRICS.active_skill_files(self.root))
        self.assertEqual(result["duplicate_or_missing_fixture_ids"], ["p1"])

    def test_hygiene_gate_accepts_unchanged_existing_debt(self) -> None:
        baseline = {
            "as_of": "2026-10-29",
            "scope": {"skills": "s", "routing": "r", "owned_negative": "n", "coverage_threshold": "c"},
            "links": {
                "scope": "inline links",
                "machine_specific_absolute": [{"path": "a.md", "line": 3, "target": "/home/a"}],
                "dangling_local_paths": [{"path": "old.md", "line": 1, "target": "missing.md"}],
                "dangling_local_anchors": [{"path": "old.md", "line": 2, "target": "#missing"}],
                "dangling_local_path_count": 2,
                "dangling_local_anchor_count": 1,
            },
            "duplicate_contract_headings": {
                "definition": "canonical H2",
                "records": [{"path": "a/SKILL.md", "headings": {"references": 2}}],
            },
            "source_review_dates": {
                "scope": "source rows",
                "records": [{"path": "docs/sources.md", "source_ids": ["LSR01"], "review_date": "2026-10-01", "expired": True}],
            },
        }
        current = json.loads(json.dumps(baseline))
        current["links"]["machine_specific_absolute"][0]["line"] = 19
        result = METRICS.compare_hygiene_to_baseline(current, baseline)
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["dangling_local_links"]["current_paths"], 2)

    def test_hygiene_gate_fails_for_new_machine_link_and_duplicate_even_when_other_debt_is_fixed(self) -> None:
        baseline = {
            "as_of": "2026-10-29",
            "scope": {"skills": "s", "routing": "r", "owned_negative": "n", "coverage_threshold": "c"},
            "links": {
                "scope": "inline links",
                "machine_specific_absolute": [{"path": "old.md", "line": 1, "target": "/old/path"}],
                "dangling_local_paths": [{"path": "old.md", "line": 2, "target": "missing-old.md"}],
                "dangling_local_anchors": [{"path": "old.md", "line": 3, "target": "#missing-old"}],
                "dangling_local_path_count": 1,
                "dangling_local_anchor_count": 0,
            },
            "duplicate_contract_headings": {
                "definition": "canonical H2",
                "records": [{"path": "old/SKILL.md", "headings": {"references": 2}}],
            },
            "source_review_dates": {
                "scope": "source rows",
                "records": [{"path": "docs/old.md", "source_ids": ["LSR01"], "review_date": "2026-10-01", "expired": True}],
            },
        }
        current = json.loads(json.dumps(baseline))
        current["links"]["machine_specific_absolute"] = [
            {"path": "new.md", "line": 4, "target": "/secret/host/path"}
        ]
        current["links"]["dangling_local_paths"] = [
            {"path": "new.md", "line": 5, "target": "missing-new.md"}
        ]
        current["links"]["dangling_local_anchors"] = [
            {"path": "new.md", "line": 6, "target": "#missing-new"}
        ]
        current["links"]["dangling_local_path_count"] = 0
        current["duplicate_contract_headings"]["records"] = [
            {"path": "new/SKILL.md", "headings": {"workflow": 2}}
        ]
        current["source_review_dates"]["records"] = [
            {"path": "docs/new.md", "source_ids": ["S22"], "review_date": "2026-10-28", "expired": True}
        ]
        result = METRICS.compare_hygiene_to_baseline(current, baseline)
        self.assertEqual(result["status"], "fail")
        self.assertEqual(result["machine_specific_links"]["new_records"], [
            {"path": "new.md", "target": "/secret/host/path", "new_occurrences": 1}
        ])
        self.assertEqual(result["duplicate_contract_headings"]["new_records"], [
            {"path": "new/SKILL.md", "heading": "workflow", "new_occurrences": 2}
        ])
        self.assertEqual(result["dangling_local_paths"]["new_records"], [
            {"path": "new.md", "target": "missing-new.md", "new_occurrences": 1}
        ])
        self.assertEqual(result["dangling_local_anchors"]["new_records"], [
            {"path": "new.md", "target": "#missing-new", "new_occurrences": 1}
        ])
        self.assertEqual(result["expired_source_reviews"]["new_records"], [
            {"path": "docs/new.md", "source_ids": ["S22"], "review_date": "2026-10-28", "new_occurrences": 1}
        ])

    def test_hygiene_gate_fails_closed_when_metric_scope_changes(self) -> None:
        baseline = {
            "as_of": "2026-10-29",
            "scope": {"skills": "old", "routing": "r", "owned_negative": "n", "coverage_threshold": "c"},
            "links": {
                "scope": "inline links",
                "machine_specific_absolute": [],
                "dangling_local_paths": [],
                "dangling_local_anchors": [],
            },
            "duplicate_contract_headings": {"definition": "canonical H2", "records": []},
            "source_review_dates": {"scope": "source rows", "records": []},
        }
        current = json.loads(json.dumps(baseline))
        current["scope"]["skills"] = "new"
        result = METRICS.compare_hygiene_to_baseline(current, baseline)
        self.assertEqual(result["status"], "fail")
        self.assertFalse(result["same_scope"])

    def test_reference_changes_count_as_touched_skill_coverage(self) -> None:
        skills = METRICS.active_skill_files(self.root)
        coverage = {
            "per_skill": {
                "linux-alpha": {"positive": 3, "owned_negative": 2},
                "linux-beta": {"positive": 1, "owned_negative": 0},
            }
        }

        def git_output(args: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
            if "diff" in args:
                self.assertEqual(args[-1], "2ce755a")
            stdout = "01-test/linux-alpha/references/guide.md\n" if "diff" in args else ""
            return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")

        with patch.object(METRICS.subprocess, "run", side_effect=git_output):
            result = METRICS.touched_skill_metrics(self.root, skills, coverage, "2ce755a")
        self.assertEqual(result["touched_skills"], ["linux-alpha"])
        self.assertEqual(result["coverage"], {"linux-alpha": {"positive": 3, "owned_negative": 2}})


if __name__ == "__main__":
    unittest.main()
