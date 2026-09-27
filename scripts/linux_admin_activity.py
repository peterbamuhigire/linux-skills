#!/usr/bin/env python3
"""Append minimal local Linux administration events and generate date-ranged reports.

This tool records only explicitly supplied task metadata; it does not monitor the host.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import sys
import uuid
from pathlib import Path
from typing import Any

SCHEMA = "chwezi.system-admin-activity.v1"
ENGINE = "linux-skills"
CATEGORIES = {"inventory", "health_check", "security", "update", "configuration", "backup", "recovery", "incident", "report", "other"}
SCOPES = {"local", "remote", "fleet", "unknown"}
STATUSES = {"succeeded", "no_change", "partial", "failed", "blocked", "not_assessed", "pending_reboot"}
_SECRET = re.compile(r"(?i)(password|passwd|token|secret|api[_-]?key|private[_-]?key|authorization)\s*[:=]")


def default_root() -> Path:
    override = os.environ.get("CHWEZI_ACTIVITY_ROOT")
    if override:
        p = Path(override).expanduser()
        if not p.is_absolute():
            raise ValueError("CHWEZI_ACTIVITY_ROOT must be an absolute path")
        return p
    state = os.environ.get("XDG_STATE_HOME")
    base = Path(state).expanduser() if state else Path.home() / ".local" / "state"
    if not base.is_absolute():
        raise ValueError("XDG_STATE_HOME must be an absolute path")
    return base / "chwezi" / "linux-admin"


def parse_time(value: str | None, *, end: bool = False) -> dt.datetime:
    if value is None:
        date = dt.datetime.now(dt.timezone.utc).date()
        return dt.datetime.combine(date, dt.time.max if end else dt.time.min, tzinfo=dt.timezone.utc)
    raw = value.strip()
    try:
        if len(raw) == 10:
            date = dt.date.fromisoformat(raw)
            return dt.datetime.combine(date, dt.time.max if end else dt.time.min, tzinfo=dt.timezone.utc)
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("timestamp must include a timezone")
        return parsed.astimezone(dt.timezone.utc)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"invalid date/time {value!r}: {exc}") from exc


def validate_ref(value: str) -> str:
    if not value.strip() or len(value) > 180 or "\n" in value or "\r" in value or ".." in value or _SECRET.search(value):
        raise ValueError("evidence references must be short IDs or relative paths without '..'")
    if Path(value).is_absolute() or value.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:[/\\]", value):
        raise ValueError("evidence references must not contain absolute paths")
    return value


def write_record(args: argparse.Namespace) -> int:
    summary = args.summary.strip()
    if not summary or len(summary) > 500 or "\n" in summary or "\r" in summary:
        raise ValueError("summary must be one non-empty line of at most 500 characters")
    if _SECRET.search(summary):
        raise ValueError("summary resembles a secret-bearing field; remove sensitive values")
    if not args.operation.strip() or len(args.operation) > 120 or "\n" in args.operation or _SECRET.search(args.operation):
        raise ValueError("operation must be a short, single-line label without secret-bearing text")
    refs = [validate_ref(v) for v in args.evidence_ref]
    if len(refs) > 30 or len(args.limitation) > 30:
        raise ValueError("at most 30 evidence references and limitations may be recorded")
    limitations = [v.strip()[:300] for v in args.limitation if v.strip()]
    if len(args.change_ref or "") > 120 or (args.change_ref and ("\r" in args.change_ref or "\n" in args.change_ref)):
        raise ValueError("change reference must be a single-line identifier of at most 120 characters")
    if args.change_ref and (_SECRET.search(args.change_ref) or len(args.change_ref) > 120 or "\n" in args.change_ref):
        raise ValueError("change reference is too long or resembles sensitive data")
    if any(_SECRET.search(value) or "\n" in value or "\r" in value for value in limitations):
        raise ValueError("limitations must be single-line and must not include secret-bearing fields")
    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    event: dict[str, Any] = {
        "schema_version": SCHEMA,
        "event_id": str(uuid.uuid4()),
        "timestamp_utc": now.isoformat().replace("+00:00", "Z"),
        "engine": ENGINE,
        "activity_type": args.category,
        "operation": args.operation.strip()[:120],
        "target_scope": args.target_scope,
        "status": args.status,
        "changed": bool(args.changed),
        "summary": summary,
        "change_ref": args.change_ref.strip()[:120] if args.change_ref else None,
        "evidence_refs": refs,
        "limitations": limitations,
    }
    if not event["operation"]:
        raise ValueError("operation is required")
    root: Path = args.record_root
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = root / f"activity-{now:%Y-%m}.jsonl"
    lock_path = root / ".activity.lock"
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        with os.fdopen(fd, "a", encoding="utf-8") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            out_fd = os.open(destination, os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
            try:
                payload = (json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
                offset = 0
                while offset < len(payload):
                    offset += os.write(out_fd, payload[offset:])
                os.fsync(out_fd)
            finally:
                os.close(out_fd)
    except Exception:
        # fdopen owns and closes the lock descriptor once constructed.
        raise
    print(f"Recorded {event['event_id']} in {destination}")
    return 0


def report(args: argparse.Namespace) -> int:
    start, end = parse_time(args.start), parse_time(args.end, end=True)
    if end < start:
        raise ValueError("--to must be at or after --from")
    root: Path = args.record_root
    events: list[dict[str, Any]] = []
    bad = 0
    roots = [root, *args.include_record_root]
    required = {"schema_version", "event_id", "timestamp_utc", "engine", "activity_type", "operation", "target_scope", "status", "changed", "summary", "change_ref", "evidence_refs", "limitations"}
    for source_root in roots:
        for path in sorted(source_root.glob("activity-*.jsonl")) if source_root.exists() else []:
            try:
                lines = path.read_text(encoding="utf-8").splitlines()
            except OSError:
                bad += 1
                continue
            for line in lines:
                try:
                    item = json.loads(line)
                    if not isinstance(item, dict) or set(item) != required or item.get("schema_version") != SCHEMA:
                        bad += 1
                        continue
                    if not isinstance(item["event_id"], str) or not 1 <= len(item["event_id"]) <= 100 or not isinstance(item["timestamp_utc"], str):
                        bad += 1
                        continue
                    if item["engine"] not in {ENGINE, "windows-admin-engine-skills"} or item["activity_type"] not in CATEGORIES or item["status"] not in STATUSES or item["target_scope"] not in SCOPES:
                        bad += 1
                        continue
                    if (not isinstance(item["operation"], str) or not 1 <= len(item["operation"]) <= 120 or
                        not isinstance(item["changed"], bool) or not isinstance(item["summary"], str) or not 1 <= len(item["summary"]) <= 500 or
                        (item["change_ref"] is not None and (not isinstance(item["change_ref"], str) or len(item["change_ref"]) > 120)) or
                        not isinstance(item["evidence_refs"], list) or len(item["evidence_refs"]) > 30 or
                        not isinstance(item["limitations"], list) or len(item["limitations"]) > 30 or
                        any(not isinstance(ref, str) or len(ref) > 180 for ref in item["evidence_refs"]) or
                        any(not isinstance(note, str) or len(note) > 300 for note in item["limitations"])):
                        bad += 1
                        continue
                    stamp = dt.datetime.fromisoformat(item["timestamp_utc"].replace("Z", "+00:00"))
                    if stamp.tzinfo is None:
                        bad += 1
                        continue
                    if start <= stamp.astimezone(dt.timezone.utc) <= end:
                        events.append(item)
                except (ValueError, KeyError, TypeError, json.JSONDecodeError):
                    bad += 1
    unique = {item["event_id"]: item for item in events}
    events = list(unique.values())
    events.sort(key=lambda e: e["timestamp_utc"])
    counts: dict[str, int] = {}
    for item in events:
        key = str(item.get("status", "unknown"))
        counts[key] = counts.get(key, 0) + 1
    lines = [
        "# System administration activity report",
        "",
        f"Period (UTC): {start.isoformat()} through {end.isoformat()}",
        f"Engines: {ENGINE} and windows-admin-engine-skills when additional record roots are supplied",
        f"Recorded activities: {len(events)}",
        f"Unreadable or malformed records: {bad}",
        "",
        "## Status summary",
        "",
        "| Status | Count |",
        "|---|---:|",
    ]
    lines.extend(f"| {name} | {count} |" for name, count in sorted(counts.items()))
    if not counts:
        lines.append("| No recorded activity | 0 |")
    lines += ["", "## Activity", "", "| UTC time | Engine | Type | Operation | Scope | Status | Changed | Summary | Change ref | Evidence refs | Limitations |", "|---|---|---|---|---|---|---:|---|---|---|---|"]
    for event in events:
        cells = [event.get("timestamp_utc", ""), event.get("engine", ""), event.get("activity_type", ""), event.get("operation", ""), event.get("target_scope", "unknown"), event.get("status", "unknown"), str(bool(event.get("changed"))), event.get("summary", ""), event.get("change_ref") or "", ", ".join(event.get("evidence_refs", [])), "; ".join(event.get("limitations", []))]
        lines.append("| " + " | ".join(str(c).replace("|", "\\|").replace("\r", " ").replace("\n", " ") for c in cells) + " |")
    lines += ["", "This report summarizes engine activity records only. It does not prove that unrecorded host activity did not occur.", ""]
    text = "\n".join(lines)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
        print(f"Wrote {args.output}")
    else:
        print(text)
    return 0 if bad == 0 else 2


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Record Linux engine operations and generate system administration activity reports.")
    parser.add_argument("--record-root", type=Path, default=default_root(), help="absolute activity directory (default: XDG user state)")
    sub = parser.add_subparsers(dest="command", required=True)
    rec = sub.add_parser("record", help="append one minimal activity record")
    rec.add_argument("--category", required=True, choices=sorted(CATEGORIES))
    rec.add_argument("--operation", required=True)
    rec.add_argument("--status", required=True, choices=sorted(STATUSES))
    rec.add_argument("--target-scope", default="local", choices=sorted(SCOPES))
    rec.add_argument("--summary", required=True)
    rec.add_argument("--changed", action="store_true")
    rec.add_argument("--change-ref")
    rec.add_argument("--evidence-ref", action="append", default=[])
    rec.add_argument("--limitation", action="append", default=[])
    rec.set_defaults(run=write_record)
    rep = sub.add_parser("report", help="generate a date-ranged Markdown report")
    rep.add_argument("--from", dest="start")
    rep.add_argument("--to", dest="end")
    rep.add_argument("--output", type=Path)
    rep.add_argument("--include-record-root", action="append", type=Path, default=[], help="also read a second engine's activity directory; may be repeated")
    rep.set_defaults(run=report)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.run(args)
    except (OSError, ValueError, argparse.ArgumentTypeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
