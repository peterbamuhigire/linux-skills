#!/usr/bin/env python3
"""Validate Claude/Codex plugin metadata and bounded package contents."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any


MAX_PACKAGE_FILES = 5000
CACHE_DIRS = {
    ".pytest_cache",
    "__pycache__",
    ".mypy_cache",
    ".ruff_cache",
    ".tox",
    ".nox",
    ".cache",
    ".venv",
    "venv",
    "node_modules",
}
WALK_EXCLUDES = CACHE_DIRS | {".git"}
SKILL_EXCLUDES = WALK_EXCLUDES | {".codex", ".claude"}
SKIP_SKILL_PREFIXES = {"meta"}
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")


def _read_json(path: Path, label: str, issues: list[str]) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        issues.append(f"{label}: required file is missing")
        return None
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        issues.append(f"{label}: cannot read valid UTF-8 JSON ({exc})")
        return None
    if not isinstance(value, dict):
        issues.append(f"{label}: top-level JSON value must be an object")
        return None
    return value


def _count_entries(root: Path, *, include_git_and_caches: bool) -> int:
    """Count file-like entries without following directory symlinks."""
    count = 0

    def fail_walk(error: OSError) -> None:
        raise error

    for current, dirs, files in os.walk(root, topdown=True, followlinks=False, onerror=fail_walk):
        current_path = Path(current)
        kept_dirs: list[str] = []
        for name in dirs:
            child = current_path / name
            excluded = not include_git_and_caches and name in WALK_EXCLUDES
            if excluded:
                continue
            if child.is_symlink():
                # A symlinked directory is a package entry, but is never followed.
                count += 1
                continue
            kept_dirs.append(name)
        dirs[:] = kept_dirs
        count += len(files)
    return count


def _discover_skill_dirs(root: Path, issues: list[str]) -> set[str]:
    found: set[str] = set()

    def fail_walk(error: OSError) -> None:
        raise error

    for current, dirs, files in os.walk(root, topdown=True, followlinks=False, onerror=fail_walk):
        current_path = Path(current)
        rel_parts = current_path.relative_to(root).parts
        if any(part in SKILL_EXCLUDES or part.startswith(".") for part in rel_parts):
            dirs[:] = []
            continue
        dirs[:] = [
            name for name in dirs
            if name not in SKILL_EXCLUDES and not name.startswith(".")
            and not (current_path / name).is_symlink()
        ]
        if "SKILL.md" in files:
            rel = current_path.relative_to(root).as_posix()
            if rel != "." and rel.split("/", 1)[0] not in SKIP_SKILL_PREFIXES:
                found.add(rel)
    return found


def _validate_paths(
    root: Path,
    raw_paths: Any,
    label: str,
    issues: list[str],
) -> set[str]:
    if not isinstance(raw_paths, list):
        issues.append(f"{label}: skills must be an explicit array of relative skill directories")
        return set()

    normalized: list[str] = []
    result: set[str] = set()
    for index, raw in enumerate(raw_paths):
        item_label = f"{label}[{index}]"
        if not isinstance(raw, str) or not raw:
            issues.append(f"{item_label}: path must be a non-empty string")
            continue
        if "\\" in raw or not raw.startswith("./"):
            issues.append(f"{item_label}: path must use a ./-prefixed POSIX relative path")
            continue
        if raw.startswith("/") or not raw.endswith("/"):
            issues.append(f"{item_label}: path is absolute, empty, or contains traversal components")
            continue
        rel = raw[2:-1]
        parts = rel.split("/")
        if not rel or any(part in {"", ".", ".."} for part in parts):
            issues.append(f"{item_label}: path is absolute, empty, or contains traversal components")
            continue
        if raw != f"./{rel}/":
            issues.append(f"{item_label}: path must use its canonical ./relative/path/ form")
            continue
        candidate = root.joinpath(*parts)
        try:
            resolved = candidate.resolve(strict=True)
            resolved.relative_to(root)
        except (OSError, ValueError):
            issues.append(f"{item_label}: path is missing or resolves outside the plugin root")
            continue
        cursor = root
        symlink_component = False
        for part in parts:
            cursor = cursor / part
            if cursor.is_symlink():
                symlink_component = True
                break
        skill_file = candidate / "SKILL.md"
        if symlink_component:
            issues.append(f"{item_label}: symlinked skill paths are not accepted")
            continue
        if not resolved.is_dir() or not skill_file.is_file() or skill_file.is_symlink():
            issues.append(f"{item_label}: path must be a directory containing a regular SKILL.md")
            continue
        if rel in result:
            issues.append(f"{item_label}: duplicate skill path: {rel}")
            continue
        result.add(rel)
        normalized.append(rel)
    return result


def _required_string(obj: dict[str, Any], key: str, label: str, issues: list[str]) -> str | None:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        issues.append(f"{label}.{key}: required non-empty string")
        return None
    return value


def audit_repository(root_arg: Path, *, file_cap: int = MAX_PACKAGE_FILES) -> tuple[list[str], dict[str, int]]:
    issues: list[str] = []
    try:
        root = root_arg.resolve(strict=True)
    except OSError as exc:
        return [f"repository root is unavailable: {exc}"], {"package_files": 0, "checkout_entries": 0}
    if not root.is_dir():
        return ["repository root is not a directory"], {"package_files": 0, "checkout_entries": 0}

    try:
        package_files = _count_entries(root, include_git_and_caches=False)
        checkout_entries = _count_entries(root, include_git_and_caches=True)
    except OSError as exc:
        return [f"file inventory failed closed: {exc}"], {"package_files": 0, "checkout_entries": 0}
    stats = {"package_files": package_files, "checkout_entries": checkout_entries}
    if not 0 <= file_cap <= MAX_PACKAGE_FILES:
        issues.append(
            f"configured file cap must be between 0 and the hard ceiling "
            f"{MAX_PACKAGE_FILES}, got {file_cap}"
        )
    if package_files > file_cap:
        issues.append(f"package file count {package_files} exceeds configured cap {file_cap}")
    if checkout_entries > file_cap:
        issues.append(f"checkout entry count {checkout_entries} exceeds configured cap {file_cap}")

    claude = _read_json(root / ".claude-plugin/plugin.json", "Claude manifest", issues)
    market = _read_json(root / ".claude-plugin/marketplace.json", "Claude marketplace", issues)
    codex = _read_json(root / ".codex-plugin/plugin.json", "Codex compatibility manifest", issues)
    if (root / "plugin.json").exists():
        issues.append("root plugin.json is not permitted with this multi-path compatibility layout; portable discovery changes skill path semantics")
    if claude is None or market is None or codex is None:
        return issues, stats

    name = _required_string(claude, "name", "Claude manifest", issues)
    version = _required_string(claude, "version", "Claude manifest", issues)
    if version and not SEMVER.fullmatch(version):
        issues.append("Claude manifest.version must be semantic version syntax")

    entries = market.get("plugins")
    if not isinstance(entries, list):
        issues.append("Claude marketplace.plugins must be an array")
        entries = []
    root_entries = [
        entry for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("source"), str)
        and entry.get("source") in {"./", "."}
    ]
    if len(root_entries) != 1:
        issues.append("Claude marketplace must contain exactly one plugin entry whose source is the repository root")
    else:
        entry = root_entries[0]
        entry_name = _required_string(entry, "name", "Claude marketplace root entry", issues)
        entry_version = entry.get("version")
        if name and entry_name != name:
            issues.append("Claude marketplace entry name must match Claude manifest name")
        if version and entry_version != version:
            issues.append("Claude marketplace entry version must match Claude manifest version")

    codex_name = _required_string(codex, "name", "Codex manifest", issues)
    codex_version = _required_string(codex, "version", "Codex manifest", issues)
    codex_description = _required_string(codex, "description", "Codex manifest", issues)
    if name and codex_name != name:
        issues.append("Codex manifest name must match Claude manifest name")
    if version and codex_version != version:
        issues.append("Codex manifest version must match Claude manifest version")
    if codex_version and not SEMVER.fullmatch(codex_version):
        issues.append("Codex manifest.version must be semantic version syntax")
    author = codex.get("author")
    if not isinstance(author, dict):
        issues.append("Codex manifest.author must be an object")
    else:
        _required_string(author, "name", "Codex manifest.author", issues)
    interface = codex.get("interface")
    if not isinstance(interface, dict):
        issues.append("Codex manifest.interface must be an object")
    else:
        for key in ("displayName", "shortDescription", "longDescription", "developerName", "category"):
            _required_string(interface, key, "Codex manifest.interface", issues)
        category = interface.get("category")
        if not isinstance(category, str) or category not in {
            "Productivity", "Creativity", "Developer Tools", "Business & Operations",
            "Data & Analytics", "Communication", "Education & Research", "Security",
            "Finance", "Healthcare", "Travel", "Entertainment", "Other",
        }:
            issues.append("Codex manifest.interface.category is not in the documented category set")
        if not isinstance(interface.get("capabilities"), list) or not all(
            isinstance(value, str) and value.strip() for value in interface.get("capabilities", [])
        ):
            issues.append("Codex manifest.interface.capabilities must be an array of non-empty strings")

    claude_skills = _validate_paths(root, claude.get("skills"), "Claude manifest.skills", issues)
    codex_skills = _validate_paths(root, codex.get("skills"), "Codex manifest.skills", issues)
    if claude_skills != codex_skills:
        issues.append("Claude and Codex skill path sets differ")
    try:
        discovered = _discover_skill_dirs(root, issues)
    except OSError as exc:
        issues.append(f"skill inventory failed closed: {exc}")
        discovered = set()
    if claude_skills != discovered:
        missing = sorted(discovered - claude_skills)
        stale = sorted(claude_skills - discovered)
        issues.append(f"skill manifest parity failed (not listed: {missing}; missing on disk: {stale})")

    hooks_path = codex.get("hooks")
    hook_file = root / "hooks/hooks.json"
    if hook_file.exists():
        if hooks_path != "./hooks/hooks.json":
            issues.append("Codex manifest must explicitly reference the existing hooks/hooks.json to retain hook behavior")
        try:
            hook_target = (root / "hooks/hooks.json").resolve(strict=True)
            hook_target.relative_to(root)
            if hook_target.is_symlink() or not hook_target.is_file():
                issues.append("hooks/hooks.json must resolve to a regular file inside the plugin root")
        except (OSError, ValueError):
            issues.append("hooks/hooks.json is missing or resolves outside the plugin root")
        try:
            hooks = json.loads(hook_file.read_text(encoding="utf-8"))
            if not isinstance(hooks, dict) or not isinstance(hooks.get("hooks"), dict):
                issues.append("hooks/hooks.json must contain a top-level hooks object")
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            issues.append(f"hooks/hooks.json is not readable valid UTF-8 JSON ({exc})")
    elif hooks_path is not None:
        issues.append("Codex manifest declares hooks but hooks/hooks.json is absent")

    # A declared MCP file must exist; this engine currently has no MCP server.
    if "mcpServers" in codex:
        issues.append("Codex manifest.mcpServers is not supported by this engine package; no MCP server is declared")
    if codex_description is not None and len(codex_description) > 1024:
        issues.append("Codex manifest.description exceeds the documented 1024-character upload limit")

    return issues, stats


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args(argv)
    issues, stats = audit_repository(args.root)
    print(f"Package files (excluding .git and ephemeral caches): {stats['package_files']}/{MAX_PACKAGE_FILES}")
    print(f"Checkout file-like entries (including .git and caches): {stats['checkout_entries']}/{MAX_PACKAGE_FILES}")
    if issues:
        for issue in issues:
            print(f"FAIL: {issue}", file=sys.stderr)
        return 1
    print("PASS: Claude marketplace and Codex compatibility manifests are aligned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
