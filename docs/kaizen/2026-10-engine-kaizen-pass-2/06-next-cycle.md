# Next cycle and handoffs — after pass 2

Owner: Peter Bamuhigire. Re-audit **2026-11-07**, or earlier on a relevant advisory or when
PostgreSQL 14 reaches its final release (2026-11-12). Target remains 95/100 raw; the gap is not
closed by scoring changes. Items carried from 29 October are marked *carried*; each was checked
open before it was kept here.

## Decision needed from Peter

The installed copies on the validation workstation are older than the repository: `sk-mysql-backup`
0.3.0 in `/usr/local/bin` and a June `common.sh` without the temporary-directory validation (evidence:
[host sample](samples/host-installed-copies-stale.log)). The 29 October backup repairs and this pass's fixes are
not live there. Updating needs `sudo install-skills-bin core --force` after reviewing the diff. This
pass did not run it (no `sudo`; the brief forbids changing the host). Say whether to do it, or whether
a cron entry on that machine uses the installed script.

## Open work

| Priority | Open work and acceptance evidence |
|---|---|
| P1 | *Carried.* Approved Debian 13 and enterprise RHEL disposable VMs: real systemd, enforcing SELinux, firewall and SSH recovery console, ACME staging renewal, repeated-run, controlled-failure and restore evidence. Add the P2-01 case end to end on a real cloud image: apply the provisioning SSH step beside a genuine `50-cloud-init.conf`, reload, show `sshd -T`, key login, rollback. |
| P1 | `install-skills-bin --list` prints `yes` for an installed script that differs from the repository copy, and `install-skills-bin core` refuses to replace it without `--force`. Add a `differs` state and a library line to `--list` (needs `cmp`, which `--list` already tolerates missing), with a fixture in `scripts/tests/install-skills-bin.test.sh`. Would have exposed the stale host in one command. Not done: it would have been an eleventh item. |
| P1 | `sk-pg-backup` against a real PostgreSQL 18 container, in the style of the MySQL lab: the stub assertions (modes, failed dump, retention), then the new "Verify a logical backup" procedure with timings and reconciliation. Requires pre-pulled Podman images. Until then the PostgreSQL restore procedure is untested. |
| P1 | `sk-capture.sh` (lines 146 to 151, 179): default output is `$SK_AUDIT_DIR` (`/var/log/linux-skills`, root, 0750) and `tcpdump` is started without `-Z`. The `tcpdump` manual on the Fedora 44 workstation says that when run as root it changes to user `tcpdump` after opening the capture device and before opening savefiles, "enabled by default (-Z tcpdump)". A savefile in a `root:root` 0750 directory would then not be writable, and the pcap mode follows the umask. Needs root to run either: the failure and the file mode are `NOT_ASSESSED`; the manual wording is sourced. |
| P1 | *Carried.* Execute the 22 scripts that still have no failure or rollback fixture, by risk class. This pass searched for the defect classes found here (writable output, sourced configuration, predictable `/tmp`, swallowed `find` errors) with `scan_scripts` style greps and the new static guard; only the sourcing class is automated. Add scanners for output modes and swallowed pipeline status. |
| P1 | *Carried.* Production-size backup RPO and RTO, storage exhaustion, remote outage, retention expiry. |
| P2 | `kaizen_metrics.py --output` also prints the full JSON to standard output; add a `--quiet` switch or stop echoing when `--output` is given. |
| P2 | Lexical routing ranker artefacts, recorded not tuned: `linux-mysql-mariadb` enters the top three for PostgreSQL prompts because its description names `linux-postgresql`; `netmiko-ssh-automation` ranks above `linux-server-hardening` for "SSH password authentication" because the token is in its name. Decide whether to evaluate with the model router (needs authorisation for paid calls) or to weight only a description's leading clause. 34 skills still lack 3 positives and 2 owned negatives. |
| P2 | Routing fixtures for the nine skills this pass touched only mechanically (heading rename or link repair): `linux-cloud-init`, `linux-config-management`, `linux-disaster-recovery`, `linux-dns-server`, `linux-mail-server`, `linux-network-admin`, `linux-observability`, `linux-secrets`, `linux-virtualization`. |
| P2 | `install-skills-bin --help` still lists exit code 3 as "not Debian/Ubuntu" although the engine is two-family. |
| P2 | `provisioning-steps.md` line 407 expects "PostgreSQL 14.x (22.04)"; 14 reaches its final release on 2026-11-12. Debian 12 examples remain where Debian 13 is stable (*carried*). Re-check after the date. |
| P2 | RHEL 10 host check of the dnf automatic unit names and which dnf generation its package ships (`dnf-reference.md` states this as not assessed). Decide `--no-tablespaces` for `sk-mysql-backup` so the account does not need `PROCESS`; run the privilege list on a MySQL container. |
| P2 | LSR-03 and LSR-09 are partial: re-read the Ubuntu Apache page (the `sites-enabled` claim) and the RHEL 9 Nginx stream list against the RHEL 9 release notes. |
| P2 | *Carried.* Review remaining release-specific examples against current distro packages; Ubuntu CIS rows were not re-fetched. |

## Cross-engine mismatches and boundaries

No sibling checkout was read or edited in this pass, and no relative Markdown link into another
engine was introduced. These are catalogue names, not filesystem paths.

- **Engine names after the upstream renames.** Local `AGENTS.md` lines 46, 59 and 175 name
  `digital-research-engine` and `chwezi-dev-engine` ("resolve through the device catalogue"); the local
  checkouts are `chwezi-research-engine` and `skills-web-dev`. `README.md` line 163 links the GitHub
  URL of `chwezi-dev-engine`; whether it redirects was not checked. No validator in this repository
  searches for sibling checkouts (`scripts/generate-plugin-manifest.js` mentions engine names only in
  comments), so nothing fails; the portfolio cycle should reconcile the names. Counterpart side: the
  catalogue file `chwezi-engine-agents/catalog/engines.yaml` was not read.
- **Deployment runtime and currentness.** `16-network-equipment/network-config-validation/SKILL.md`
  (around line 301) cites the development engine's `docs/source-registers/skills-engine-currentness-2026-09.json`.
  Resolved on 29 October; not re-read here. Separately, upstream Nginx stable is 1.30.6 while Debian 13 and
  RHEL ship older branches (see `currency.md`): the development engine's deployment policy should say
  "package branch, not upstream stable". Counterpart policy file `NOT_ASSESSED`.
- **Shared safety model.** `scripts/lib/common.sh` gained `sk_source_trusted_config` and a private audit
  fallback. The Windows engine's matching files were not inspected: semantic equality `NOT_ASSESSED`;
  a configuration-import trust check may be worth mirroring there.
- **Financial backup retention.** Unchanged: the local 7 and 3 day defaults are not legal retention advice;
  the accounting doctrine counterpart was not read.
- **Research engine.** During this pass the research engine's `AGENTS.md` changed on disk (its machine-error
  gate now takes an `--engines-root` argument). Not mine and not touched; mentioned only so the portfolio
  cycle knows the file moved while this cycle ran.

## One small experiment for next time

Run the existing `tests/test_pg_backup.py` assertions against a throwaway PostgreSQL 18 container (no
published ports, synthetic data, Podman images pulled beforehand), replacing only the stubs. If every assertion holds,
restore the dump and globals into a second container with the documented procedure and record the
elapsed time and object counts. If one fails, the stub fixture was too kind: fix the fixture first.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
