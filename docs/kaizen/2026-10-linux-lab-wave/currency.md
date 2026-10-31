# Currency record — Linux lab wave, 31 October 2026

The wave brief does not ask for a source-register refresh and none was done: pass 2 re-verified ten source
rows on the same date (`docs/kaizen/2026-10-engine-kaizen-pass-2/currency.md`), the metrics gate reports 0
expired rows at the baseline and at the end, and no new web source was fetched in this wave. Nothing below is a
source-register entry. These are versions and behaviours observed by running commands in containers on
2026-10-31, kept here so a reader can tell an observation from a verified source.

| Observation | How obtained | Support state | Review by |
|---|---|---|---|
| Debian 12 security archive publishes `Origin: Debian`, `Label: Debian-Security`, `Suite: oldstable-security`, `Codename: bookworm-security` | `InRelease` file read inside `debian:bookworm` after `apt-get update` | Observed. The Suite name changes when the release moves from stable to oldstable, which is why the Debian procedure matches on `codename` and `label` | Re-read when Debian 13 point releases change the archive layout, and before 2026-11-30 |
| Debian 12 `ssh.service` carries `Alias=sshd.service` and has `ExecReload=/usr/sbin/sshd -t` before the `kill -HUP` | `systemctl cat ssh` and `systemctl reload sshd` (exit 0) in `debian:bookworm` | Observed on Debian 12 only. Ubuntu 22.04 and 24.04 not assessed | 2026-11-30 |
| Fedora 44 `sshd.service` has `ExecReload=/bin/kill -HUP $MAINPID` and no `ssh.service` | `systemctl cat`, `systemctl reload ssh` (exit 5) in `fedora:44`, OpenSSH 10.2p1 | Observed on Fedora 44. RHEL 9 and 10 not assessed; enterprise units may differ | 2026-11-30 |
| dnf5 5.4.6.0 on Fedora 44: `dnf-automatic` installs `dnf5-plugin-automatic`; `dnf-automatic.timer` is an alias; `dnf5-automatic.timer` disabled by preset | `dnf`, `rpm -q`, `systemctl list-unit-files` in `fedora:44` | Observed; confirms the pass-2 page. RHEL 10 not assessed | 2026-11-30 |
| PostgreSQL 15.19 (Debian 12) and 18.6 (Fedora 44): `pg_restore --exit-on-error --create --dbname=postgres < dump` restores; `pg_restore -j` from standard input is refused | restore lab | Observed | with the next PostgreSQL minor release |
| MySQL 8.4.13 `mysqldump`: no `PROCESS` gives a stderr access-denied line about tablespaces and exit 0 | direct probe and lab | Observed on 8.4.13 only. MySQL 8.0, 9.x and MariaDB not assessed | 2026-11-30 |
| ShellCheck 0.9.0 (Debian 12 package) and the Fedora 44 package version printed by `shellcheck --version` | `shellcheck --version` in each container | Observed; version of the Fedora package is in the lab output | next distro release |

`NOT_ASSESSED`, with the reason: current Debian and RHEL-family release and support status beyond the
pass-2 record (not re-fetched in this wave); Nginx, Apache and PHP-FPM supported branches; CIS Benchmark
versions; Let's Encrypt certificate lifetime changes; Cisco IOS-XE release references. All were last verified
in pass 2 or the 29 October cycle, and this wave's brief does not cover them.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
