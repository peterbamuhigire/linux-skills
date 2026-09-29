"""Linux-host tests for the cross-engine activity ledger and report CLI."""

import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

import pytest


pytestmark = pytest.mark.skipif(
    sys.platform == "win32",
    reason="linux_admin_activity.py imports fcntl for file locking; fcntl exists only on POSIX hosts",
)

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "linux_admin_activity.py"


def run_cli(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--record-root", str(root), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def test_record_writes_private_jsonl_and_report_preserves_outcome(tmp_path: Path) -> None:
    root = tmp_path / "state" / "activity"
    recorded = run_cli(
        root,
        "record",
        "--category",
        "security",
        "--operation",
        "review local controls",
        "--status",
        "partial",
        "--target-scope",
        "local",
        "--summary",
        "Reviewed <system> | two checks remain.",
        "--evidence-ref",
        "case-001",
        "--limitation",
        "One source was unavailable.",
    )
    assert recorded.returncode == 0, recorded.stderr
    files = list(root.glob("activity-*.jsonl"))
    assert len(files) == 1
    assert root.stat().st_mode & 0o777 == 0o700
    assert files[0].stat().st_mode & 0o777 == 0o600

    event = json.loads(files[0].read_text(encoding="utf-8").splitlines()[0])
    assert event["status"] == "partial"
    assert event["changed"] is False
    assert event["evidence_refs"] == ["case-001"]
    assert event["timestamp_utc"].endswith("Z")

    now = dt.datetime.now(dt.timezone.utc).date().isoformat()
    report = run_cli(root, "report", "--from", now, "--to", now)
    assert report.returncode == 0, report.stderr
    assert "Recorded activities: 1" in report.stdout
    assert "| partial |" in report.stdout
    assert "&lt;system&gt; \\| two checks remain." in report.stdout
    assert "case-001" in report.stdout


def test_report_combines_windows_events_and_keeps_failed_states(tmp_path: Path) -> None:
    linux_root = tmp_path / "linux"
    windows_root = tmp_path / "windows"
    linux_root.mkdir()
    windows_root.mkdir()
    timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    windows_event = {
        "schema_version": "chwezi.system-admin-activity.v1",
        "event_id": "windows-001",
        "timestamp_utc": timestamp,
        "engine": "windows-admin-engine-skills",
        "activity_type": "update",
        "operation": "review update history",
        "target_scope": "local",
        "status": "failed",
        "changed": False,
        "summary": "Update history could not be read.",
        "change_ref": None,
        "evidence_refs": [],
        "limitations": ["Access denied by the current account."],
    }
    (windows_root / f"activity-{dt.datetime.now(dt.timezone.utc):%Y-%m}.jsonl").write_text(
        json.dumps(windows_event) + "\n", encoding="utf-8"
    )

    now = dt.datetime.now(dt.timezone.utc).date().isoformat()
    report = run_cli(
        linux_root,
        "report",
        "--from",
        now,
        "--to",
        now,
        "--include-record-root",
        str(windows_root),
        "--include-record-root",
        str(windows_root),
    )
    assert report.returncode == 0, report.stderr
    assert "Recorded activities: 1" in report.stdout
    assert "windows-admin-engine-skills" in report.stdout
    assert "| failed |" in report.stdout
    assert "Access denied by the current account." in report.stdout


def test_malformed_record_is_reported_and_returns_nonzero(tmp_path: Path) -> None:
    root = tmp_path / "activity"
    root.mkdir()
    stamp = dt.datetime.now(dt.timezone.utc)
    (root / f"activity-{stamp:%Y-%m}.jsonl").write_text("{bad json}\n", encoding="utf-8")

    now = stamp.date().isoformat()
    report = run_cli(root, "report", "--from", now, "--to", now)
    assert report.returncode == 2
    assert "Unreadable or malformed records: 1" in report.stdout


@pytest.mark.parametrize(
    "overrides",
    [
        {"evidence_refs": ["/etc/shadow"]},
        {"evidence_refs": ["../private/host.txt"]},
        {"evidence_refs": ["token: sample-value"]},
        {"limitations": ["authorization: private-value"]},
        {"limitations": ["line one\nline two"]},
        {"summary": "token: sample-value"},
    ],
)
def test_report_rejects_schema_invalid_imported_text(tmp_path: Path, overrides: dict[str, object]) -> None:
    root = tmp_path / "activity"
    root.mkdir()
    stamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    event: dict[str, object] = {
        "schema_version": "chwezi.system-admin-activity.v1",
        "event_id": "imported-invalid-001",
        "timestamp_utc": stamp.isoformat().replace("+00:00", "Z"),
        "engine": "windows-admin-engine-skills",
        "activity_type": "inventory",
        "operation": "review inventory status",
        "target_scope": "local",
        "status": "succeeded",
        "changed": False,
        "summary": "Read-only review completed.",
        "change_ref": None,
        "evidence_refs": [],
        "limitations": [],
    }
    event.update(overrides)
    (root / f"activity-{stamp:%Y-%m}.jsonl").write_text(json.dumps(event) + "\n", encoding="utf-8")

    now = stamp.date().isoformat()
    report = run_cli(root, "report", "--from", now, "--to", now)
    assert report.returncode == 2
    assert "Recorded activities: 0" in report.stdout
    assert "Unreadable or malformed records: 1" in report.stdout
    assert "sample-value" not in report.stdout


@pytest.mark.parametrize(
    "summary",
    ["", "token: sample-value", "line one\nline two"],
)
def test_record_rejects_empty_secret_like_and_multiline_summaries(tmp_path: Path, summary: str) -> None:
    result = run_cli(
        tmp_path / "activity",
        "record",
        "--category",
        "security",
        "--operation",
        "review controls",
        "--status",
        "failed",
        "--summary",
        summary,
    )
    assert result.returncode == 2
    assert "error:" in result.stderr
    assert not (tmp_path / "activity").exists()
