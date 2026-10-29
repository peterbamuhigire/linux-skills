import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_marketplace", ROOT / "scripts" / "check_marketplace.py"
)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


class MarketplaceCheckerTests(unittest.TestCase):
    def make_fixture(self, root: Path) -> None:
        (root / "ops" / "skill-one").mkdir(parents=True)
        (root / "ops" / "skill-one" / "SKILL.md").write_text(
            "---\nname: skill-one\ndescription: Test skill.\n---\nDo the test.\n",
            encoding="utf-8",
        )
        (root / "meta" / "authoring").mkdir(parents=True)
        (root / "meta" / "authoring" / "SKILL.md").write_text(
            "---\nname: authoring\ndescription: Not packaged.\n---\nAuthor skills.\n",
            encoding="utf-8",
        )
        write_json(
            root / ".claude-plugin" / "plugin.json",
            {
                "name": "linux",
                "version": "1.0.0",
                "skills": ["./ops/skill-one/"],
                "mcpServers": {},
            },
        )
        write_json(
            root / ".claude-plugin" / "marketplace.json",
            {
                "name": "test-marketplace",
                "owner": {"name": "Test"},
                "plugins": [
                    {
                        "name": "linux",
                        "source": "./",
                        "version": "1.0.0",
                    }
                ],
            },
        )
        write_json(
            root / ".codex-plugin" / "plugin.json",
            {
                "name": "linux",
                "version": "1.0.0",
                "description": "Test Linux operations plugin.",
                "author": {"name": "Test"},
                "skills": ["./ops/skill-one/"],
                "interface": {
                    "displayName": "Linux Operations",
                    "shortDescription": "Portable Linux skills",
                    "longDescription": "A test plugin for Linux operations.",
                    "developerName": "Test",
                    "category": "Developer Tools",
                    "capabilities": ["Linux administration"],
                },
            },
        )

    def test_repository_manifests_are_aligned(self) -> None:
        issues, stats = CHECKER.audit_repository(ROOT)
        self.assertEqual([], issues)
        self.assertLessEqual(stats["package_files"], CHECKER.MAX_PACKAGE_FILES)

    def test_manifest_path_traversal_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            codex_path = root / ".codex-plugin" / "plugin.json"
            codex = json.loads(codex_path.read_text(encoding="utf-8"))
            codex["skills"] = ["./../outside/"]
            write_json(codex_path, codex)
            issues, _ = CHECKER.audit_repository(root)
            self.assertTrue(any("traversal" in issue for issue in issues))

    def test_skill_manifest_mismatch_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            codex_path = root / ".codex-plugin" / "plugin.json"
            codex = json.loads(codex_path.read_text(encoding="utf-8"))
            codex["skills"] = []
            write_json(codex_path, codex)
            issues, _ = CHECKER.audit_repository(root)
            self.assertTrue(any("skill path sets differ" in issue for issue in issues))

    def test_missing_skill_directory_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            codex_path = root / ".codex-plugin" / "plugin.json"
            codex = json.loads(codex_path.read_text(encoding="utf-8"))
            codex["skills"] = ["./ops/missing/"]
            write_json(codex_path, codex)
            issues, _ = CHECKER.audit_repository(root)
            self.assertTrue(any("missing or resolves outside" in issue for issue in issues))

    def test_version_mismatch_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            codex_path = root / ".codex-plugin" / "plugin.json"
            codex = json.loads(codex_path.read_text(encoding="utf-8"))
            codex["version"] = "1.0.1"
            write_json(codex_path, codex)
            issues, _ = CHECKER.audit_repository(root)
            self.assertTrue(any("version must match" in issue for issue in issues))

    def test_package_file_cap_excludes_git_and_cache_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            (root / ".git" / "objects").mkdir(parents=True)
            (root / ".git" / "objects" / "marker").write_text("git", encoding="utf-8")
            (root / ".pytest_cache").mkdir()
            (root / ".pytest_cache" / "marker").write_text("cache", encoding="utf-8")
            issues, stats = CHECKER.audit_repository(root, file_cap=1)
            self.assertGreater(stats["checkout_entries"], stats["package_files"])
            self.assertTrue(any("package file count" in issue for issue in issues))

    def test_checkout_cap_includes_git_and_caches(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            baseline_issues, baseline = CHECKER.audit_repository(root)
            self.assertEqual([], baseline_issues)
            (root / ".git" / "objects").mkdir(parents=True)
            (root / ".git" / "objects" / "marker").write_text("git", encoding="utf-8")
            (root / ".pytest_cache").mkdir()
            (root / ".pytest_cache" / "marker").write_text("cache", encoding="utf-8")
            issues, stats = CHECKER.audit_repository(root, file_cap=baseline["package_files"])
            self.assertEqual(baseline["package_files"], stats["package_files"])
            self.assertGreater(stats["checkout_entries"], baseline["package_files"])
            self.assertTrue(any("checkout entry count" in issue for issue in issues))

    def test_malformed_manifest_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.make_fixture(root)
            (root / ".codex-plugin" / "plugin.json").write_text("{", encoding="utf-8")
            issues, _ = CHECKER.audit_repository(root)
            self.assertTrue(any("valid UTF-8 JSON" in issue for issue in issues))

    def test_legacy_command_safety_gates_remain_present(self) -> None:
        rclone = (ROOT / "commands" / "rclone.md").read_text(encoding="utf-8")
        redis = (ROOT / "commands" / "redis.md").read_text(encoding="utf-8")

        self.assertTrue(rclone.startswith("---\ndescription:"))
        self.assertIn("rclone --dry-run --verbose delete", rclone)
        self.assertIn("rclone --dry-run --verbose sync", rclone)
        self.assertIn("rclone config redacted", rclone)
        self.assertIn("Do not run or share the output of: rclone config show", rclone)
        self.assertIn("redaction may not be perfect", rclone)
        self.assertIn("owner has approved that exact target and scope", rclone)
        self.assertIn("restore procedure works", rclone)

        self.assertTrue(redis.startswith("---\ndescription:"))
        self.assertIn("approved isolated non-production target", redis)
        self.assertIn("tested, recoverable restore copy", redis)
        self.assertIn("KEYS blocks", redis)
        self.assertIn("incremental SCAN", redis)
        self.assertIn("Treat `MONITOR` output as sensitive", redis)
        self.assertIn("(inference)", redis)


if __name__ == "__main__":
    unittest.main()
