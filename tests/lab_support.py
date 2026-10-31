"""Helpers for the opt-in Podman distro labs (tests/test_distro_labs.py).

Rootless Podman only, local images only, no published ports, no host paths mounted. Every container
is named with LINUX_SKILLS_LAB_PREFIX (default "lskw-") so it can be found and removed by name.
Real systemd is PID 1 in each container: the image runs a package install, then execs systemd.
"""
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

from __future__ import annotations

import os
import re
import shutil
import subprocess
import time
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
LAB_REPO = Path(os.environ.get("LINUX_SKILLS_LAB_REPO", str(REPO_ROOT)))
PREFIX = os.environ.get("LINUX_SKILLS_LAB_PREFIX", "lskw-")
LAB_ENV = "LINUX_SKILLS_LAB"

IMAGES = {
    "debian": os.environ.get("LINUX_SKILLS_LAB_DEBIAN_IMAGE", "docker.io/library/debian:bookworm"),
    "fedora": os.environ.get("LINUX_SKILLS_LAB_FEDORA_IMAGE", "quay.io/fedora/fedora:44"),
}

# Packages each role needs. "src" runs the scripts and procedures; "scratch" only receives a restore.
PACKAGES = {
    ("debian", "src"): "openssh-server openssh-client sshpass sudo procps postgresql postgresql-contrib "
    "unattended-upgrades apt-listchanges shellcheck",
    ("debian", "scratch"): "sudo procps postgresql postgresql-contrib",
    ("fedora", "src"): "dbus-broker openssh-server openssh-clients sshpass sudo procps-ng postgresql-server "
    "postgresql-contrib dnf-automatic cronie findutils diffutils ShellCheck",
    ("fedora", "scratch"): "dbus-broker sudo procps-ng postgresql-server postgresql-contrib",
}


def run(args: list[str], *, input_text: str | None = None, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args, input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=timeout, check=False,
    )


def podman(*args: str, input_text: str | None = None, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return run(["podman", *args], input_text=input_text, timeout=timeout)


def podman_ready(*images: str) -> str | None:
    """None when Podman and every image are present locally, else the reason to skip."""
    if shutil.which("podman") is None:
        return "Podman is required for the disposable distro labs"
    for image in images:
        if podman("image", "exists", image).returncode != 0:
            return f"image {image} is not present locally; these labs never pull images"
    return None


def clean_repo_copy(destination: Path) -> Path:
    """A copy of the checkout without .git or caches, so the lab never reads a bind mount of the live tree."""
    shutil.copytree(
        LAB_REPO, destination,
        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc", "node_modules"),
    )
    return destination


class LabContainer:
    """One throwaway systemd container, named PREFIX + role, removed by name."""

    def __init__(self, family: str, role: str) -> None:
        self.family = family
        self.role = role
        self.name = f"{PREFIX}lab-{family}-{role}-{uuid.uuid4().hex[:6]}"

    def start(self) -> None:
        packages = PACKAGES[(self.family, self.role)]
        if self.family == "debian":
            setup = (
                "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && "
                f"apt-get install -y -qq systemd systemd-sysv {packages} >/root/setup.log 2>&1; "
                "echo $? >/root/setup.rc; exec /lib/systemd/systemd"
            )
        else:
            setup = (
                "dnf -y --setopt=install_weak_deps=False install systemd "
                f"{packages} >/root/setup.log 2>&1; echo $? >/root/setup.rc; exec /usr/lib/systemd/systemd"
            )
        result = podman(
            "run", "--pull=never", "--detach", "--name", self.name, "--systemd=always",
            IMAGES[self.family], "bash", "-c", setup,
        )
        if result.returncode != 0:
            raise RuntimeError(f"cannot start {self.name}: {result.stdout}")

    def wait_ready(self, timeout: int = 900) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            rc = self.exec("cat", "/root/setup.rc", timeout=20)
            if rc.returncode == 0:
                if rc.stdout.strip() != "0":
                    log = self.exec("tail", "-n", "20", "/root/setup.log", timeout=20).stdout
                    raise RuntimeError(f"package install failed in {self.name}:\n{log}")
                state = self.exec("systemctl", "is-system-running", timeout=20).stdout.strip()
                if state in {"running", "degraded"}:
                    return
            time.sleep(3)
        raise RuntimeError(f"{self.name} was not ready within {timeout}s")

    def prepare_postgres(self) -> None:
        """Make PostgreSQL run under systemd. Debian creates the cluster at install time."""
        if self.family == "fedora":
            for command in (
                "systemctl enable --now dbus-broker",
                "postgresql-setup --initdb",
                "systemctl enable --now postgresql",
            ):
                result = self.exec("bash", "-c", command, timeout=300)
                if result.returncode != 0:
                    raise RuntimeError(f"{command!r} failed in {self.name}:\n{result.stdout}")
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if self.exec("bash", "-c", "sudo -u postgres psql -X -Atc 'select 1' 2>/dev/null", timeout=30).stdout.strip() == "1":
                return
            time.sleep(2)
        raise RuntimeError(f"PostgreSQL did not come up in {self.name}")

    def exec(self, *command: str, timeout: int = 600, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        args = ["exec"]
        for key, value in (env or {}).items():
            args += ["-e", f"{key}={value}"]
        return podman(*args, self.name, *command, timeout=timeout)

    def put(self, source: Path, destination: str) -> None:
        result = podman("cp", str(source), f"{self.name}:{destination}")
        if result.returncode != 0:
            raise RuntimeError(f"podman cp into {self.name} failed: {result.stdout}")

    def get(self, source: str, destination: Path) -> None:
        result = podman("cp", f"{self.name}:{source}", str(destination))
        if result.returncode != 0:
            raise RuntimeError(f"podman cp out of {self.name} failed: {result.stdout}")

    def remove(self) -> None:
        podman("rm", "--force", "--volumes", self.name, timeout=60)


def markdown_blocks(document: Path, heading: str) -> list[str]:
    """Fenced code blocks (any indentation) in the section that starts at HEADING, verbatim."""
    lines = document.read_text(encoding="utf-8").splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith(heading))
    level = len(heading) - len(heading.lstrip("#"))
    end = len(lines)
    in_fence = False
    for i in range(start + 1, len(lines)):
        if re.match(r"^\s*```", lines[i]):
            in_fence = not in_fence
            continue
        match = None if in_fence else re.match(r"^(#+) ", lines[i])
        if match and len(match.group(1)) <= level:
            end = i
            break
    blocks: list[str] = []
    buffer: list[str] | None = None
    indent = 0
    for line in lines[start:end]:
        fence = re.match(r"^(\s*)```", line)
        if buffer is None and fence:
            buffer, indent = [], len(fence.group(1))
        elif buffer is not None and fence:
            blocks.append("\n".join(buffer) + "\n")
            buffer = None
        elif buffer is not None:
            buffer.append(line[indent:] if line[:indent].strip() == "" else line)
    return blocks


def pick_block(blocks: list[str], needle: str) -> str:
    """The one block containing NEEDLE; more or fewer than one is a documentation change to look at."""
    found = [block for block in blocks if needle in block]
    if len(found) != 1:
        raise AssertionError(f"expected exactly one documented block containing {needle!r}, found {len(found)}")
    return found[0]


def write_blocks(directory: Path, named: dict[str, str]) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    for name, text in named.items():
        (directory / name).write_text(text, encoding="utf-8")
    return directory
