"""Fixture tests for scripts/sk-pg-backup.sh.

The script runs against PATH stubs for sudo, psql, pg_dump, pg_dumpall, pg_restore
and (in one case) find, inside a temporary directory. No PostgreSQL server is
contacted, nothing outside the temporary directory is written, and the role hash
in the globals output is synthetic. A real dump and a real restore are a separate,
lab-only check.

Author: Peter Bamuhigire <techguypeter.com> +256784464178
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sk-pg-backup.sh"
SYNTHETIC_HASH = "SCRAM-SHA-256$4096:SYNTHETIC-FIXTURE-HASH"

STUBS = {
    # Drop "-u user", then run the rest the way the postgres user would: umask 022.
    "sudo": r"""#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then shift 2; fi
umask 022
exec "$@"
""",
    # STUB_DATABASES holds names separated by "|"; psql -0 emits them NUL-terminated,
    # otherwise one per line, as the real client does.
    "psql": r"""#!/usr/bin/env bash
terminator='\n'
for a in "$@"; do [[ "$a" == "-0" ]] && terminator='\0'; done
IFS='|' read -r -a names <<< "${STUB_DATABASES:-appdb|salesdb}"
for n in "${names[@]}"; do printf "%s$terminator" "$n"; done
""",
    "pg_dumpall": r"""#!/usr/bin/env bash
printf "CREATE ROLE app;\nALTER ROLE app WITH LOGIN PASSWORD '%s';\n" "$SYNTHETIC_HASH"
""",
    # Writes to --file=PATH when given, otherwise to standard output, like pg_dump.
    "pg_dump": r"""#!/usr/bin/env bash
file=""
for a in "$@"; do case "$a" in --file=*) file="${a#--file=}" ;; esac; done
db="${@: -1}"
emit() { if [[ -n "$file" ]]; then printf '%s' "$1" > "$file"; else printf '%s' "$1"; fi; }
if [[ "$db" == "${STUB_PG_DUMP_FAIL:-}" ]]; then
    emit 'PGDMP partial'
    exit 1
fi
emit "PGDMP synthetic custom-format fixture for $db"$'\n'
""",
    "pg_restore": r"""#!/usr/bin/env bash
[[ -z "${STUB_PG_RESTORE_FAIL:-}" ]] || { echo "pg_restore: not a valid archive" >&2; exit 1; }
head -c 5 "$2" | grep -q '^PGDMP' || { echo "pg_restore: not a valid archive" >&2; exit 1; }
""",
}

FAILING_FIND = r"""#!/usr/bin/env bash
if [[ "$*" == *-delete* ]]; then echo "find: cannot delete" >&2; exit 1; fi
exec /usr/bin/find "$@"
"""


class PgBackupFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.work = Path(tempfile.mkdtemp(prefix="pg-backup-test."))
        self.addCleanup(shutil.rmtree, self.work, True)
        self.stubs = self.work / "stubs"
        self.stubs.mkdir()
        for name, body in STUBS.items():
            self.install_stub(name, body)
        self.tmp = self.work / "tmp"
        self.tmp.mkdir(mode=0o700)
        self.backups = self.work / "backups"

    def install_stub(self, name: str, body: str) -> None:
        path = self.stubs / name
        path.write_text(body, encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": f"{self.stubs}:/usr/local/bin:/usr/bin:/bin",
            "SYNTHETIC_HASH": SYNTHETIC_HASH,
            "SK_PG_BACKUP_CONFIG": str(self.work / "absent.conf"),
            "TMPDIR": str(self.tmp),
            "HOME": str(self.work),
            "LC_ALL": "C",
        }
        environment.update(env or {})
        return subprocess.run(
            ["bash", str(SCRIPT), "--yes", "--backup-dir", str(self.backups), *args],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
            preexec_fn=lambda: os.umask(0o022),  # the usual default: the script must not rely on it
        )

    def entries(self) -> list[str]:
        return sorted(p.name for p in self.backups.iterdir()) if self.backups.exists() else []

    def mode(self, path: Path) -> int:
        return stat.S_IMODE(path.stat().st_mode)


class PgBackupModeTests(PgBackupFixture):
    def test_new_directory_and_every_artefact_are_private(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.mode(self.backups), 0o700)
        names = self.entries()
        self.assertEqual(len([n for n in names if n.startswith("globals_") and n.endswith(".sql")]), 1)
        self.assertEqual(len([n for n in names if n.endswith(".dump")]), 2)
        for name in names:
            self.assertEqual(self.mode(self.backups / name), 0o600, name)
        globals_file = next(self.backups / n for n in names if n.startswith("globals_"))
        self.assertIn(SYNTHETIC_HASH, globals_file.read_text(encoding="utf-8"))

    def test_staging_directory_is_removed_after_success(self) -> None:
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual([n for n in self.entries() if n.startswith(".")], [])

    def test_existing_loose_directory_warns_and_files_stay_private(self) -> None:
        self.backups.mkdir(mode=0o755)
        self.backups.chmod(0o755)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("other users can list backup names", result.stdout)
        self.assertEqual(self.mode(self.backups), 0o755, "an existing directory must not be re-moded")
        for name in self.entries():
            self.assertEqual(self.mode(self.backups / name), 0o600, name)


class PgBackupFailureTests(PgBackupFixture):
    def test_failed_dump_leaves_no_partial_file_or_staging_directory(self) -> None:
        result = self.run_script(env={"STUB_PG_DUMP_FAIL": "salesdb"})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("pg_dump failed for salesdb", result.stdout + result.stderr)
        self.assertEqual([n for n in self.entries() if n.startswith("salesdb")], [])
        self.assertEqual([n for n in self.entries() if n.startswith(".")], [])
        for name in self.entries():
            text = (self.backups / name).read_text(encoding="utf-8")
            self.assertNotIn("partial", text, name)

    def test_dump_that_pg_restore_cannot_read_is_not_published(self) -> None:
        result = self.run_script(env={"STUB_PG_RESTORE_FAIL": "1"})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual([n for n in self.entries() if n.endswith(".dump")], [])
        self.assertEqual([n for n in self.entries() if n.startswith(".")], [])

    def test_retention_failure_fails_the_run(self) -> None:
        self.install_stub("find", FAILING_FIND)
        result = self.run_script()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("local backup retention failed", result.stdout + result.stderr)
        self.assertNotIn("backup completed successfully", result.stdout)

    def test_invalid_retention_is_rejected_before_anything_is_written(self) -> None:
        for value in ("abc", "0", "-1", "1.5", ""):
            with self.subTest(value=value):
                result = self.run_script("--retention", value)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertFalse(self.backups.exists())

    def test_relative_backup_directory_is_rejected(self) -> None:
        result = subprocess.run(
            ["bash", str(SCRIPT), "--yes", "--backup-dir", "relative/path"],
            env={"PATH": f"{self.stubs}:/usr/bin:/bin", "TMPDIR": str(self.tmp), "SK_PG_BACKUP_CONFIG": str(self.work / "absent.conf")},
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)


class PgBackupRetentionTests(PgBackupFixture):
    def age(self, path: Path, days: int) -> None:
        stamp = time.time() - days * 86400
        os.utime(path, (stamp, stamp))

    def test_only_this_scripts_names_are_pruned(self) -> None:
        self.backups.mkdir(mode=0o700)
        old_dump = self.backups / "appdb_20200101-000000.dump"
        old_globals = self.backups / "globals_20200101-000000.sql"
        unrelated_dump = self.backups / "manual-export.dump"
        unrelated_note = self.backups / "notes.txt"
        fresh_dump = self.backups / "appdb_20990101-000000.dump"
        for path in (old_dump, old_globals, unrelated_dump, unrelated_note):
            path.write_text("x", encoding="utf-8")
            self.age(path, 30)
        fresh_dump.write_text("x", encoding="utf-8")
        result = self.run_script("--retention", "7")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(old_dump.exists())
        self.assertFalse(old_globals.exists())
        self.assertTrue(unrelated_dump.exists(), "a dump the script did not name must survive retention")
        self.assertTrue(unrelated_note.exists())
        self.assertTrue(fresh_dump.exists())


class PgBackupNamingTests(PgBackupFixture):
    def test_hostile_database_names_stay_inside_the_backup_directory(self) -> None:
        names = "app db|../escape|a/b|a_b"
        result = self.run_script(env={"STUB_DATABASES": names})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        dumps = [n for n in self.entries() if n.endswith(".dump")]
        self.assertEqual(len(dumps), 4, dumps)
        self.assertEqual(len(set(dumps)), 4, "distinct names must not collide on one file")
        for name in self.entries():
            self.assertNotIn("/", name)
            resolved = (self.backups / name).resolve()
            self.assertEqual(resolved.parent, self.backups.resolve())
        self.assertEqual(sorted(p.name for p in self.work.iterdir()), ["backups", "stubs", "tmp"])


class PgBackupDryRunTests(PgBackupFixture):
    def test_dry_run_writes_nothing(self) -> None:
        result = self.run_script("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("dry-run completed; no backup was written", result.stdout)
        self.assertFalse(self.backups.exists())


if __name__ == "__main__":
    unittest.main()
