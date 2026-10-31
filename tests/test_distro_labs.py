"""Opt-in distro labs: the engine's own procedures and scripts, run in real Debian and Fedora containers.

Run with: LINUX_SKILLS_LAB=1 python -m pytest -q tests/test_distro_labs.py
Rootless Podman, local images only (debian:bookworm, fedora:44), no published ports, no host mounts.
Containers are named with LINUX_SKILLS_LAB_PREFIX (default "lskw-") and removed by name at the end.
Documented fenced blocks are extracted from the Markdown and executed verbatim; a block that no longer
exists or no longer runs makes the lab fail. Nothing here touches the host it runs on.
"""
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

from __future__ import annotations

import os
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import pytest

from lab_support import (
    IMAGES, LAB_ENV, LAB_REPO, LabContainer, clean_repo_copy, markdown_blocks, pick_block, podman_ready,
    write_blocks,
)

pytestmark = pytest.mark.skipif(
    os.environ.get(LAB_ENV) != "1",
    reason=f"opt-in disposable Podman distro labs: set {LAB_ENV}=1",
)

FAMILIES = ["debian", "fedora"]
PROVISIONING_STEPS = LAB_REPO / "01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md"
PG_BACKUP_PAGE = LAB_REPO / "11-databases-and-caching/linux-postgresql/references/backup-and-pitr.md"


@dataclass
class Lab:
    containers: dict[tuple[str, str], LabContainer]
    work: Path

    def src(self, family: str) -> LabContainer:
        return self.containers[(family, "src")]

    def scratch(self, family: str) -> LabContainer:
        return self.containers[(family, "scratch")]


@pytest.fixture(scope="module")
def lab(tmp_path_factory: pytest.TempPathFactory):
    reason = podman_ready(IMAGES["debian"], IMAGES["fedora"])
    if reason:
        pytest.skip(reason)
    work = tmp_path_factory.mktemp("distro-lab")
    repo_copy = clean_repo_copy(work / "repo")
    containers = {(family, role): LabContainer(family, role) for family in FAMILIES for role in ("src", "scratch")}
    try:
        with ThreadPoolExecutor(max_workers=len(containers)) as pool:
            list(pool.map(lambda c: c.start(), containers.values()))
            list(pool.map(lambda c: c.wait_ready(), containers.values()))
        for container in containers.values():
            container.prepare_postgres()
        for (family, role), container in containers.items():
            if role == "src":
                container.put(repo_copy, "/opt/repo")
        yield Lab(containers, work)
    finally:
        for container in containers.values():
            container.remove()


def run_driver(container: LabContainer, driver: str, *args: str) -> str:
    result = container.exec(
        "bash", f"/opt/repo/tests/labs/{driver}", *args,
        env={"SK_LAB_DISPOSABLE": "1"}, timeout=1200,
    )
    return result.stdout


def assert_driver_passed(output: str) -> None:
    failures = [line for line in output.splitlines() if line.startswith("FAIL")]
    assert "### RESULT: ALL-PASS" in output and not failures, (
        "lab failures:\n" + "\n".join(failures) + "\n\nfull output:\n" + output
    )


def ssh_blocks(destination: Path) -> Path:
    blocks = markdown_blocks(PROVISIONING_STEPS, "## 3. SSH hardening")
    reload_block = pick_block(blocks, "sshd -t &&")
    # The documented block ends with an interactive step ("ssh administrator@<server-ip>") that the lab
    # replaces with real login attempts; every other line runs as written.
    reload_block = "".join(
        line for line in reload_block.splitlines(keepends=True) if not line.startswith("ssh administrator@")
    )
    return write_blocks(destination, {
        "list.sh": pick_block(blocks, "grep -rniE"),
        "apply.sh": pick_block(blocks, "tee /etc/ssh/sshd_config.d/00-linux-skills-ssh.conf"),
        "reload.sh": reload_block,
        "rollback.sh": pick_block(blocks, "sudo rm /etc/ssh/sshd_config.d/00-linux-skills-ssh.conf"),
        "verify.sh": pick_block(blocks, "sshd -T | grep -Ei"),
    })


def restore_blocks(destination: Path) -> Path:
    blocks = markdown_blocks(PG_BACKUP_PAGE, "### Verify a logical backup")
    commands = pick_block(blocks, "pg_restore --exit-on-error --create").splitlines(keepends=True)
    globals_cmd = next(line for line in commands if "psql -X postgres <" in line)
    database_cmd = next(line for line in commands if "pg_restore --exit-on-error --create" in line)
    return write_blocks(destination, {"globals.sh": globals_cmd, "database.sh": database_cmd})


def unattended_blocks(destination: Path) -> Path:
    blocks = markdown_blocks(PROVISIONING_STEPS, "## 5. Unattended security upgrades")
    return write_blocks(destination, {
        "debian.sh": pick_block(blocks, "52unattended-upgrades-local"),
        "verify.sh": pick_block(blocks, "unattended-upgrade --dry-run --debug"),
    })


@pytest.mark.parametrize("family", FAMILIES)
def test_ssh_dropin_procedure(lab: Lab, family: str) -> None:
    """The documented SSH drop-in beats a cloud-init password file, rolls back, and refuses a broken file."""
    container = lab.src(family)
    blocks = ssh_blocks(lab.work / f"ssh-blocks-{family}")
    container.put(blocks, "/root/blocks-ssh")
    assert_driver_passed(run_driver(container, "ssh_dropin_lab.sh", "/root/blocks-ssh"))


@pytest.mark.parametrize("family", FAMILIES)
def test_pg_backup_then_restore_on_scratch_instance(lab: Lab, family: str) -> None:
    """sk-pg-backup against a real PostgreSQL, then the documented restore on a second instance."""
    source, scratch = lab.src(family), lab.scratch(family)
    assert_driver_passed(run_driver(source, "pg_backup_lab.sh", "/opt/repo/scripts/sk-pg-backup.sh"))

    transfer = lab.work / f"pg-transfer-{family}"
    transfer.mkdir(mode=0o700)
    source.get("/root/lab-out", transfer)
    scratch.put(transfer / "lab-out" / "set", "/root/restore")
    scratch.exec("mkdir", "-p", "/root/src")
    for name in ("fp.sql", "fp-lab_a.txt", "fp-odd.txt"):
        scratch.put(transfer / "lab-out" / name, f"/root/src/{name}")
    scratch.exec("bash", "-c", "chmod 600 /root/restore/*")
    blocks = restore_blocks(lab.work / f"restore-blocks-{family}")
    scratch.put(blocks, "/root/blocks-restore")
    scratch.put(clean_labs_directory(lab), "/root/labs")
    assert_driver_passed(
        scratch.exec(
            "bash", "/root/labs/pg_restore_lab.sh", "/root/blocks-restore",
            env={"SK_LAB_DISPOSABLE": "1"}, timeout=600,
        ).stdout
    )


def clean_labs_directory(lab: Lab) -> Path:
    """The two shell files the scratch container needs (it has no repository copy)."""
    destination = lab.work / "labs-for-scratch"
    if not destination.exists():
        destination.mkdir()
        for name in ("lab_common.sh", "pg_restore_lab.sh"):
            (destination / name).write_bytes((LAB_REPO / "tests/labs" / name).read_bytes())
    return destination


def test_debian_unattended_upgrades_origins_match_the_security_archive(lab: Lab) -> None:
    """The documented Debian origins must match the security archive and list its pending upgrades."""
    container = lab.src("debian")
    blocks = unattended_blocks(lab.work / "uu-blocks")
    container.put(blocks, "/root/blocks-uu")
    assert_driver_passed(run_driver(container, "unattended_upgrades_lab.sh", "/root/blocks-uu"))


def shell_sources(repository: Path) -> list[str]:
    """Every shell source in the repository copy: *.sh files and extensionless files with a bash or sh shebang."""
    found: list[str] = []
    for path in sorted(repository.rglob("*")):
        if not path.is_file() or any(part in {".git", "node_modules"} for part in path.parts):
            continue
        if path.suffix == ".sh":
            found.append(path.relative_to(repository).as_posix())
        elif path.suffix == "":
            first = path.read_bytes()[:64].split(b"\n", 1)[0]
            if first.startswith(b"#!") and (b"bash" in first or first.endswith(b"/sh")):
                found.append(path.relative_to(repository).as_posix())
    return found


@pytest.mark.parametrize("family", FAMILIES)
def test_shellcheck_reports_no_warnings(lab: Lab, family: str) -> None:
    """ShellCheck (0.9.0 on Debian 12, the Fedora 44 package on Fedora) finds no warning or error anywhere."""
    container = lab.src(family)
    sources = shell_sources(lab.work / "repo")
    assert len(sources) >= 30, f"expected the engine's shell sources, found {len(sources)}"
    result = container.exec(
        "bash", "-c",
        "cd /opt/repo && shellcheck --version | sed -n 2p && "
        f"shellcheck -x --severity=warning {' '.join(sources)}",
        timeout=600,
    )
    assert result.returncode == 0, f"ShellCheck findings in {family}:\n{result.stdout}"
