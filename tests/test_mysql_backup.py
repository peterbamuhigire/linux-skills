"""Opt-in MySQL 8.4 backup/restore exercise in disposable Podman containers.

Run with LINUX_SKILLS_MYSQL_BACKUP_LAB=1 pytest -q tests/test_mysql_backup.py.
The test uses a synthetic database, an internal network, and a local rclone
backend. It publishes no database ports and never calls a paid cloud service.
"""
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

from __future__ import annotations

import os
import secrets
import shutil
import stat
import subprocess
import time
import uuid
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
MYSQL_IMAGE = os.environ.get("MYSQL_BACKUP_LAB_IMAGE", "docker.io/library/mysql:8.4")
RCLONE_IMAGE = os.environ.get("MYSQL_BACKUP_RCLONE_IMAGE", "docker.io/rclone/rclone")


def _run(args: list[str], *, input_text: str | None = None, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )


def _podman(*args: str, input_text: str | None = None, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    return _run(["podman", *args], input_text=input_text, timeout=timeout)


def _require_ok(result: subprocess.CompletedProcess[str], label: str) -> str:
    assert result.returncode == 0, f"{label} failed (exit {result.returncode}):\n{result.stdout}"
    return result.stdout


def _image_available(image: str) -> bool:
    return _podman("image", "exists", image).returncode == 0


def _client_config(path: Path, host: str, password: str) -> None:
    path.write_text(
        f"[client]\nuser=root\npassword={password}\nhost={host}\nprotocol=tcp\nport=3306\n",
        encoding="utf-8",
    )
    path.chmod(0o600)


def _run_script(
    *,
    network: str,
    lab_root: Path,
    backup_subdir: str,
    remote_subdir: str,
    path_prefix: str = "/lab/bin",
    extra_env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    environment = {
        "PATH": f"{path_prefix}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "MYSQL_CNF": "/lab/source.cnf",
        "BACKUP_DIR": f"/lab/{backup_subdir}",
        "GPG_KEY_FILE": "/lab/gpg-passphrase",
        "LOCAL_RETENTION_DAYS": "7",
        "REMOTE_RETENTION_DAYS": "7",
    }
    if extra_env:
        environment.update(extra_env)
    args = [
        "run", "--rm", "--security-opt", "label=disable", "--network", network,
        "-v", f"{REPO_ROOT}:/repo:ro", "-v", f"{lab_root}:/lab:rw", "-w", "/repo",
    ]
    for key, value in environment.items():
        args.extend(["-e", f"{key}={value}"])
    args.extend([
        MYSQL_IMAGE, "bash", "-lc",
        "umask 077; bash scripts/sk-mysql-backup.sh --yes "
        f"--mysql-cnf /lab/source.cnf --backup-dir /lab/{backup_subdir} "
        "--gpg-key-file /lab/gpg-passphrase "
        f"--rclone-remote :local:/lab/{remote_subdir}",
    ])
    return _podman(*args, timeout=240)


@pytest.mark.skipif(
    os.environ.get("LINUX_SKILLS_MYSQL_BACKUP_LAB") != "1",
    reason="opt-in disposable MySQL/Podman integration lab",
)
def test_mysql_backup_restore_repeat_and_failures(tmp_path: Path) -> None:
    if shutil.which("podman") is None:
        pytest.skip("Podman is required for the disposable integration lab")
    if not _image_available(MYSQL_IMAGE) or not _image_available(RCLONE_IMAGE):
        pytest.skip("pre-pulled MySQL 8.4 and rclone images are required; this test does not pull images")

    lab_root = tmp_path / "mysql-backup-lab"
    lab_root.mkdir(mode=0o700)
    lab_root.chmod(0o700)
    (lab_root / "bin").mkdir(mode=0o700)
    password = secrets.token_urlsafe(24)
    passphrase = secrets.token_urlsafe(24)
    (lab_root / "root-password").write_text(password, encoding="utf-8")
    (lab_root / "root-password").chmod(0o600)
    (lab_root / "gpg-passphrase").write_text(passphrase + "\n", encoding="utf-8")
    (lab_root / "gpg-passphrase").chmod(0o600)
    suffix = uuid.uuid4().hex[:10]
    network = f"mysql-backup-{suffix}"
    source = f"mysql-lab-source-{suffix}"
    target = f"mysql-lab-target-{suffix}"
    _client_config(lab_root / "source.cnf", source, password)
    _client_config(lab_root / "target.cnf", target, password)
    created: list[str] = []
    try:
        _require_ok(_podman("network", "create", "--internal", network), "create internal network")
        for name in (source, target):
            result = _podman(
                "run", "-d", "--name", name, "--network", network,
                "-e", f"MYSQL_ROOT_PASSWORD={password}", MYSQL_IMAGE,
                "--event-scheduler=ON",
            )
            _require_ok(result, f"start {name}")
            created.append(name)

        for name in (source, target):
            ready = False
            for _ in range(90):
                result = _podman(
                    "exec", "-e", f"MYSQL_PWD={password}", name,
                    "mysql", "-uroot", "--protocol=tcp", "--host=127.0.0.1", "-Nse", "SELECT 1", timeout=10,
                )
                if result.returncode == 0:
                    ready = True
                    break
                time.sleep(2)
            assert ready, f"{name} did not become ready"

        _require_ok(
            _podman(
                "exec", "-i", "-e", f"MYSQL_PWD={password}", source, "mysql", "-uroot",
                input_text=(
                    "CREATE DATABASE lab_app; USE lab_app; "
                    "CREATE TABLE witness (id INT PRIMARY KEY, marker VARCHAR(100) NOT NULL); "
                    "INSERT INTO witness VALUES (1, 'synthetic-mysql-backup-witness'); "
                    "CREATE TABLE audit (entry VARCHAR(100)); "
                    "CREATE TRIGGER witness_after_insert AFTER INSERT ON witness "
                    "FOR EACH ROW INSERT INTO audit VALUES (NEW.marker); "
                    "CREATE PROCEDURE read_witness() SELECT id, marker FROM witness;\n"
                ),
            ),
            "create synthetic schema",
        )

        rclone_container = f"mysql-rclone-{suffix}"
        _require_ok(_podman("create", "--name", rclone_container, RCLONE_IMAGE), "create rclone image container")
        try:
            _require_ok(
                _podman("cp", f"{rclone_container}:/usr/local/bin/rclone", str(lab_root / "bin" / "rclone")),
                "copy rclone executable into temporary lab",
            )
        finally:
            _podman("rm", rclone_container)
        (lab_root / "bin" / "rclone").chmod(0o755)

        version_result = _podman(
            "exec", "-e", f"MYSQL_PWD={password}", source,
            "mysql", "-uroot", "-Nse", "SELECT VERSION()",
        )
        version = _require_ok(version_result, "read source version").strip()
        assert version.startswith("8.4."), f"expected MySQL 8.4, got {version!r}"

        started = time.monotonic()
        first = _run_script(
            network=network, lab_root=lab_root, backup_subdir="backups", remote_subdir="remote",
        )
        first_elapsed = time.monotonic() - started
        _require_ok(first, "first backup")
        assert "backup completed successfully" in first.stdout
        backups = sorted((lab_root / "backups").glob("mysql-backup_*.tar.gz.gpg"))
        remote_backups = sorted((lab_root / "remote").glob("mysql-backup_*.tar.gz.gpg"))
        assert len(backups) == 1 and len(remote_backups) == 1
        assert stat.S_IMODE(backups[0].stat().st_mode) == 0o600
        assert not list((lab_root / "backups").glob(".mysql-backup.*"))

        invalid_retention = _run_script(
            network=network, lab_root=lab_root, backup_subdir="invalid-retention", remote_subdir="remote",
            extra_env={"LOCAL_RETENTION_DAYS": "7;rm"},
        )
        assert invalid_retention.returncode == 2
        assert "LOCAL_RETENTION_DAYS must be a positive whole number" in invalid_retention.stdout
        assert not (lab_root / "invalid-retention").exists()

        restore = _podman(
            "run", "--rm", "--security-opt", "label=disable", "--network", network,
            "-v", f"{REPO_ROOT}:/repo:ro", "-v", f"{lab_root}:/lab:rw", "-w", "/repo",
            "-e", "PATH=/lab/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            MYSQL_IMAGE, "bash", "-lc",
            "umask 077; mkdir -m 0700 -p /lab/extract; "
            "gpg --batch --decrypt --passphrase-file /lab/gpg-passphrase "
            f"--output /lab/restore.tar.gz /lab/backups/{backups[0].name}; "
            "tar -xzf /lab/restore.tar.gz -C /lab/extract; "
            "sql=$(find /lab/extract -type f -name 'database_*_lab_app.sql' -print -quit); "
            "test -n \"$sql\"; mysql --defaults-file=/lab/target.cnf < \"$sql\"; "
            "mysql --defaults-file=/lab/target.cnf -Nse \""
            "SELECT COUNT(*), MIN(marker) FROM lab_app.witness; "
            "SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='lab_app'; "
            "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='lab_app';\"",
        )
        restore_output = _require_ok(restore, "decrypt and restore to second MySQL instance")
        assert "1\tsynthetic-mysql-backup-witness\n1\n1" in restore_output

        time.sleep(2)
        repeated = _run_script(
            network=network, lab_root=lab_root, backup_subdir="backups", remote_subdir="remote",
        )
        _require_ok(repeated, "repeated backup")
        backups = sorted((lab_root / "backups").glob("mysql-backup_*.tar.gz.gpg"))
        remote_backups = sorted((lab_root / "remote").glob("mysql-backup_*.tar.gz.gpg"))
        assert len(backups) == 2 and len(remote_backups) == 2
        assert backups[0].name != backups[1].name
        assert all(stat.S_IMODE(path.stat().st_mode) == 0o600 for path in backups)

        gpg_failure_dir = lab_root / "gpg-failure-bin"
        gpg_failure_dir.mkdir(mode=0o700)
        fail_gpg = gpg_failure_dir / "gpg"
        fail_gpg.write_text("#!/bin/sh\nprintf 'controlled GPG failure\\n' >&2\nexit 42\n", encoding="utf-8")
        fail_gpg.chmod(0o755)
        controlled = _run_script(
            network=network, lab_root=lab_root, backup_subdir="gpg-failure", remote_subdir="remote",
            path_prefix="/lab/gpg-failure-bin:/lab/bin",
        )
        assert controlled.returncode == 1, f"controlled GPG failure exit was {controlled.returncode}"
        assert "gpg encryption failed" in controlled.stdout
        assert not list((lab_root / "gpg-failure").glob("mysql-backup_*.tar.gz"))
        assert not list((lab_root / "gpg-failure").glob("mysql-backup_*.tar.gz.gpg"))
        assert not list((lab_root / "gpg-failure").glob(".mysql-backup.*"))

        rclone_failure_dir = lab_root / "rclone-failure-bin"
        rclone_failure_dir.mkdir(mode=0o700)
        fail_rclone = rclone_failure_dir / "rclone"
        fail_rclone.write_text(
            "#!/bin/sh\nif [ \"$1\" = delete ]; then "
            "printf 'controlled rclone retention failure\\n' >&2; exit 42; fi\n"
            "exec /lab/bin/rclone \"$@\"\n",
            encoding="utf-8",
        )
        fail_rclone.chmod(0o755)
        retention_failure = _run_script(
            network=network, lab_root=lab_root, backup_subdir="retention-failure", remote_subdir="remote",
            path_prefix="/lab/rclone-failure-bin:/lab/bin",
        )
        assert retention_failure.returncode == 1
        assert "remote backup retention failed" in retention_failure.stdout
        assert "backup completed successfully" not in retention_failure.stdout
        retained = list((lab_root / "retention-failure").glob("mysql-backup_*.tar.gz.gpg"))
        assert len(retained) == 1 and stat.S_IMODE(retained[0].stat().st_mode) == 0o600

        assert first_elapsed > 0
    finally:
        for name in created:
            _podman("rm", "--force", "--volumes", name, timeout=30)
        _podman("network", "rm", network, timeout=30)
