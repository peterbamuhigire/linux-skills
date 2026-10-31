"""Guard the SSH hardening drop-in procedures against first-value-wins precedence.

OpenSSH processes ``Include`` globs in lexical order and keeps the first value it
obtains for each keyword. A hardening file numbered after a competing file (for
example cloud-init's ``50-cloud-init.conf``) therefore loses. These tests read the
shipped procedures, build a fixture configuration with a competing
``PasswordAuthentication yes`` file, and ask ``sshd -T`` for the effective value.

The behavioural tests need an OpenSSH server binary and ``ssh-keygen``; they are
skipped, never passed, when either is missing. Nothing here starts a daemon or
touches ``/etc``.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Procedures that tell an operator to create or edit an sshd drop-in.
PROCEDURES = [
    "01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md",
    "01-provisioning-and-bootstrap/linux-server-provisioning/references/post-install-verification.md",
    "02-users-access-and-secrets/linux-access-control/references/users-sudoers-pam.md",
    "07-security-and-hardening/linux-server-hardening/SKILL.md",
    "07-security-and-hardening/linux-server-hardening/references/hardening-checklist.md",
    "notes/server-security.md",
]

DROPIN_PATH = re.compile(r"sshd_config\.d/(\d+)-([A-Za-z0-9._-]+\.conf)")
COMPETING_CLOUD_INIT = "50-cloud-init.conf"

SSHD = shutil.which("sshd") or ("/usr/sbin/sshd" if Path("/usr/sbin/sshd").exists() else None)
SSH_KEYGEN = shutil.which("ssh-keygen")


def dropin_mentions(text: str) -> list[tuple[int, str]]:
    return [(int(number), f"{number}-{name}") for number, name in DROPIN_PATH.findall(text)]


def heredoc_after(text: str, marker: str) -> str:
    """Return the body of the first quoted heredoc that follows ``marker``."""
    start = text.index(marker)
    match = re.search(r"<<'(\w+)'\n(.*?)\n\1\n", text[start:], re.DOTALL)
    if not match:
        raise AssertionError(f"no heredoc after {marker!r}")
    return match.group(2)


def fenced_block_after(text: str, marker: str) -> str:
    start = text.index(marker)
    match = re.search(r"```[a-z]*\n(.*?)\n```", text[start:], re.DOTALL)
    if not match:
        raise AssertionError(f"no fenced block after {marker!r}")
    return match.group(1)


def effective_sshd_values(dropin_name: str, dropin_body: str) -> dict[str, str]:
    """Build a throwaway config tree and return ``sshd -T`` output as a mapping."""
    assert SSHD and SSH_KEYGEN
    with tempfile.TemporaryDirectory() as work_name:
        work = Path(work_name)
        (work / "sshd_config.d").mkdir()
        key = work / "hostkey"
        subprocess.run(
            [SSH_KEYGEN, "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
            check=True,
            capture_output=True,
        )
        main = work / "sshd_config"
        main.write_text(
            f"Include {work}/sshd_config.d/*.conf\nHostKey {key}\nPasswordAuthentication yes\nPermitRootLogin yes\n",
            encoding="utf-8",
        )
        (work / "sshd_config.d" / COMPETING_CLOUD_INIT).write_text(
            "PasswordAuthentication yes\n", encoding="utf-8"
        )
        (work / "sshd_config.d" / dropin_name).write_text(dropin_body + "\n", encoding="utf-8")
        result = subprocess.run(
            [SSHD, "-T", "-f", str(main), "-C", "user=operator,host=fixture,addr=203.0.113.9"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(f"sshd -T rejected the documented drop-in: {result.stderr.strip()}")
        values: dict[str, str] = {}
        for line in result.stdout.splitlines():
            key_name, _, value = line.partition(" ")
            values.setdefault(key_name, value)
        return values


class SshDropinNamingTests(unittest.TestCase):
    def test_procedures_exist(self) -> None:
        for relative in PROCEDURES:
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_no_procedure_numbers_a_hardening_dropin_after_cloud_init(self) -> None:
        offenders: list[str] = []
        for relative in PROCEDURES:
            text = (ROOT / relative).read_text(encoding="utf-8")
            for number, name in dropin_mentions(text):
                if name == COMPETING_CLOUD_INIT:
                    continue
                if number >= 50:
                    offenders.append(f"{relative}: sshd_config.d/{name}")
        self.assertEqual(
            offenders,
            [],
            "Hardening drop-ins numbered 50 or higher lose to earlier files under "
            "OpenSSH first-value-wins; use a name that sorts before 50-cloud-init.conf.",
        )

    def test_mentions_use_one_consistent_name(self) -> None:
        names: dict[str, set[str]] = {}
        for relative in PROCEDURES:
            text = (ROOT / relative).read_text(encoding="utf-8")
            for _, name in dropin_mentions(text):
                if name != COMPETING_CLOUD_INIT:
                    names.setdefault(name, set()).add(relative)
        self.assertLessEqual(
            len(names), 1, f"procedures disagree on the hardening drop-in name: {sorted(names)}"
        )


@unittest.skipUnless(SSHD and SSH_KEYGEN, "OpenSSH server binary or ssh-keygen not available")
class SshDropinEffectiveValueTests(unittest.TestCase):
    def test_provisioning_dropin_wins_over_cloud_init(self) -> None:
        text = (ROOT / PROCEDURES[0]).read_text(encoding="utf-8")
        marker = "sudo tee /etc/ssh/sshd_config.d/"
        name = DROPIN_PATH.search(text[text.index(marker) :]).group(0).split("/")[-1]  # type: ignore[union-attr]
        values = effective_sshd_values(name, heredoc_after(text, marker))
        self.assertEqual(values["passwordauthentication"], "no", f"drop-in {name} lost to {COMPETING_CLOUD_INIT}")
        self.assertEqual(values["permitrootlogin"], "no")
        self.assertEqual(values["pubkeyauthentication"], "yes")

    def test_hardening_checklist_dropin_wins_over_cloud_init(self) -> None:
        relative = "07-security-and-hardening/linux-server-hardening/references/hardening-checklist.md"
        text = (ROOT / relative).read_text(encoding="utf-8")
        block = fenced_block_after(text, "Use the following baseline")
        name = DROPIN_PATH.search(block).group(0).split("/")[-1]  # type: ignore[union-attr]
        values = effective_sshd_values(name, block)
        self.assertEqual(values["passwordauthentication"], "no", f"drop-in {name} lost to {COMPETING_CLOUD_INIT}")
        self.assertEqual(values["permitrootlogin"], "no")

    def test_competing_file_does_win_over_a_later_name(self) -> None:
        """Negative control: proves the fixture detects the failure it guards against."""
        values = effective_sshd_values("99-hardening.conf", "PasswordAuthentication no\nPermitRootLogin no")
        self.assertEqual(values["passwordauthentication"], "yes")
        self.assertEqual(values["permitrootlogin"], "no")


if __name__ == "__main__":
    unittest.main()
