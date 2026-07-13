#!/usr/bin/env python3
"""Run deterministic top-three routing fixtures against active skill contracts."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures" / "routing.json"
BASELINE = ROOT / "quality-baseline.json"
FRONTMATTER_RE = re.compile(r"^---\r?\n(.*?)\r?\n---\r?\n?", re.DOTALL)
STOPWORDS = {
    "a", "an", "and", "after", "before", "between", "for", "from", "in", "is", "it", "no",
    "of", "on", "or", "the", "to", "with", "without", "while", "one", "current", "provide",
    "plan", "safely", "server", "linux", "host", "configure", "create", "use", "set", "up",
}


def tokens(text: str) -> list[str]:
    return [word for word in re.findall(r"[a-z0-9]+", text.lower()) if len(word) > 1 and word not in STOPWORDS]


def catalogue() -> dict[str, dict[str, Counter[str] | str]]:
    skills: dict[str, dict[str, Counter[str] | str]] = {}
    for path in sorted(ROOT.rglob("SKILL.md")):
        if any(part in {".git", "templates", "__pycache__"} for part in path.relative_to(ROOT).parts):
            continue
        raw = path.read_text(encoding="utf-8")
        match = FRONTMATTER_RE.match(raw)
        if not match:
            continue
        meta = yaml.safe_load(match.group(1)) or {}
        name = meta.get("name")
        description = str(meta.get("description", ""))
        use_match = re.search(r"^##\s+Use When\s*$([\s\S]*?)(?=^##\s|\Z)", raw[match.end():], re.MULTILINE | re.IGNORECASE)
        use_when = use_match.group(1) if use_match else ""
        if isinstance(name, str):
            skills[name] = {
                "name": Counter(tokens(name.replace("-", " "))),
                "description": Counter(tokens(description)),
                "use_when": Counter(tokens(use_when)),
                "description_text": description.lower(),
            }
    return skills


def rank(prompt: str, skills: dict[str, dict[str, Counter[str] | str]]) -> list[str]:
    query = Counter(tokens(prompt))
    scored: list[tuple[float, str]] = []
    for name, fields in skills.items():
        score = 0.0
        score += sum(query[token] * fields["name"][token] * 6 for token in query)  # type: ignore[index]
        score += sum(query[token] * fields["description"][token] * 3 for token in query)  # type: ignore[index]
        score += sum(query[token] * min(fields["use_when"][token], 3) * 2 for token in query)  # type: ignore[index]
        name_phrase = name.replace("linux-", "").replace("-", " ")
        if name_phrase in prompt.lower():
            score += 20
        scored.append((score, name))
    return [name for _, name in sorted(scored, key=lambda item: (-item[0], item[1]))]


def main() -> int:
    fixtures = json.loads(FIXTURES.read_text(encoding="utf-8"))
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))["routing"]
    skills = catalogue()
    top_k = int(baseline["top_k"])
    passed = 0
    failures: list[str] = []
    kinds = Counter(item["kind"] for item in fixtures)
    for fixture in fixtures:
        top = rank(fixture["prompt"], skills)[:top_k]
        reasons: list[str] = []
        if fixture["expected"] not in top:
            reasons.append(f"expected {fixture['expected']} in {top}")
        for neighbour in fixture.get("also_top_three", []):
            if neighbour not in top:
                reasons.append(f"expected neighbour {neighbour} in {top}")
        for forbidden in fixture.get("forbidden", []):
            if forbidden in top:
                reasons.append(f"forbidden {forbidden} appeared in {top}")
        if reasons:
            failures.append(f"{fixture['id']}: {'; '.join(reasons)}")
        else:
            passed += 1
    precision = passed / len(fixtures) if fixtures else 0.0
    print(f"routing fixtures: {passed}/{len(fixtures)} passed; top_k={top_k}; precision={precision:.3f}")
    print("fixture kinds: " + ", ".join(f"{key}={value}" for key, value in sorted(kinds.items())))
    for failure in failures:
        print(f"- {failure}")
    expected_count = int(baseline["fixture_count"])
    required = float(baseline["required_precision"])
    return 1 if len(fixtures) != expected_count or precision < required or failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
