"""Configuration-trust tests for scripts/sk-mysql-backup.sh that need no database.

The script stops in ``load_config`` before it checks for MySQL tools or touches a
backup directory, so these cases run anywhere. The restore and failure behaviour of
the backup itself is covered by the opt-in Podman lab in test_mysql_backup.py.

Author: Peter Bamuhigire <techguypeter.com> +256784464178
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "sk-mysql-backup.sh"
LIBRARY = ROOT / "scripts" / "lib" / "common.sh"
INSTALLED_LIBRARY_LINE = 'SK_LIB="/usr/local/lib/linux-skills/common.sh"'


class MysqlBackupConfigurationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.work = Path(tempfile.mkdtemp(prefix="mysql-backup-config-test."))
        self.addCleanup(shutil.rmtree, self.work, True)
        self.tmp = self.work / "tmp"
        self.tmp.mkdir(mode=0o700)
        self.script = self.make_script_tree(LIBRARY.read_text(encoding="utf-8"))

    def make_script_tree(self, library_text: str) -> Path:
        tree = self.work / "tree" / "scripts"
        (tree / "lib").mkdir(parents=True, exist_ok=True)
        (tree / "lib" / "common.sh").write_text(library_text, encoding="utf-8")
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertEqual(source.count(INSTALLED_LIBRARY_LINE), 1, "library line changed; update the fixture")
        script = tree / "sk-mysql-backup.sh"
        script.write_text(
            source.replace(INSTALLED_LIBRARY_LINE, f'SK_LIB="{tree / "lib" / "common.sh"}"'),
            encoding="utf-8",
        )
        return script

    def run_script(self, config: Path | None) -> subprocess.CompletedProcess[str]:
        environment = {
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "TMPDIR": str(self.tmp),
            "HOME": str(self.work),
            "LC_ALL": "C",
            "SK_MYSQL_BACKUP_CONFIG": str(config if config else self.work / "absent.conf"),
        }
        return subprocess.run(
            ["bash", str(self.script), "--yes", "--dry-run"],
            env=environment,
            text=True,
            capture_output=True,
            check=False,
            timeout=60,
        )

    def write_config(self, text: str, mode: int) -> Path:
        path = self.work / "mysql-backup.conf"
        path.write_text(text, encoding="utf-8")
        path.chmod(mode)
        return path

    def test_writable_configuration_is_refused_and_never_executed(self) -> None:
        marker = self.work / "executed"
        for mode in (0o666, 0o664, 0o602):
            with self.subTest(mode=oct(mode)):
                config = self.write_config(f'touch "{marker}"\n', mode)
                result = self.run_script(config)
                self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                self.assertIn("refusing to load configuration", result.stdout + result.stderr)
                self.assertFalse(marker.exists(), "a writable configuration file must not be executed")

    def test_symlinked_configuration_is_refused(self) -> None:
        real = self.write_config("RETENTION_NOTE=1\n", 0o600)
        link = self.work / "link.conf"
        link.symlink_to(real)
        result = self.run_script(link)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)

    def test_trusted_configuration_is_loaded(self) -> None:
        config = self.write_config("LOCAL_RETENTION_DAYS=5\n", 0o600)
        result = self.run_script(config)
        self.assertIn("loaded config from", result.stdout)

    def test_older_library_stops_with_a_clear_message(self) -> None:
        self.script = self.make_script_tree("sk_on_exit() { :; }\n")
        result = self.run_script(None)
        self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
        self.assertIn("older than this script", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
