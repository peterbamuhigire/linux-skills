"""Opt-in MySQL 8.4 backup/restore exercise in disposable Podman containers.

Run with LINUX_SKILLS_MYSQL_BACKUP_LAB=1 pytest -q tests/test_mysql_backup.py.
The test uses a synthetic database, an internal network, and a local rclone
backend. It publishes no database ports and never calls a paid cloud service.
"""
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

from __future__ import annotations

import os
import re
import secrets
import shutil
import stat
import subprocess
import time
import uuid
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
# The repository copy mounted read-only into lab containers, and a prefix for every
# container and network name so an operator can find and remove them by name.
LAB_REPO = Path(os.environ.get("LINUX_SKILLS_LAB_REPO", str(REPO_ROOT)))
LAB_PREFIX = os.environ.get("LINUX_SKILLS_LAB_PREFIX", "")
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


def _name_args(kind: str) -> list[str]:
    """`--name` for short-lived lab containers, so `podman ps` shows who owns them."""
    if not LAB_PREFIX:
        return []
    return ["--name", f"{LAB_PREFIX}{kind}-{uuid.uuid4().hex[:8]}"]


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
    cnf: str = "/lab/source.cnf",
) -> subprocess.CompletedProcess[str]:
    environment = {
        "PATH": f"{path_prefix}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "MYSQL_CNF": cnf,
        "BACKUP_DIR": f"/lab/{backup_subdir}",
        "GPG_KEY_FILE": "/lab/gpg-passphrase",
        "LOCAL_RETENTION_DAYS": "7",
        "REMOTE_RETENTION_DAYS": "7",
    }
    if extra_env:
        environment.update(extra_env)
    args = [
        "run", "--rm", *_name_args("script"), "--security-opt", "label=disable", "--network", network,
        "-v", f"{LAB_REPO}:/repo:ro", "-v", f"{lab_root}:/lab:rw", "-w", "/repo",
    ]
    for key, value in environment.items():
        args.extend(["-e", f"{key}={value}"])
    args.extend([
        MYSQL_IMAGE, "bash", "-lc",
        "umask 077; bash scripts/sk-mysql-backup.sh --yes "
        f"--mysql-cnf {cnf} --backup-dir /lab/{backup_subdir} "
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
    network = f"{LAB_PREFIX}mysql-backup-{suffix}"
    source = f"{LAB_PREFIX}mysql-lab-source-{suffix}"
    target = f"{LAB_PREFIX}mysql-lab-target-{suffix}"
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

        rclone_container = f"{LAB_PREFIX}mysql-rclone-{suffix}"
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
            "run", "--rm", *_name_args("restore"), "--security-opt", "label=disable", "--network", network,
            "-v", f"{LAB_REPO}:/repo:ro", "-v", f"{lab_root}:/lab:rw", "-w", "/repo",
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


# --- least-privilege backup account ---------------------------------------------------------

BACKUP_ACCOUNT_DOC = LAB_REPO / "11-databases-and-caching/linux-mysql-mariadb/references/backup-and-restore.md"
ACCOUNT_PLACEHOLDER = "<generated, kept only in the 0600 option file>"


def _documented_account_sql(password: str) -> str:
    """The CREATE USER and GRANT statements of the 'Backup account' section, verbatim."""
    section = BACKUP_ACCOUNT_DOC.read_text(encoding="utf-8").split("## Backup account", 1)[1].split("\n## ", 1)[0]
    block = re.search(r"```sql\n(.*?)```", section, re.S)
    assert block, "no sql block in the Backup account section"
    sql = block.group(1)
    assert ACCOUNT_PLACEHOLDER in sql, "password placeholder not found in the documented SQL"
    return sql.replace(ACCOUNT_PLACEHOLDER, password)


def _sql(container: str, password: str, sql: str, *, user: str = "root") -> subprocess.CompletedProcess[str]:
    """Run SQL as USER over the container's local socket, so 'user'@'localhost' accounts apply."""
    args = ["exec", "-i", "-e", f"MYSQL_PWD={password}", container, "mysql", f"-u{user}", "--batch", "--skip-column-names"]
    return _podman(*args, input_text=sql + "\n", timeout=60)


def _wait_ready(container: str, password: str) -> None:
    for _ in range(90):
        if _sql(container, password, "SELECT 1").returncode == 0:
            return
        time.sleep(2)
    raise AssertionError(f"{container} did not become ready")


def _script_in(container: str, *, backup_subdir: str, cnf: str) -> subprocess.CompletedProcess[str]:
    """Run sk-mysql-backup inside the database container, as it runs on a real host."""
    command = (
        "umask 077; cd /repo && "
        f"MYSQL_CNF={cnf} BACKUP_DIR=/lab/{backup_subdir} GPG_KEY_FILE=/lab/gpg-passphrase "
        "LOCAL_RETENTION_DAYS=7 REMOTE_RETENTION_DAYS=7 PATH=/lab/bin:$PATH "
        f"bash scripts/sk-mysql-backup.sh --yes --mysql-cnf {cnf} --backup-dir /lab/{backup_subdir} "
        f"--gpg-key-file /lab/gpg-passphrase --rclone-remote :local:/lab/remote-{backup_subdir}"
    )
    return _podman("exec", container, "bash", "-lc", command, timeout=240)


def _extract_newest(container: str, backup_subdir: str) -> str:
    """Decrypt and unpack the newest archive of a backup directory; return the extraction directory."""
    command = (
        "set -e; umask 077; d=$(mktemp -d /lab/x.XXXXXX); "
        f"f=$(ls -t /lab/{backup_subdir}/mysql-backup_*.tar.gz.gpg | head -1); "
        'gpg --batch --quiet --decrypt --passphrase-file /lab/gpg-passphrase --output $d/a.tar.gz "$f"; '
        "tar -xzf $d/a.tar.gz -C $d; echo $d"
    )
    return _require_ok(_podman("exec", container, "bash", "-lc", command), "extract archive").strip().splitlines()[-1]


def _dumped_files(container: str, extraction_dir: str) -> list[str]:
    out = _require_ok(
        _podman("exec", container, "find", extraction_dir, "-type", "f", "-name", "*.sql", "-printf", "%f\n"),
        "list dump files",
    )
    return sorted(out.split())


def _dumped_schemas(files: list[str]) -> set[str]:
    return {re.sub(r"^database_\d+_", "", name)[: -len(".sql")] for name in files if name.startswith("database_")}


@pytest.mark.skipif(
    os.environ.get("LINUX_SKILLS_MYSQL_BACKUP_LAB") != "1",
    reason="opt-in disposable MySQL/Podman integration lab",
)
def test_mysql_backup_least_privilege_account(tmp_path: Path) -> None:
    """The documented 'sk_backup' grants must back up, restore, and be unable to write."""
    if shutil.which("podman") is None:
        pytest.skip("Podman is required for the disposable integration lab")
    if not _image_available(MYSQL_IMAGE) or not _image_available(RCLONE_IMAGE):
        pytest.skip("pre-pulled MySQL 8.4 and rclone images are required; this test does not pull images")

    lab_root = tmp_path / "mysql-account-lab"
    (lab_root / "bin").mkdir(parents=True, mode=0o700)
    lab_root.chmod(0o700)
    root_password = secrets.token_urlsafe(24)
    account_password = secrets.token_urlsafe(24)
    (lab_root / "gpg-passphrase").write_text(secrets.token_urlsafe(24) + "\n", encoding="utf-8")
    (lab_root / "gpg-passphrase").chmod(0o600)
    suffix = uuid.uuid4().hex[:10]
    network = f"{LAB_PREFIX}mysql-account-{suffix}"
    source = f"{LAB_PREFIX}mysql-acct-source-{suffix}"
    target = f"{LAB_PREFIX}mysql-acct-target-{suffix}"
    rclone_container = f"{LAB_PREFIX}mysql-acct-rclone-{suffix}"
    created: list[str] = []
    try:
        _require_ok(_podman("network", "create", "--internal", network), "create internal network")
        for name in (source, target):
            _require_ok(
                _podman("run", "-d", "--name", name, "--network", network,
                        "-e", f"MYSQL_ROOT_PASSWORD={root_password}", MYSQL_IMAGE, "--event-scheduler=ON"),
                f"start {name}",
            )
            created.append(name)
        for name in (source, target):
            _wait_ready(name, root_password)

        _require_ok(_podman("create", "--name", rclone_container, RCLONE_IMAGE), "create rclone image container")
        try:
            _require_ok(
                _podman("cp", f"{rclone_container}:/usr/local/bin/rclone", str(lab_root / "bin" / "rclone")),
                "copy rclone executable",
            )
        finally:
            _podman("rm", "--force", rclone_container)
        (lab_root / "bin" / "rclone").chmod(0o755)

        schema = (
            "CREATE DATABASE lab_app; CREATE DATABASE lab_hidden; USE lab_app; "
            "CREATE TABLE witness (id INT PRIMARY KEY, marker VARCHAR(100) NOT NULL); "
            "INSERT INTO witness VALUES (1, 'synthetic-account-witness'), (2, 'second-row'); "
            "CREATE TABLE audit (entry VARCHAR(100)); "
            "CREATE TRIGGER witness_after_insert AFTER INSERT ON witness FOR EACH ROW INSERT INTO audit VALUES (NEW.marker); "
            "CREATE VIEW witness_view AS SELECT id FROM witness; "
            "CREATE PROCEDURE read_witness() SELECT id, marker FROM witness; "
            "CREATE EVENT lab_event ON SCHEDULE EVERY 1 DAY DISABLE DO SELECT 1; "
            "USE lab_hidden; CREATE TABLE secret (id INT PRIMARY KEY); INSERT INTO secret VALUES (7);"
        )
        _require_ok(_sql(source, root_password, schema), "create synthetic schemas")

        # The script runs inside the source container, as it does on a real host, so the documented
        # 'sk_backup'@'localhost' account applies unchanged.
        _require_ok(_podman("cp", str(LAB_REPO), f"{source}:/repo"), "copy the repository copy into the container")
        _require_ok(_podman("cp", str(lab_root), f"{source}:/lab"), "copy lab files into the container")

        def cnf_for(user: str, password: str, name: str) -> str:
            path = f"/lab/{name}.cnf"
            body = f"[client]\nuser={user}\npassword={password}\n"
            _require_ok(
                _podman("exec", "-i", source, "bash", "-c", f"umask 077; cat > {path}", input_text=body),
                f"write {name}.cnf",
            )
            return path

        # 1. The account the documentation describes, created from the documentation's own SQL.
        _require_ok(_sql(source, root_password, _documented_account_sql(account_password)), "create documented account")
        documented_cnf = cnf_for("sk_backup", account_password, "sk_backup")
        run = _script_in(source, backup_subdir="documented", cnf=documented_cnf)
        _require_ok(run, "backup with the documented account")
        assert "backup completed successfully" in run.stdout

        # Every schema the server holds (bar the three the script excludes by design) must be in the archive.
        visible = set(_require_ok(_sql(source, root_password, "SHOW DATABASES"), "SHOW DATABASES").split())
        expected = visible - {"information_schema", "performance_schema", "sys"}
        extraction = _extract_newest(source, "documented")
        files = _dumped_files(source, extraction)
        assert _dumped_schemas(files) == expected, f"dumped {sorted(_dumped_schemas(files))}, server holds {sorted(expected)}"
        assert any(not name.startswith("database_") for name in files), f"no all-databases dump among {files}"

        # 2. Restore into the second instance and reconcile rows, triggers, routines, events and views.
        lab_app_sql = _require_ok(
            _podman("exec", source, "bash", "-lc", f"cat {extraction}/dump_*/database_*_lab_app.sql"),
            "read the lab_app dump",
        )
        _require_ok(_sql(target, root_password, lab_app_sql), "restore lab_app into the target")
        counts = (
            "SELECT (SELECT COUNT(*) FROM lab_app.witness), "
            "(SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='lab_app'), "
            "(SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='lab_app'), "
            "(SELECT COUNT(*) FROM information_schema.events WHERE event_schema='lab_app'), "
            "(SELECT COUNT(*) FROM information_schema.views WHERE table_schema='lab_app');"
        )
        source_counts = _require_ok(_sql(source, root_password, counts), "source counts").strip()
        target_counts = _require_ok(_sql(target, root_password, counts), "target counts").strip()
        assert source_counts == target_counts == "2\t1\t1\t1\t1"

        # 3. The account must be unable to change anything.
        writes = [
            "INSERT INTO lab_app.witness VALUES (99, 'must-not-exist')",
            "UPDATE lab_app.witness SET marker = 'changed' WHERE id = 1",
            "DELETE FROM lab_app.witness",
            "CREATE TABLE lab_app.should_not_exist (i INT)",
            "DROP TABLE lab_app.audit",
            "CREATE USER 'sk_intruder'@'%' IDENTIFIED BY 'x'",
            "GRANT ALL ON *.* TO 'sk_backup'@'localhost'",
            "UPDATE mysql.user SET authentication_string = '' WHERE user = 'root'",
        ]
        for statement in writes:
            attempt = _sql(source, account_password, statement, user="sk_backup")
            assert attempt.returncode != 0 and "denied" in attempt.stdout.lower(), f"{statement!r} was not refused: {attempt.stdout}"
        assert _require_ok(_sql(source, root_password, "SELECT COUNT(*) FROM lab_app.witness"), "row count").strip() == "2"
        assert "sk_intruder" not in _require_ok(_sql(source, root_password, "SELECT user FROM mysql.user"), "users")

        # 4. What narrowing the grants does, as the 'Backup account' section describes it.
        variants = {
            "noproc": "GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, RELOAD ON *.* TO 'sk_noproc'@'localhost'",
            "norel": "GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, PROCESS ON *.* TO 'sk_norel'@'localhost'",
            "schema": (
                "GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON lab_app.* TO 'sk_schema'@'localhost'; "
                "GRANT PROCESS, RELOAD ON *.* TO 'sk_schema'@'localhost'"
            ),
            "visible": (
                "GRANT SELECT, SHOW VIEW, TRIGGER, EVENT ON lab_app.* TO 'sk_visible'@'localhost'; "
                "GRANT SHOW VIEW ON lab_hidden.* TO 'sk_visible'@'localhost'; "
                "GRANT PROCESS, RELOAD ON *.* TO 'sk_visible'@'localhost'"
            ),
        }
        results: dict[str, subprocess.CompletedProcess[str]] = {}
        dumped: dict[str, set[str]] = {}
        for label, grants in variants.items():
            _require_ok(
                _sql(source, root_password, f"CREATE USER 'sk_{label}'@'localhost' IDENTIFIED BY '{account_password}'; {grants};"),
                f"create {label}",
            )
            results[label] = _script_in(source, backup_subdir=label, cnf=cnf_for(f"sk_{label}", account_password, f"sk_{label}"))
            if results[label].returncode == 0:
                dumped[label] = _dumped_schemas(_dumped_files(source, _extract_newest(source, label)))

        # Without PROCESS mysqldump reports an access-denied error about tablespaces but still exits 0 and
        # dumps every schema; without RELOAD (GTIDs off) it needs nothing more.
        assert results["noproc"].returncode == 0 and dumped["noproc"] == expected
        assert "PROCESS privilege" in results["noproc"].stdout
        assert results["norel"].returncode == 0 and dumped["norel"] == expected
        # An account that cannot see a schema leaves it out, and the run still reports success.
        assert results["schema"].returncode == 0 and "backup completed successfully" in results["schema"].stdout
        assert dumped["schema"] == {"lab_app"}
        # An account that can see a schema but cannot read it makes the script stop with exit 1.
        assert results["visible"].returncode == 1, results["visible"].stdout
        assert "mysqldump failed" in results["visible"].stdout
    finally:
        for name in created:
            _podman("rm", "--force", "--volumes", name, timeout=30)
        _podman("network", "rm", network, timeout=30)
