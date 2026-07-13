#!/usr/bin/env python3
"""Validate the linux-skills catalogue against the July 2026 local contract."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

import yaml


ALLOWED_KEYS = {"name", "description", "license", "allowed-tools", "metadata"}
COMPATIBILITY = ["claude-code", "codex"]
REQUIRED_HEADINGS = (
    "Use When",
    "Do Not Use When",
    "Required Inputs",
    "Workflow",
    "Quality Standards",
    "Anti-Patterns",
    "Outputs",
    "Evidence Produced",
    "Capability Contract",
    "Degraded Mode",
    "Decision Rules",
    "Worked Example",
    "References",
)
MOJIBAKE = ("Ãƒ", "Ã‚", "Ã¢", "â€", "â†", "âœ", "ðŸ", "�")
RUNNER_SPECIFIC = (
    "context: fork",
    "disable-model-invocation",
    "user-invocable:",
    "$ARGUMENTS",
    "activate_skill",
    "chat.customAgentInSubagent.enabled",
)
FRONTMATTER_RE = re.compile(r"^\ufeff?---\r?\n(.*?)\r?\n---\r?\n?", re.DOTALL)
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def active_skills(root: Path) -> list[Path]:
    """Discover active entrypoints; templates use `.tmpl` and are excluded."""
    ignored = {".git", ".venv", "venv", "__pycache__", "templates"}
    return sorted(
        path
        for path in root.rglob("SKILL.md")
        if not any(part in ignored for part in path.relative_to(root).parts)
    )


def templates(root: Path) -> list[Path]:
    directory = root / "templates"
    return sorted(directory.rglob("*")) if directory.exists() else []


def section(body: str, heading: str) -> str | None:
    match = re.search(
        rf"^##\s+{re.escape(heading)}\s*$\r?\n([\s\S]*?)(?=^##\s|\Z)",
        body,
        re.MULTILINE | re.IGNORECASE,
    )
    return match.group(1).strip() if match else None


def record(findings: list[dict], code: str, path: Path, detail: str) -> None:
    findings.append({"code": code, "path": path.as_posix(), "detail": detail})


def parse(path: Path, root: Path, findings: list[dict]) -> tuple[dict, str, str] | None:
    rel = path.relative_to(root)
    raw = path.read_text(encoding="utf-8", errors="replace")
    match = FRONTMATTER_RE.match(raw)
    if not match:
        record(findings, "frontmatter", rel, "missing or malformed YAML frontmatter")
        return None
    try:
        data = yaml.safe_load(match.group(1)) or {}
    except yaml.YAMLError as exc:
        record(findings, "frontmatter-yaml", rel, str(exc).splitlines()[0])
        return None
    if not isinstance(data, dict):
        record(findings, "frontmatter-type", rel, "frontmatter is not a mapping")
        return None
    return data, raw[match.end():], raw


def validate_table(findings: list[dict], rel: Path, code: str, text: str | None, columns: tuple[str, ...]) -> None:
    if not text or "|" not in text:
        record(findings, code, rel, "missing contract table")
        return
    header = next((line.lower() for line in text.splitlines() if line.strip().startswith("|")), "")
    missing = [column for column in columns if column.lower() not in header]
    if missing:
        record(findings, code, rel, f"table is missing columns: {', '.join(missing)}")


def validate_links(root: Path, path: Path, raw: str, findings: list[dict]) -> None:
    rel = path.relative_to(root)
    for target in LINK_RE.findall(raw):
        clean = target.split("#", 1)[0].strip()
        if not clean or "://" in clean or clean.startswith(("mailto:", "#")):
            continue
        if not (path.parent / clean).resolve().exists():
            record(findings, "broken-link", rel, target)


def validate_skill(root: Path, path: Path, findings: list[dict]) -> tuple[str | None, str]:
    rel = path.relative_to(root)
    parsed = parse(path, root, findings)
    if not parsed:
        return None, ""
    frontmatter, body, raw = parsed
    name = frontmatter.get("name")
    description = frontmatter.get("description")
    if name != path.parent.name:
        record(findings, "name-mismatch", rel, f"{name!r} != {path.parent.name!r}")
    unexpected = sorted(set(frontmatter) - ALLOWED_KEYS)
    if unexpected:
        record(findings, "unsupported-frontmatter", rel, ", ".join(unexpected))
    metadata = frontmatter.get("metadata")
    if not isinstance(metadata, dict) or metadata.get("portable") is not True or metadata.get("compatible_with") != COMPATIBILITY:
        record(findings, "portable-metadata", rel, "metadata.portable/compatible_with contract is missing")
    if isinstance(metadata, dict):
        for key in ("author", "author_url", "author_contact"):
            if not metadata.get(key):
                record(findings, "author-attribution", rel, f"metadata.{key} is missing")
    if not isinstance(description, str) or not description.startswith("Use when") or not 80 <= len(description) <= 350:
        record(findings, "description", rel, "description must start with 'Use when' and be 80-350 characters")
    elif not re.search(r"\b(?:linux|skill)-[a-z0-9-]+", description):
        record(findings, "description-neighbour", rel, "description must name a neighbouring skill")
    desc_lines = re.findall(r"^description\s*:", FRONTMATTER_RE.match(raw).group(1), re.MULTILINE)
    if len(desc_lines) != 1:
        record(findings, "description-count", rel, "description must be one frontmatter field")
    if len(raw.splitlines()) > 500:
        record(findings, "line-limit", rel, f"{len(raw.splitlines())} lines")
    for marker in MOJIBAKE:
        if marker in raw:
            record(findings, "encoding-noise", rel, f"contains {marker!r}")
            break
    for snippet in RUNNER_SPECIFIC:
        if snippet in body:
            record(findings, "runner-specific", rel, snippet)
    for heading in REQUIRED_HEADINGS:
        content = section(body, heading)
        if content is None:
            record(findings, "missing-section", rel, heading)
        elif not content:
            record(findings, "empty-section", rel, heading)
    if "<!-- dual-compat-start -->" not in body or "<!-- dual-compat-end -->" not in body:
        record(findings, "portable-markers", rel, "dual compatibility markers are missing")
    validate_table(findings, rel, "input-contract", section(body, "Required Inputs"), ("Artefact", "Source", "Required", "If absent"))
    validate_table(findings, rel, "output-contract", section(body, "Outputs"), ("Artefact", "Consumer", "Acceptance"))
    validate_table(findings, rel, "evidence-contract", section(body, "Evidence Produced"), ("Artefact", "Acceptance"))
    decision = section(body, "Decision Rules")
    if decision is not None and ("|" not in decision or not re.search(r"failure|risk", decision, re.IGNORECASE)):
        record(findings, "decision-contract", rel, "decision table must name a failure or risk avoided")
    workflow = section(body, "Workflow")
    if workflow is not None:
        if len(re.findall(r"^\d+\.\s", workflow, re.MULTILINE)) < 3:
            record(findings, "workflow-order", rel, "workflow needs at least three ordered steps")
        if not re.search(r"stop|abort|block", workflow, re.IGNORECASE):
            record(findings, "workflow-stop", rel, "workflow has no stop condition")
        if not re.search(r"recover|rollback|restore|fallback|revert", workflow, re.IGNORECASE):
            record(findings, "workflow-recovery", rel, "workflow has no recovery behaviour")
    anti = section(body, "Anti-Patterns")
    if anti is not None:
        items = re.findall(r"^\s*[-*]\s+", anti, re.MULTILINE)
        if len(items) < 5 or len(re.findall(r"\bFix:", anti)) < 5:
            record(findings, "anti-patterns", rel, "at least five bullet items must each include 'Fix:'")
    capability = section(body, "Capability Contract") or ""
    if not re.search(r"read|search", capability, re.IGNORECASE) or not re.search(r"authori[sz]|explicit|permission", capability, re.IGNORECASE):
        record(findings, "capability-contract", rel, "minimum capability and permission boundary are missing")
    if re.search(r"(?:^|-)analysis$|(?:^|-)audit$|scanning$", str(name)) and "read-only" not in capability.lower():
        record(findings, "audit-read-only", rel, "audit/analysis/scanning skill must default to read-only")
    references = section(body, "References")
    if references is not None and not LINK_RE.search(references):
        record(findings, "direct-references", rel, "References must contain direct Markdown links")
    first_h2 = re.search(r"^##\s+(.+?)\s*$", body, re.MULTILINE)
    if rel.parts[0][:2].isdigit() and (not first_h2 or first_h2.group(1).lower() != "distro support"):
        record(findings, "distro-matrix-position", rel, "specialist skill must start with ## Distro support")
    validate_links(root, path, raw, findings)
    return str(name) if isinstance(name, str) else None, str(description or "")


def main() -> int:
    args = arguments()
    root = args.root.resolve()
    findings: list[dict] = []
    names: Counter[str] = Counter()
    descriptions: Counter[str] = Counter()
    files = active_skills(root)
    for path in files:
        name, description = validate_skill(root, path, findings)
        if name:
            names[name] += 1
        if description:
            descriptions[description.strip().lower()] += 1
    for name, count in names.items():
        if count > 1:
            record(findings, "duplicate-name", Path("."), f"{name}: {count}")
    for description, count in descriptions.items():
        if count > 1:
            record(findings, "duplicate-description", Path("."), f"{count} skills: {description[:100]}")
    template_files = [path for path in templates(root) if path.is_file()]
    counts = dict(sorted(Counter(item["code"] for item in findings).items()))
    payload = {
        "active_skill_count": len(files),
        "template_count": len(template_files),
        "fully_compliant": len(files) - len({item["path"] for item in findings if item["path"].endswith("SKILL.md")}),
        "failure_counts": counts,
        "findings": findings,
    }
    if args.baseline:
        baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        if len(files) != baseline["expected_active_skill_count"]:
            record(findings, "active-count", Path("."), f"{len(files)} != {baseline['expected_active_skill_count']}")
        if len(template_files) != baseline["expected_template_count"]:
            record(findings, "template-count", Path("."), f"{len(template_files)} != {baseline['expected_template_count']}")
        if counts != baseline.get("failure_counts", {}):
            payload["baseline_match"] = False
        else:
            payload["baseline_match"] = True
    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        print(f"linux-skills validator: {len(files)} active skills, {len(template_files)} templates")
        print(f"fully compliant: {payload['fully_compliant']}")
        print(f"failure counts: {json.dumps(counts, sort_keys=True)}")
        for item in findings:
            print(f"- {item['path']}: {item['code']}: {item['detail']}")
    return 1 if findings or payload.get("baseline_match") is False else 0


if __name__ == "__main__":
    raise SystemExit(main())
