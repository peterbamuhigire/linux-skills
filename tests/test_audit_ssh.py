"""Exercise the audit's actual SSH/firewall sections without host access.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
"""
import subprocess
import unittest
from pathlib import Path

SCRIPT = (Path(__file__).resolve().parents[1] / 'scripts/sk-audit.sh').read_text()
FUNCTION = SCRIPT[SCRIPT.index('ssh_setting() {'):SCRIPT.index('\nsysctl_check()')]
SSH = SCRIPT[SCRIPT.index('# --- 2. SSH hardening'):SCRIPT.index('# --- 3. Firewall')]
UPDATES = SCRIPT[SCRIPT.index('# --- 1. System updates'):SCRIPT.index('# --- 2. SSH hardening')]
FIREWALL = SCRIPT[SCRIPT.index('# --- 3. Firewall'):SCRIPT.index('# --- 4. Fail2Ban')]


class AuditChecks(unittest.TestCase):
    def run_section(self, section, stubs):
        code = '''set -uo pipefail
pass() { printf 'PASS %s\\n' "$*"; }
warn() { printf 'WARN %s\\n' "$*"; }
fail() { printf 'FAIL %s\\n' "$*"; }
info() { :; }
header() { :; }
pkg_is_installed() { return 0; }
systemctl() { return 0; }
''' + FUNCTION + stubs + section
        result = subprocess.run(['bash', '-c', code], text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_failed_package_query_cannot_report_current(self):
        stub = "\nSK_DISTRO_FAMILY=rhel\nSK_PKG=dnf\ndnf() { return 1; }\n"
        output = self.run_section(UPDATES, stub)
        self.assertIn('NOT_ASSESSED: cached package update query failed', output)
        self.assertNotIn('fully up to date', output)

    def test_dnf_update_exit_100_is_not_a_query_failure(self):
        stub = "\nSK_DISTRO_FAMILY=rhel\nSK_PKG=dnf\ndnf() { echo 'package.x86_64 2.0 updates'; return 100; }\n"
        output = self.run_section(UPDATES, stub)
        self.assertNotIn('query failed', output)
        self.assertNotIn('fully up to date', output)

    def test_failed_sshd_never_infers_defaults(self):
        output = self.run_section(SSH, '\nsshd() { return 1; }\n')
        self.assertIn('NOT_ASSESSED', output)
        self.assertNotIn('PASS ', output)

    def test_empty_sshd_never_passes(self):
        output = self.run_section(SSH, '\nsshd() { return 0; }\n')
        self.assertNotIn('PASS ', output)

    def test_effective_values_and_keyboard_interactive(self):
        stub = '''
sshd() {
    [[ "$*" == "-T" ]] || return 9
    printf '%s\\n' 'permitrootlogin yes' 'passwordauthentication no' \
        'kbdinteractiveauthentication yes' 'pubkeyauthentication yes' \
        'maxauthtries 3' 'permitemptypasswords no'
}
'''
        output = self.run_section(SSH, stub)
        self.assertIn('FAIL Root login is permitted: yes', output)
        self.assertIn('PASS MaxAuthTries is set to 3', output)
        self.assertNotIn('PASS Password', output)
        self.assertIn('MFA policy', output)

    def test_missing_fields_are_unknown(self):
        output = self.run_section(SSH, "\nsshd() { echo 'port 22'; }\n")
        self.assertNotIn('PASS ', output)
        self.assertIn('NOT_ASSESSED', output)

    def test_ufw_inactive_is_not_active(self):
        output = self.run_section(FIREWALL, "\nSK_DISTRO_FAMILY=debian\nufw() { echo 'Status: inactive'; }\n")
        self.assertIn('FAIL UFW firewall is NOT active', output)
        self.assertNotIn('PASS UFW firewall is active', output)

    def test_ufw_active_is_recognised(self):
        stub = "\nSK_DISTRO_FAMILY=debian\nufw() { printf '%s\\n' 'Status: active' 'Default: deny (incoming)' '22 ALLOW'; }\n"
        output = self.run_section(FIREWALL, stub)
        self.assertIn('PASS UFW firewall is active', output)


if __name__ == '__main__':
    unittest.main()
