#!/usr/bin/env python3
"""Validate fixture-only dry-run and rollback evidence without executing a host action.

Author: Peter Bamuhigire <techguypeter.com> +256784464178
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


REQUIRED_ROLLBACK_FIELDS = ("trigger", "last_safe_state", "action", "verification")
REQUIRED_SCENARIO_FIELDS = (
    "id",
    "domain",
    "target",
    "dry_run",
    "host_mutation",
    "planned_action",
    "rollback",
)
EXPECTED_DOMAINS = {"package", "service", "firewall", "storage", "recovery"}
EXPECTED_EVIDENCE = {
    "structural": "PASS",
    "behavioural": "SIMULATED",
    "render": "NOT ASSESSED",
    "system": "NOT ASSESSED",
    "production": "NOT ASSESSED",
}
REQUIRED_EVIDENCE_MANIFEST_FIELDS = ("fixture_id", "source_scope", "observed_at", "review_status")
FORBIDDEN_EXECUTION_MARKERS = (
    "sudo ",
    "systemctl ",
    "firewall-cmd",
    "ufw ",
    "apt ",
    "dnf ",
    "rm -rf",
    "/etc/",
)


def _require_mapping(value: Any, label: str, errors: list[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return {}
    return value


def validate_data(data: Any) -> list[str]:
    """Return deterministic safety/contract errors; never execute fixture text."""

    errors: list[str] = []
    root = _require_mapping(data, "fixture", errors)
    if root.get("data_classification") != "fictional-test-data":
        errors.append("data_classification must be fictional-test-data")
    if root.get("execution_mode") != "read-only-simulation":
        errors.append("execution_mode must be read-only-simulation")
    if root.get("host_mutation") is not False:
        errors.append("fixture host_mutation must be false")

    evidence = _require_mapping(root.get("evidence_status"), "evidence_status", errors)
    for key, expected in EXPECTED_EVIDENCE.items():
        if evidence.get(key) != expected:
            errors.append(f"evidence_status.{key} must be {expected}")

    manifest = _require_mapping(root.get("evidence_manifest"), "evidence_manifest", errors)
    for key in REQUIRED_EVIDENCE_MANIFEST_FIELDS:
        if not isinstance(manifest.get(key), str) or not manifest[key].strip():
            errors.append(f"evidence_manifest.{key} must be non-empty text")

    scenarios = root.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        errors.append("scenarios must be a non-empty list")
        return errors

    seen_domains: set[str] = set()
    seen_ids: set[str] = set()
    for index, raw_scenario in enumerate(scenarios):
        label = f"scenarios[{index}]"
        scenario = _require_mapping(raw_scenario, label, errors)
        missing = [key for key in REQUIRED_SCENARIO_FIELDS if key not in scenario]
        if missing:
            errors.append(f"{label} missing: {', '.join(missing)}")
            continue
        scenario_id = scenario["id"]
        if not isinstance(scenario_id, str) or not scenario_id.startswith("TEST-"):
            errors.append(f"{label}.id must be test-labelled")
        elif scenario_id in seen_ids:
            errors.append(f"{label}.id must be unique")
        else:
            seen_ids.add(scenario_id)
        if not str(scenario["target"]).startswith("fictional-"):
            errors.append(f"{label}.target must be fictional/test-labelled")
        domain = str(scenario["domain"])
        seen_domains.add(domain)
        if domain not in EXPECTED_DOMAINS:
            errors.append(f"{label}.domain is not a representative domain")
        if scenario["dry_run"] is not True:
            errors.append(f"{label}.dry_run must be true")
        if scenario["host_mutation"] is not False:
            errors.append(f"{label}.host_mutation must be false")
        if not isinstance(scenario["planned_action"], str) or not scenario["planned_action"].strip():
            errors.append(f"{label}.planned_action must be non-empty text")
        rollback = _require_mapping(scenario["rollback"], f"{label}.rollback", errors)
        for key in REQUIRED_ROLLBACK_FIELDS:
            if not isinstance(rollback.get(key), str) or not rollback[key].strip():
                errors.append(f"{label}.rollback.{key} must be non-empty text")

        text = json.dumps(scenario, sort_keys=True).lower()
        for marker in FORBIDDEN_EXECUTION_MARKERS:
            if marker in text:
                errors.append(f"{label} contains executable host marker: {marker.strip()}")
        if "command" in scenario or "execute" in scenario:
            errors.append(f"{label} must describe a plan, not an executable command")

    missing_domains = EXPECTED_DOMAINS - seen_domains
    if missing_domains:
        errors.append(f"representative domains missing: {', '.join(sorted(missing_domains))}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    try:
        data = json.loads(args.fixture.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"[FAIL] cannot read fixture: {exc}")
        return 1

    errors = validate_data(data)
    if errors:
        for error in errors:
            print(f"[FAIL] {error}")
        return 1

    for scenario in data["scenarios"]:
        print(f"[PASS] {scenario['id']}: dry-run and rollback fields are safe fixture evidence")
    print("[PASS] fixture-only validation completed; no host action was executed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
