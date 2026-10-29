#!/usr/bin/env python3
"""Measure bounded skill-routing and documentation quality evidence.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import re
import subprocess
from datetime import date
from pathlib import Path
from statistics import median
from urllib.parse import unquote, urlsplit


CONTRACT_HEADINGS = {
    "use when",
    "do not use when",
    "required inputs",
    "workflow",
    "quality standards",
    "anti-patterns",
    "outputs",
    "references",
}
INLINE_LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^)]+)\)")
EXTERNAL_SCHEMES = {"http", "https", "mailto", "tel", "plugin", "app", "data"}


def load_router(root: Path):
    path = root / "scripts" / "routing_smoke_test.py"
    spec = importlib.util.spec_from_file_location("kaizen_routing_smoke", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load routing implementation: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def active_skill_files(root: Path) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for path in sorted(root.rglob("SKILL.md")):
        if any(part in {".git", "templates", "__pycache__"} for part in path.relative_to(root).parts):
            continue
        raw = path.read_text(encoding="utf-8")
        match = re.match(r"^---\r?\n(.*?)\r?\n---\r?\n?", raw, re.DOTALL)
        if not match:
            continue
        try:
            import yaml

            front = yaml.safe_load(match.group(1)) or {}
        except Exception as exc:  # malformed frontmatter remains outside this metric
            raise RuntimeError(f"cannot parse frontmatter in {path}: {exc}") from exc
        name = front.get("name")
        if isinstance(name, str):
            result[name] = path
    return result


def read_fixtures(root: Path) -> list[dict[str, object]]:
    path = root / "tests" / "fixtures" / "routing.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"routing fixtures must be a JSON list: {path}")
    return data


def routing_metrics(root: Path, skills: dict[str, Path]) -> dict[str, object]:
    router = load_router(root)
    catalogue = router.catalogue()
    fixtures = read_fixtures(root)
    ranked = [router.rank(str(f["prompt"]), catalogue) for f in fixtures]
    fixture_ids = [str(f.get("id", "")) for f in fixtures]
    duplicate_ids = sorted(
        fixture_id for fixture_id, count in collections.Counter(fixture_ids).items() if not fixture_id or count > 1
    )
    kinds = collections.Counter(str(f.get("kind", "unknown")) for f in fixtures)
    out: dict[str, object] = {
        "fixture_count": len(fixtures),
        "fixture_kinds": dict(sorted(kinds.items())),
    }
    for k in (1, 3):
        hits = sum(str(f.get("expected", "")) in ranked[index][:k] for index, f in enumerate(fixtures))
        out[f"expected_target_at_{k}"] = {
            "passed": hits,
            "total": len(fixtures),
            "precision": hits / len(fixtures) if fixtures else 0.0,
        }

    positives: collections.Counter[str] = collections.Counter()
    negatives: collections.Counter[str] = collections.Counter()
    owned_negative_at_1 = owned_negative_at_3 = forbidden_absent = 0
    unknown_expected: list[str] = []
    for index, f in enumerate(fixtures):
        expected = str(f.get("expected", ""))
        kind = str(f.get("kind", ""))
        top = ranked[index][:3]
        if expected not in skills:
            unknown_expected.append(str(f.get("id", "<no id>")))
        if kind == "positive":
            positives[expected] += 1
        if kind == "negative":
            negatives[expected] += 1
            owned_negative_at_1 += int(expected in top[:1])
            owned_negative_at_3 += int(expected in top)
            forbidden_absent += int(not any(str(x) in top for x in f.get("forbidden", [])))

    deficits = {
        name: {"positive": positives[name], "owned_negative": negatives[name]}
        for name in sorted(skills)
        if positives[name] < 3 or negatives[name] < 2
    }
    coverage: dict[str, object] = {
        "positive_fixtures": sum(positives.values()),
        "owned_negative_fixtures": sum(negatives.values()),
        "skills_total": len(skills),
        "skills_meeting_3_positive_and_2_owned_negative": len(skills) - len(deficits),
        "shortfalls": deficits,
        "per_skill": {
            name: {"positive": positives[name], "owned_negative": negatives[name]}
            for name in sorted(skills)
        },
    }
    out["coverage"] = coverage
    out["owned_negatives"] = {
        "fixture_count": sum(negatives.values()),
        "expected_target_at_1": owned_negative_at_1,
        "expected_target_at_3": owned_negative_at_3,
        "forbidden_absent_at_3": forbidden_absent,
    }
    out["unknown_expected_ids"] = unknown_expected
    out["duplicate_or_missing_fixture_ids"] = duplicate_ids
    return out


def worked_examples_and_duplicates(skills: dict[str, Path], root: Path) -> tuple[dict[str, object], dict[str, object]]:
    examples: list[dict[str, object]] = []
    duplicate_rows: list[dict[str, object]] = []
    for name, path in sorted(skills.items()):
        text = path.read_text(encoding="utf-8")
        match = re.search(r"^##\s+Worked Example\s*$", text, re.MULTILINE | re.IGNORECASE)
        if match:
            tail = text[match.end() :]
            boundary = re.search(r"^##\s+", tail, re.MULTILINE)
            body = tail[: boundary.start()] if boundary else tail
            paragraphs = [part for part in re.split(r"\n\s*\n", body.strip()) if part.strip()]
            examples.append(
                {
                    "skill": name,
                    "path": str(path.relative_to(root)),
                    "paragraphs": len(paragraphs),
                    "nonblank_lines": sum(bool(line.strip()) for line in body.splitlines()),
                }
            )
        headings = [h.strip().lower() for h in re.findall(r"^##\s+(.+?)\s*$", text, re.MULTILINE)]
        repeated = {
            heading: count
            for heading, count in sorted(collections.Counter(headings).items())
            if heading in CONTRACT_HEADINGS and count > 1
        }
        if repeated:
            duplicate_rows.append({"skill": name, "path": str(path.relative_to(root)), "headings": repeated})

    paragraphs = [int(row["paragraphs"]) for row in examples]
    lines = [int(row["nonblank_lines"]) for row in examples]
    example_metrics = {
        "definition": "H2 Worked Example body up to the next H2; paragraphs split on blank lines",
        "skills_with_example": len(examples),
        "skills_without_example": len(skills) - len(examples),
        "paragraphs_total": sum(paragraphs),
        "nonblank_lines_total": sum(lines),
        "median_paragraphs": median(paragraphs) if paragraphs else 0,
        "median_nonblank_lines": median(lines) if lines else 0,
        "per_skill": examples,
    }
    duplicate_metrics = {
        "definition": "repeated canonical contract H2 headings within one skill; case-insensitive",
        "skills_with_duplicates": len(duplicate_rows),
        "duplicate_heading_types": sum(len(row["headings"]) for row in duplicate_rows),
        "records": duplicate_rows,
    }
    return example_metrics, duplicate_metrics


def heading_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: collections.Counter[str] = collections.Counter()
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.MULTILINE):
        clean = re.sub(r"`([^`]*)`", r"\1", heading)
        clean = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", clean)
        slug = re.sub(r"[^\w\- ]", "", clean.lower(), flags=re.UNICODE).strip().replace(" ", "-")
        suffix = counts[slug]
        counts[slug] += 1
        anchors.add(slug if suffix == 0 else f"{slug}-{suffix}")
    return anchors


def link_metrics(root: Path) -> dict[str, object]:
    absolute: list[dict[str, object]] = []
    broken_paths: list[dict[str, object]] = []
    broken_anchors: list[dict[str, object]] = []
    external_count = 0
    template_placeholders: list[dict[str, object]] = []
    for md in sorted(root.rglob("*.md")):
        if ".git" in md.relative_to(root).parts:
            continue
        source = md.read_text(encoding="utf-8", errors="replace")
        for line_no, line in enumerate(source.splitlines(), 1):
            for raw_target in INLINE_LINK_RE.findall(line):
                target = raw_target.strip().split()[0].strip("<>")
                parsed = urlsplit(target)
                if parsed.scheme in EXTERNAL_SCHEMES:
                    external_count += 1
                    continue
                link_path = unquote(parsed.path)
                if re.match(r"^[A-Za-z]:[\\/]", link_path) or link_path.startswith("/"):
                    absolute.append({"path": str(md.relative_to(root)), "line": line_no, "target": target})
                    continue
                destination = (md.parent / link_path).resolve() if link_path else md
                if not destination.exists():
                    item = {"path": str(md.relative_to(root)), "line": line_no, "target": target}
                    if "templates" in md.relative_to(root).parts:
                        template_placeholders.append(item)
                    else:
                        broken_paths.append(item)
                    continue
                if parsed.fragment:
                    fragment = unquote(parsed.fragment)
                    dest_md = destination if destination.is_file() else destination / "README.md"
                    if dest_md.suffix.lower() == ".md" and dest_md.exists():
                        valid = heading_anchors(dest_md.read_text(encoding="utf-8", errors="replace"))
                        if fragment not in valid:
                            broken_anchors.append(
                                {"path": str(md.relative_to(root)), "line": line_no, "target": target}
                            )
    return {
        "scope": "Markdown inline links in repository .md files; external/reference-style links are not fetched or checked",
        "machine_specific_absolute_count": len(absolute),
        "machine_specific_absolute": absolute,
        "dangling_local_path_count": len(broken_paths),
        "dangling_local_paths": broken_paths,
        "dangling_local_anchor_count": len(broken_anchors),
        "dangling_local_anchors": broken_anchors,
        "template_placeholders": template_placeholders,
        "external_links": external_count,
        "external_reachability": "NOT_ASSESSED",
    }


def source_review_metrics(root: Path, as_of: date) -> dict[str, object]:
    records: list[dict[str, object]] = []
    cue = re.compile(r"(?:review\s+by|next\s+review)\s*:?\s*(20\d{2}-\d{2}-\d{2})", re.IGNORECASE)
    source_id = re.compile(r"\b(?:LSR|S)-?\d{1,3}\b", re.IGNORECASE)
    for path in sorted((root / "docs").rglob("*.md")):
        for line_no, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            source_ids = sorted({value.upper().replace("-", "") for value in source_id.findall(line)})
            if not source_ids:
                continue
            match = cue.search(line)
            if not match:
                continue
            value = date.fromisoformat(match.group(1))
            records.append(
                {
                    "path": str(path.relative_to(root)),
                    "line": line_no,
                    "source_ids": source_ids,
                    "review_date": value.isoformat(),
                    "expired": value < as_of,
                }
            )
    expired = [record for record in records if record["expired"]]
    return {
        "scope": "docs Markdown lines with a source ID (LSR-n or S-n) and explicit review-by/next-review date; due/access dates excluded",
        "as_of": as_of.isoformat(),
        "dated_source_records": len(records),
        "expired_source_records": len(expired),
        "records": records,
    }


def touched_skill_metrics(root: Path, skills: dict[str, Path], coverage: dict[str, object], base_ref: str) -> dict[str, object]:
    changed: set[str] = set()
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", base_ref],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        changed.update(result.stdout.splitlines())
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        changed.update(untracked.stdout.splitlines())
    except (OSError, subprocess.SubprocessError):
        return {"status": "NOT_ASSESSED", "reason": "Git worktree unavailable"}

    skill_dirs = sorted(
        ((str(path.parent.relative_to(root)), name) for name, path in skills.items()),
        key=lambda item: len(item[0]),
        reverse=True,
    )
    touched_set: set[str] = set()
    for changed_path in changed:
        for skill_dir, name in skill_dirs:
            if changed_path == skill_dir or changed_path.startswith(skill_dir + "/"):
                touched_set.add(name)
                break
    touched = sorted(touched_set)
    per_skill = coverage["per_skill"]
    return {
        "status": "measured",
        "touched_skills": touched,
        "coverage": {
            name: per_skill[name]
            for name in touched
        },
        "skills_meeting_3_positive_and_2_owned_negative": sum(
            per_skill[name]["positive"] >= 3 and per_skill[name]["owned_negative"] >= 2
            for name in touched
        ),
    }


def _link_identity_counts(links: dict[str, object], field: str) -> collections.Counter[tuple[str, str]]:
    records = links.get(field, [])
    return collections.Counter(
        (str(record.get("path", "")), str(record.get("target", "")))
        for record in records
        if isinstance(record, dict)
    )


def _source_review_identity_counts(source_reviews: dict[str, object]) -> collections.Counter[tuple[str, tuple[str, ...], str]]:
    records = source_reviews.get("records", [])
    return collections.Counter(
        (
            str(record.get("path", "")),
            tuple(sorted(str(value) for value in record.get("source_ids", []))),
            str(record.get("review_date", "")),
        )
        for record in records
        if isinstance(record, dict) and record.get("expired")
    )


def _new_identity_records(
    current: collections.Counter[tuple[str, ...]], baseline: collections.Counter[tuple[str, ...]], names: tuple[str, ...]
) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for identity, count in sorted(current.items()):
        delta = count - baseline[identity]
        if delta > 0:
            fields = {
                name: list(value) if isinstance(value, tuple) else value
                for name, value in zip(names, identity)
            }
            result.append({**fields, "new_occurrences": delta})
    return result


def _duplicate_heading_counts(duplicates: dict[str, object]) -> collections.Counter[tuple[str, str]]:
    counts: collections.Counter[tuple[str, str]] = collections.Counter()
    for record in duplicates.get("records", []):
        if not isinstance(record, dict):
            continue
        path = str(record.get("path", ""))
        headings = record.get("headings", {})
        if isinstance(headings, dict):
            for heading, count in headings.items():
                counts[(path, str(heading))] += int(count)
    return counts


def compare_hygiene_to_baseline(current: dict[str, object], baseline: dict[str, object]) -> dict[str, object]:
    """Fail on newly introduced same-scope link, contract, or expired-source debt."""
    scope_fields = ("skills", "routing", "owned_negative", "coverage_threshold")
    scope_matches = all(current.get("scope", {}).get(key) == baseline.get("scope", {}).get(key) for key in scope_fields)
    current_links = current.get("links", {})
    baseline_links = baseline.get("links", {})
    current_duplicates = current.get("duplicate_contract_headings", {})
    baseline_duplicates = baseline.get("duplicate_contract_headings", {})
    current_sources = current.get("source_review_dates", {})
    baseline_sources = baseline.get("source_review_dates", {})
    scope_matches = scope_matches and current_links.get("scope") == baseline_links.get("scope")
    scope_matches = scope_matches and current_duplicates.get("definition") == baseline_duplicates.get("definition")
    scope_matches = scope_matches and current_sources.get("scope") == baseline_sources.get("scope")

    current_machine = _link_identity_counts(current_links, "machine_specific_absolute")
    baseline_machine = _link_identity_counts(baseline_links, "machine_specific_absolute")
    new_machine = _new_identity_records(current_machine, baseline_machine, ("path", "target"))
    current_broken_paths = _link_identity_counts(current_links, "dangling_local_paths")
    baseline_broken_paths = _link_identity_counts(baseline_links, "dangling_local_paths")
    new_broken_paths = _new_identity_records(current_broken_paths, baseline_broken_paths, ("path", "target"))
    current_broken_anchors = _link_identity_counts(current_links, "dangling_local_anchors")
    baseline_broken_anchors = _link_identity_counts(baseline_links, "dangling_local_anchors")
    new_broken_anchors = _new_identity_records(current_broken_anchors, baseline_broken_anchors, ("path", "target"))

    current_duplicate_counts = _duplicate_heading_counts(current_duplicates)
    baseline_duplicate_counts = _duplicate_heading_counts(baseline_duplicates)
    new_duplicates: list[dict[str, object]] = []
    for (path, heading), count in sorted(current_duplicate_counts.items()):
        delta = count - baseline_duplicate_counts[(path, heading)]
        if delta > 0:
            new_duplicates.append({"path": path, "heading": heading, "new_occurrences": delta})

    current_expired_sources = _source_review_identity_counts(current_sources)
    baseline_expired_sources = _source_review_identity_counts(baseline_sources)
    new_expired_sources = _new_identity_records(
        current_expired_sources, baseline_expired_sources, ("path", "source_ids", "review_date")
    )

    violations: list[str] = []
    if not scope_matches:
        violations.append("metric scope differs from baseline")
    if new_machine:
        violations.append("new machine-specific absolute Markdown links")
    if new_broken_paths:
        violations.append("new dangling local Markdown link targets")
    if new_broken_anchors:
        violations.append("new dangling local Markdown anchors")
    if new_duplicates:
        violations.append("new duplicate canonical contract headings")
    if new_expired_sources:
        violations.append("new expired structured source-review records")
    return {
        "status": "pass" if not violations else "fail",
        "same_scope": scope_matches,
        "baseline_as_of": baseline.get("as_of"),
        "machine_specific_links": {
            "baseline_count": sum(baseline_machine.values()),
            "current_count": sum(current_machine.values()),
            "new_records": new_machine,
        },
        "dangling_local_paths": {
            "baseline_count": sum(baseline_broken_paths.values()),
            "current_count": sum(current_broken_paths.values()),
            "new_records": new_broken_paths,
        },
        "dangling_local_anchors": {
            "baseline_count": sum(baseline_broken_anchors.values()),
            "current_count": sum(current_broken_anchors.values()),
            "new_records": new_broken_anchors,
        },
        "duplicate_contract_headings": {
            "baseline_count": sum(baseline_duplicate_counts.values()),
            "current_count": sum(current_duplicate_counts.values()),
            "new_records": new_duplicates,
        },
        "dangling_local_links": {
            "baseline_paths": baseline_links.get("dangling_local_path_count"),
            "current_paths": current_links.get("dangling_local_path_count"),
            "baseline_anchors": baseline_links.get("dangling_local_anchor_count"),
            "current_anchors": current_links.get("dangling_local_anchor_count"),
            "gate": "identity-based; only unchanged baseline path/anchor debt is grandfathered",
        },
        "expired_source_reviews": {
            "baseline_count": sum(baseline_expired_sources.values()),
            "current_count": sum(current_expired_sources.values()),
            "new_records": new_expired_sources,
        },
        "violations": violations,
    }


def build_metrics(
    root: Path,
    as_of: date,
    baseline_path: Path | None = None,
    base_ref: str = "HEAD",
    baseline_commit: str | None = None,
) -> dict[str, object]:
    skills = active_skill_files(root)
    routing = routing_metrics(root, skills)
    examples, duplicates = worked_examples_and_duplicates(skills, root)
    coverage = routing["coverage"]
    report = {
        "as_of": as_of.isoformat(),
        "base_ref": base_ref,
        "baseline_commit": baseline_commit,
        "baseline_provenance": (
            "recomputed from a pristine archive of baseline_commit with this metrics schema; the frozen prior report is retained as metrics-baseline-legacy.json"
            if baseline_commit
            else None
        ),
        "baseline_schema_note": (
            "The frozen legacy report counted 8 broken local targets in one aggregate. The refined scanner separates missing destination paths (7) from dangling anchors (10); this is a classification change, not a silent reduction in link debt."
            if baseline_commit
            else None
        ),
        "root_label": root.name if root.name != "linux-skills" else "working tree",
        "scope": {
            "skills": "SKILL.md files with parseable name frontmatter, excluding templates and VCS/cache directories",
            "routing": "same deterministic ranker and repository routing fixtures; expected target P@1 and P@3 reported separately",
            "owned_negative": "fixture kind negative with expected skill as owner; forbidden competitor absence measured at top 3",
            "coverage_threshold": "at least 3 kind=positive and 2 kind=negative fixtures per skill",
        },
        "active_skills": len(skills),
        "routing": routing,
        "worked_examples": examples,
        "duplicate_contract_headings": duplicates,
        "links": link_metrics(root),
        "source_review_dates": source_review_metrics(root, as_of),
        "touched_skill_coverage": touched_skill_metrics(root, skills, coverage, base_ref),
    }
    if baseline_path is not None:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        report["hygiene_regression"] = compare_hygiene_to_baseline(report, baseline)
    else:
        report["hygiene_regression"] = {"status": "NOT_ASSESSED", "reason": "pass --baseline to compare bounded hygiene findings"}
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--baseline", type=Path, help="baseline metrics JSON for a same-scope hygiene regression gate")
    parser.add_argument("--base-ref", default="HEAD", help="Git ref for touched-skill diff coverage (default: HEAD)")
    parser.add_argument("--baseline-commit", help="source commit when measuring a detached archive snapshot")
    parser.add_argument("--as-of", type=date.fromisoformat, default=date.today())
    args = parser.parse_args()
    root = args.root.resolve()
    report = build_metrics(
        root,
        args.as_of,
        args.baseline.resolve() if args.baseline else None,
        args.base_ref,
        args.baseline_commit,
    )
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 1 if report["hygiene_regression"].get("status") == "fail" else 0


if __name__ == "__main__":
    raise SystemExit(main())
