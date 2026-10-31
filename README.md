# Linux Skills

Linux Skills is an operations engine for administering Linux servers and the network equipment around them. Its 48 skills cover the working life of a host: provisioning and first boot, users and secrets, networking and DNS, web and mail services, systemd and virtualisation, storage, hardening, intrusion detection, observability, troubleshooting and disaster recovery, Bash automation, databases and caches, containers, backup and archiving, performance and kernel tuning, compliance auditing, and Cisco IOS/IOS-XE configuration review. A hub skill, `linux-sysadmin`, routes each request to the narrowest specialist. Linux specialists carry a `## Distro support` matrix covering both the Debian/Ubuntu and RHEL families (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Network-appliance specialists declare their vendor scope instead. Every procedure declares its target, preconditions, a bounded change, a rollback route and a verification step. Mutating work is preview-first and needs explicit authority; evidence that is unavailable is recorded as `NOT ASSESSED`, never assumed.

The engine produces server provisioning plans and cloud-init, autoinstall and Kickstart files; Ansible desired-state playbooks; hardening and read-only security assessments; firewall, TLS and certificate configurations; site release and rollback runbooks; database backup, restore and point-in-time recovery procedures; container deployment specifications; observability and log-shipping configurations; incident diagnosis trees; recovery procedures; and 26 `sk-*` Bash scripts built on a shared `common.sh` contract. For network devices it produces bounded IOS change plans, Netmiko collection scripts and static configuration preflight reports. Its procedures follow the IETF RFCs for DNS, SMTP submission, TLS, HSTS, ACME, SPF, DKIM and DMARC. Compliance work uses CIS Benchmark and DISA STIG profiles through OpenSCAP and the SCAP Security Guide, and TLS work follows Mozilla's server-side TLS guidance. It is written for Linux administrators, infrastructure and network engineers, service owners and support teams, and for AI agents (Claude Code, Codex and others) acting on their behalf.

## Quality and improvement

The October 2026 Kaizen cycles are recorded under `docs/kaizen/`. Each folder holds the numbered files 00 to 06 (scope and evidence, baseline scorecard, backlog, experiment log, validation record, final report, next cycle) and the raw samples behind them. [`docs/README.md`](docs/README.md) indexes the rest of `docs/`.

| Cycle | Evidence folder | Read first |
|---|---|---|
| 29 October 2026, first cycle | [`docs/kaizen/2026-10-engine-kaizen/`](docs/kaizen/2026-10-engine-kaizen/) | [Final report](docs/kaizen/2026-10-engine-kaizen/05-final-report.md) |
| 31 October 2026, pass 2 | [`docs/kaizen/2026-10-engine-kaizen-pass-2/`](docs/kaizen/2026-10-engine-kaizen-pass-2/) | [Final report](docs/kaizen/2026-10-engine-kaizen-pass-2/05-final-report.md), [operator note](docs/updates/2026-10-31-kaizen-pass-2.md) |
| 31 October 2026, Linux lab wave (rootless Podman labs) | [`docs/kaizen/2026-10-linux-lab-wave/`](docs/kaizen/2026-10-linux-lab-wave/) | [Final report](docs/kaizen/2026-10-linux-lab-wave/05-final-report.md), [operator note](docs/kaizen/2026-10-linux-lab-wave/operator-note.md) |

**Latest published score** (lab wave final report): ten equally weighted dimensions, raw mean **77.9**, published score `min(raw, 65)` = **65.0**. The raw mean moved 50.5 (first-cycle baseline), 74.0 (first-cycle final), 75.6 (pass 2 final), 77.9 (lab wave final). The 95/100 raw target is not met: the raw mean is 17.1 points short, and the 65 cap is a reporting ceiling that does not close that gap. The first-cycle report also records a stricter 45/100 ceiling requested for that cycle. Scores are reviewer judgements against named evidence, not a percentage of anything.

### What the October 2026 kaizen improved

The three cycles ([29 October](docs/kaizen/2026-10-engine-kaizen/03-experiment-log.md), [pass 2](docs/kaizen/2026-10-engine-kaizen-pass-2/03-experiment-log.md) and the [lab wave](docs/kaizen/2026-10-linux-lab-wave/03-experiment-log.md)) kept every experiment they ran; none was reverted. This list holds kept changes only, defects first. Each hash is an ancestor of `main` (`git merge-base --is-ancestor`). "Lab" means a throwaway rootless Podman container, not a production host. Figures marked re-measured were run on 31 October 2026; the rest come from the evidence file named.

**Defects fixed**

1. **Debian automatic security updates matched no security archive (critical).** The provisioning, hardening and package-management procedures told a Debian operator to allow `"${distro_id}:${distro_codename}-security"`, an Ubuntu pattern; on Debian 12 the dry run printed "No packages found that can be upgraded unattended" with a security update pending. The Debian form is now an `Origins-Pattern` with `#clear` and `label=Debian-Security`; the Ubuntu form is kept and marked not run. Verified in a Debian 12 lab (the dry run lists the pending upgrade; 1 passed in 124 s); the same driver fails 4 checks against the old text. Ubuntu is `NOT_ASSESSED`. `92bafbd`
2. **The SSH hardening drop-in lost to cloud-init (critical).** OpenSSH keeps the first value it reads, so `99-hardening.conf` lost to a cloud image's `50-cloud-init.conf` and left `PasswordAuthentication yes`. The drop-in is now `00-linux-skills-ssh.conf` in five procedures, with the precedence rule stated. Verified with `sshd -T` on a fixture (3 of 6 new tests failed before, 6 of 6 pass) and, in the lab wave, with real `sshd` on Debian 12 and Fedora 44: password login refused, key login works, the old name loses. A real cloud image is `NOT_ASSESSED` (the lab imitates `50-cloud-init.conf`). `6f30e09`
3. **`sk-pg-backup` wrote world-readable role password hashes and could publish a partial dump (critical).** Output was directory 755 and files 644. It now stages privately (0700, 0600), checks each dump with `pg_restore --list` before renaming it into place, and prunes only its own files. Verified with stubs (10 of 11 new cases failed against the old script, 11 of 11 pass) and on real PostgreSQL 15.19 and 18.6 in labs, including seven controlled failures that publish nothing. Dumps are still not encrypted, and files written by earlier versions keep their old modes until an operator tightens them. `cae7544`
4. **Temporary cleanup and atomic writes trusted filenames (critical).** A private temporary registry and trusted-parent checks replace that trust; atomic write rejects symlinks and keeps mode and owner with checked operations. An independent review found a writable-ancestor gap in the first attempt; it was repaired and the suites rerun. The `common.sh` suite had 29 cases then (45, re-measured). ACL, xattr and SELinux metadata preservation remain unassessed. `c1a3385`
5. **A failed GPG step left readable plaintext MySQL backups (critical).** A lab reproduced mode 0644 plaintext. Backups now stage privately, clean up on failure and prune with validated retention, and a restore procedure was run. Verified on `mysql:8.4` with synthetic data: mode 0600, a repeated backup, a clean restore into a second instance, injected GPG and retention failures. Production-size data is not assessed. `c47b4ae`
6. **`systemctl reload ssh` does not exist on the RHEL family (major).** The apply and rollback blocks failed on Fedora 44 with `Unit ssh.service not found` (exit 5). They now name `sshd` (an alias on Debian 12), both distro matrices carry an SSH unit row, and every reload after an edit follows `sshd -t &&`: in the lab a bad drop-in followed by a plain reload stopped the daemon on Fedora. Verified by running the blocks as written (5 lab tests passed in 217 s; 8 static tests pass). Enterprise RHEL is `NOT_ASSESSED`. `dad557e`
7. **Root-run scripts trusted configuration files and a predictable `/tmp` path (major).** The backup scripts sourced `/etc/linux-skills/*.conf` unchecked, and the non-root audit fallback wrote to `/tmp/linux-skills-<user>` (mode 755, log 644). `sk_source_trusted_config` now refuses a symlink or a file or directory not owned by root or the caller, or writable by group or others (exit 3), and the fallback uses a validated 0700 directory. Verified by new `common.sh` cases that failed before: 29 to 39 to 42 passed across the two commits. `ec2a269`, `054c45c`
8. **`sk-audit` inferred health from grep and defaults (major).** It now reads effective `sshd -T` values, matches the firewall exactly and labels cached update results, with explicit unknown states. Verified by eight fixture cases (`tests/test_audit_ssh.py`, part of the 119 passed). `4dcaba2`
9. **The installer hid a missing `cmp`.** A dependency check now stops it before any write; a minimal Fedora image had failed idempotence. 21 installer cases passed in each family container in the 29 October record; they need root, so they were not re-run here. `a4e6f7f`
10. **Smaller defects.** Every `die` printed a banner reading `exited N at line 1` and `last command: exit "$code"` in all 26 scripts; it now reports only its own cause (`common.sh` suite 42 to 45, re-measured). `sk-pg-backup` made the Debian client wrapper print `could not change directory to "/root"` on each call; client calls now run from `/`, and the usage text no longer says a failed run leaves nothing (it can leave a globals file). `journalctl -u dnf-automatic` printed no entries on dnf5; the guidance is split by dnf generation and holds on Fedora 44 (dnf5 5.4.6.0). `a31dc52`, `85a96dd`, `9ce3518`

**New checks and tests**

11. **Container labs for the engine's own procedures and scripts.** The lab steps were prose; nothing in the repository could re-run them. `tests/test_distro_labs.py` (opt-in) now runs documented fenced blocks verbatim in Debian 12 and Fedora 44 containers: the SSH drop-in, `sk-pg-backup`, the PostgreSQL "Verify a logical backup" procedure (written in pass 2 as untested, `62f2e56`) and Debian automatic updates. The restore ran in about 0.3 s with eleven reconciliation figures equal; 7 tests passed in 201 s. `2293b73`, `cf670be`
12. **The least-privilege MySQL backup account, verified.** Pass 2 specified the `CREATE USER` and `GRANT` lines from the manual and never ran them (`d42cd1f`). On `mysql:8.4` they back up every schema, restore with rows, triggers, routines, events and views reconciled, and refuse eight write attempts. The page was also wrong that `PROCESS` is required: without it `mysqldump` 8.4.13 exits 0 with an access-denied line about tablespaces and omits general-tablespace statements. 2 tests passed in 70 s. `fe5f9f9`
13. **ShellCheck as a zero-warning gate.** It had been run once by hand. ShellCheck 0.9.0 and 0.11.0 reported 28 warnings (exit 1); the lab test `test_shellcheck_reports_no_warnings` now passes with 0 over 41 shell sources in both containers, with the intended findings annotated inline (29 `# shellcheck disable=` lines). It runs inside the labs, not in CI. `4dabff3`
14. **Stronger distro checks.** The matrix check proved a section existed, not that it was right. It now rejects boilerplate and empty catalogues (ten adversarial cases), and `tests/test_distro_parity.py` fails when a procedure names a Debian-only service unit that its matrix never pairs: 8 unpaired uses in 7 skills to 0, with five negative fixtures. `check-distro-matrix.sh` passes 41 of 41 (re-measured). `4518733`, `ae84c01`
15. **Routing measured, and fixtures where skills were touched.** Passing the top three had been mistaken for coverage. P@1 and owned-negative checks were added, with fixtures for the skills each cycle edited: 109 fixtures, P@1 96/109, P@3 109/109 and 17 of 48 skills at 3 positives and 2 owned negatives (all re-measured). 31 skills still lack that coverage, and the lexical ranker's artefacts are recorded, not tuned. `6e75a2f`, `221871c`, `16e45f2`
16. **CI gates.** Tests had run outside required CI. CI now runs the Python suite with pinned action revisions and limited permissions plus a Fedora 44 fixture job, and a hygiene step fails on new link, anchor, heading or expired-source debt against the pass-2 baseline (`kaizen_metrics.py` gained `--quiet`; an unavailable Fedora image pin was refreshed). Hosted CI last ran on `f904f7b` (all three workflows succeeded on 29 October); the pass 2 and lab wave commits had not been pushed, so it has not run on them. `923342b`, `f904f7b`, `199265f`, `af0e9e0`

**Recovery procedures and sources**

17. **A PHP 502 procedure that observes before it acts.** A short example restarted PHP-FPM without identifying the failing upstream. `php-upgrade-502.md` and `tests/labs/web_502.sh` now cover diagnosis, repair, a repeat, rejection of an invalid configuration and an upstream rollback, run on Debian and Fedora on 29 October with a synthetic 502; no real firewall or ACME change. `4e28dae`
18. **Source and link debt repaid.** Ten expired source rows were re-opened at their primary sources (8 verified, 2 partial), and the dangling local paths (5), dangling anchors (10) and skills with duplicate headings (10) were repaired. All four measures read 0 now (re-measured). The 29 October refresh also added a dated register that separates candidate exposure from installed-host vulnerability. Ten source rows carry a review-by date of 2026-11-30 (see [Date-triggered gates](#date-triggered-gates)). `bdda0a2`, `1ef490f`, `fc0c8af`

**Packaging**

19. **Claude and Codex packages from one set of skill folders.** Both manifests list the same 45 skills (re-measured), `scripts/check_marketplace.py` checks parity, paths and a 5,000-file ceiling (a limit set above 5,000 is rejected), and native offline discovery was recorded for Claude 2.1.312 and Codex 0.165.0. Live client loading and public listing are `NOT_ASSESSED`. `93122fb`, `57bd07d`, `041c738`

**Figures**

| Measure | 29 Oct baseline | 29 Oct final | Pass 2 final | Lab wave final | Source |
|---|---:|---:|---:|---:|---|
| Raw mean, ten dimensions | 50.5 | 74.0 | 75.6 | 77.9 | Final reports |
| Published `min(raw, 65)` | 50.5 | 65.0 | 65.0 | 65.0 | Final reports |
| Routing fixtures | 30 | 80 | 95 | 109 | Experiment logs; 109 re-measured |
| Top-1 routing (P@1) | 25/30 | 67/80 | 82/95 | 96/109 | Experiment logs; 96/109 re-measured |
| Skills at 3 positive and 2 owned-negative fixtures | 0 | 11 | 14 | 17 of 48 | Experiment logs; 17 re-measured |
| `common.sh` suite, passed | not recorded | 29 | 42 | 45 | Validation records; 45 re-measured |
| Full suite, real pytest | not recorded | not recorded | 102 passed, 1 skipped | 119 passed, 9 skipped | [Lab wave validation record](docs/kaizen/2026-10-linux-lab-wave/04-validation-record.md); 119 and 9 re-measured |
| Dangling local paths, dangling anchors | 7, 10 | 5, 10 | 0, 0 | 0, 0 | Final reports; 0, 0 re-measured |
| Skills with duplicate contract headings | 10 | 10 | 0 | 0 | Final reports; 0 re-measured |
| Expired source rows | 10 | 10 | 0 | 0 | Final reports; 0 re-measured |
| ShellCheck warnings | not recorded | not recorded | 28 | 0 | Lab wave validation record; not re-measured (no ShellCheck or container in the documentation wave) |
| Opt-in container lab tests | not recorded | 1 | 1 | 9 | Validation records; 9 re-measured as the default run's skips |

The raw mean is a reviewer judgement against named evidence and cannot be re-measured with a command. The pass 2 column of the full-suite row is the lab wave's baseline, which is the pass 2 end state.

### Open findings that matter to a user

- **Installed copies of the `sk-*` scripts can be older than this checkout.** `scripts/install-skills-bin --list` prints `yes` under INSTALLED? even when the installed file differs. See [Updating installed scripts](#updating-installed-scripts).
- **Hosts set up from the earlier procedures need two read-only checks.** A Debian host configured from the older "Unattended security upgrades" text may not be patching itself, and `systemctl reload ssh` does not exist on the RHEL family. The [lab wave operator note](docs/kaizen/2026-10-linux-lab-wave/operator-note.md) has the commands.
- **Not tested.** The labs ran Debian 12, Fedora 44 and MySQL 8.4 in rootless Podman containers. Ubuntu 22.04 and 24.04, enterprise RHEL and its rebuilds, Debian 13, a real cloud image with cloud-init, enforcing SELinux, firewalld, UFW and nftables, and ACME issuance are `NOT_ASSESSED`. 22 of the 26 `sk-*` scripts have not been run in any lab ([lab wave final report](docs/kaizen/2026-10-linux-lab-wave/05-final-report.md#residual-risk-and-scope)).
- **Known behaviours of the backup scripts.** `sk-mysql-backup` against MySQL 8.4 without the `PROCESS` privilege exits 0 but prints an access-denied line about tablespaces and leaves out general-tablespace statements. `sk-pg-backup` writes the globals file first, so a run that fails on a later database leaves globals and no dumps. `sk-capture` may fail to write its default output under `tcpdump`'s privilege drop (unverified). Details and the open decisions are in the [lab wave next-cycle file](docs/kaizen/2026-10-linux-lab-wave/06-next-cycle.md).

Use the [current vulnerability triage runbook](docs/security/current-vulnerability-triage.md)
and its dated source register when assessing packages. The watchlist is a review
queue, not proof that a host is vulnerable or fully patched. The
[platform evidence](docs/continuous-improvement/platform-test-matrix-2026-08.md)
distinguishes disposable tests from live service, recovery and production evidence.

### Date-triggered gates

Only the first row is enforced by a validator; the others are review dates written in the evidence and are not scheduled automation.

| Date | What happens | Check |
|---|---|---|
| 2026-12-01 (first failing day) | The CI step "Check bounded hygiene regressions" fails: ten source rows (`LSR01` to `LSR10` in [`P03-linux-web-service-preservation.md`](docs/continuous-improvement/skills-kaizen/P03-linux-web-service-preservation.md)) carry a review-by date of 2026-11-30. Re-verify the sources and move the dates, as pass 2 did for ten earlier rows; do not weaken the gate. | `kaizen_metrics.py --baseline docs/kaizen/2026-10-engine-kaizen-pass-2/metrics-final.json --as-of 2026-11-30` exits 0; `--as-of 2026-12-01` exits 1 with `expired_source_records: 10` (run 31 October 2026) |
| 2026-11-07 | Re-audit date set by the [lab wave next-cycle file](docs/kaizen/2026-10-linux-lab-wave/06-next-cycle.md) | None |
| 2026-11-12 | PostgreSQL 14 reaches its final release; the provisioning steps still expect "PostgreSQL 14.x (22.04)" ([currency record](docs/kaizen/2026-10-engine-kaizen-pass-2/currency.md)) | None |
| 2026-11-16, 2026-11-30, 2026-12-15 | Review-by dates in the [pass-2 currency record](docs/kaizen/2026-10-engine-kaizen-pass-2/currency.md): the PostgreSQL row, most other rows, and the PHP, MySQL 8.0 and Let's Encrypt rows. Their IDs are `P2-C01` to `P2-C11`, which `kaizen_metrics.py` does not read (it lists ten records, all in the file named above) | None |
| 2026-12-28 | Next full model-policy evaluation ([model review](docs/continuous-improvement/model-review-2026-10-29.md)) | None |
| 2026-12-31 | PHP 8.2 reaches end of life and PHP 8.4 leaves active support (currency record, row P2-C05) | None |

## Installation

**Prerequisites.** Git. `diffutils` (`cmp`) for script installation/update; missing dependencies are reported before installation writes. Node.js 18 or later for the clone installers and the plugin's destructive-command hook. Python 3.11 or later for the validators, tests and the Codex model-policy helper; the validators also need `PyYAML` and the tests need `pytest` (see [Validation](#validation)). Bash 4 on target servers for the `sk-*` scripts.

**Claude Code plugin (recommended).** The repository is its own marketplace (`.claude-plugin/marketplace.json`, marketplace `chwezi-linux`, plugin `linux`, version 1.1.0):

```text
/plugin marketplace add https://github.com/peterbamuhigire/linux-skills
/plugin install linux@chwezi-linux
```

**Clone installer.** `install.sh` and `install.ps1` delegate to `scripts/install-engine.js`. Scope is `user` (`~/.claude`, the default) or `project` (`.claude` under the current directory). Add `--dry-run` to preview. Run `install.sh` through `bash`: the file is committed without the executable bit (mode 100644), so `./install.sh` stops with "Permission denied" (exit 126).

```sh
git clone https://github.com/peterbamuhigire/linux-skills
cd linux-skills
bash install.sh --scope project --dry-run   # macOS, Linux or Git Bash; drop --dry-run to install
.\install.ps1 --scope project               # Windows PowerShell
node scripts/install-engine.js doctor --scope project
```

On 31 October 2026, `bash install.sh --scope project --dry-run` on Linux listed the files it would copy into `.claude` under the current directory and wrote nothing, and `doctor` reported "nothing installed". `install.ps1` was not run: the machine used had no PowerShell, so that path is `NOT_ASSESSED`.

**Server toolkit.** On a managed Debian/Ubuntu or RHEL-family host, install the tier-1 `sk-*` scripts to `/usr/local/bin` and `common.sh` to `/usr/local/lib/linux-skills/`. Tier 1 is 13 scripts. Other skills' scripts install on first use (`sudo scripts/install-skills-bin <skill-name>`). The installer needs root even with `--dry-run`; `--list` does not, and shows each script's skill, whether it is tier 1 and whether it is installed.

```sh
scripts/install-skills-bin --list
sudo scripts/install-skills-bin --dry-run core
sudo scripts/install-skills-bin core
```

### Updating installed scripts

Installed copies do not follow the checkout. After updating the repository, compare the installed library and any script you rely on with the repository copy, then reinstall:

```sh
diff /usr/local/lib/linux-skills/common.sh scripts/lib/common.sh
sudo scripts/install-skills-bin core --force      # tier 1; use <skill-name> for another skill's scripts
```

`--list` prints `yes` under INSTALLED? even when the installed file differs from the repository copy, so use `diff` or `cmp`. Without `--force` the installer refuses to replace a differing script. Read the diff first: the [pass 2](docs/updates/2026-10-31-kaizen-pass-2.md) and [lab wave](docs/kaizen/2026-10-linux-lab-wave/operator-note.md) operator notes list which scripts changed.

`scripts/setup-claude-code.sh` is an optional, gated Claude Code bootstrap for a server. Review its `--dry-run` plan first. It needs explicit target, authority and recovery-file flags.

**Codex.** The `.codex-plugin/plugin.json` compatibility manifest exposes the same 45 operational skills as Claude without copying skill content. See [marketplace packaging and checks](docs/marketplace.md) for verified support and public-upload limitations. Both the engine package and this checkout are checked against a hard 5,000-file ceiling. [Native offline tests](docs/kaizen/2026-10-engine-kaizen/portfolio-refresh.md) confirm installation in both CLIs and all 45 declared skills visible in Codex. Manual use needs no installer. Load `AGENTS.md`, then the selected `SKILL.md`. Before substantive work, check the Codex model policy with `python3 .codex/ensure_model_policy.py --runtime codex --check`. Claude skips this step.

**Manual use.** Clone the repository anywhere. Read `CLAUDE.md` (Claude Code) or `AGENTS.md` (any runner), then load `linux-sysadmin/SKILL.md` as the default route. Validate changes as described under [Validation](#validation).

## Validation

Run from the repository root. The commands use `python3`; CI runs the same forms on Ubuntu 24.04 with Python 3.12 ([`skill-quality.yml`](.github/workflows/skill-quality.yml), [`bash-suites.yml`](.github/workflows/bash-suites.yml), [`source-ingestion-guardrail.yml`](.github/workflows/source-ingestion-guardrail.yml)).

**Dependencies.** Python 3.11 or later; `PyYAML` (the skill validator, routing test, hygiene metrics and quick validator import it); `pytest` (the test suite). The repository has no requirements file. Install them into a virtual environment (`python3 -m venv "$VENV" && "$VENV/bin/pip" install PyYAML pytest`) and run the commands below with `"$VENV/bin/python"`. A system Python without `pytest` fails `python3 -m pytest` with "No module named pytest". To keep a run from writing into the checkout, set `PYTHONDONTWRITEBYTECODE=1` and add `-p no:cacheprovider` to pytest. Node.js 18 or later for the manifest generator and the hook tests; Bash for the shell suites. The figures below are from 31 October 2026 on Python 3.14.8, Node.js 22 and `pytest` 9.0.3, on `main`.

| Check | Command | Result |
|---|---|---|
| Skill contracts, zero-debt | `python3 -X utf8 scripts/validate_skills.py --baseline quality-baseline.json` | 48 active skills, 1 template; 48 fully compliant; no failure counts |
| Routing | `python3 -X utf8 scripts/routing_smoke_test.py` | 109 of 109 fixtures valid; P@1 96/109 (0.881); P@3 109/109; 17 of 48 skills at 3 positive and 2 owned-negative fixtures |
| Distro matrices | `bash scripts/tests/check-distro-matrix.sh` | 41 passed, 0 failed |
| Test suite | `python3 -m pytest -q` | 119 passed, 9 skipped, 28 subtests passed; the 9 skips are the opt-in container labs |
| Marketplace packages and file ceiling | `python3 scripts/check_marketplace.py` | PASS; package and checkout file counts are printed against the 5,000 ceiling |
| Plugin manifest | `node scripts/generate-plugin-manifest.js --engine . --root . --exclude "docs,scripts,templates,tests,commands,meta,notes,prompts" --check` | `plugin.json is current`, 45 skills |
| Safe-operation fixture | `python3 -X utf8 scripts/validate_safe_operation_fixture.py tests/fixtures/safe-operation-evidence.json` | 5 fixture cases pass; no host action |
| Source-ingestion guardrail | `python3 -X utf8 scripts/source_ingestion_guardrail.py` | 0 findings |
| `common.sh` suite | `bash scripts/tests/common-sh.test.sh` | 45 passed, 0 failed (one root-only case reports SKIP when run unprivileged) |
| Hygiene gate (date-triggered) | `python3 scripts/kaizen_metrics.py --baseline docs/kaizen/2026-10-engine-kaizen-pass-2/metrics-final.json --output "$OUT" --quiet` | Exit 0, prints nothing; without `--output --quiet` it prints the full JSON report. Fails from 2026-12-01 (see [Date-triggered gates](#date-triggered-gates)) |
| Plugin hook tests | `node hooks/test-destructive-bash-gate.js` and `node hooks/test-plugin-hook-config.js` | 61/61 and 7/7 passed |
| Canonical engine scanner | `python3 -X utf8 <chwezi-dev-engine checkout>/skills/sdlc-meta/skill-engine-audit/scripts/engine_compliance.py --root . --active-root . --details` | 48 skills, 48 fully compliant, 0 safe fixes applied. Needs the engineering-catalogue checkout (on some machines its folder is still named `skills-web-dev`) |
| Skill quick validator | `python3 -X utf8 meta/skill-writing/scripts/quick_validate.py <skill-directory>` | `linux-sysadmin`: "Skill is valid." |
| Whitespace | `git diff --check` | No output |

**Checks that need more than Python and Node.**

- **Root, in a disposable machine.** `sudo bash scripts/tests/install-skills-bin.test.sh` is run by CI under `sudo` in a disposable job and again in a Fedora 44 container. The installer refuses to run unprivileged ("must run as root"): run without root on 31 October 2026 the suite gave 11 passed and 10 failed, the failures following from that refusal, so this check is `NOT_ASSESSED` on a workstation. Run it only as root inside a disposable container or VM.
- **Container labs (opt-in).** `LINUX_SKILLS_LAB=1 python3 -m pytest -rP tests/test_distro_labs.py` runs 7 tests in Debian 12 and Fedora 44 containers; `LINUX_SKILLS_MYSQL_BACKUP_LAB=1 LINUX_SKILLS_LAB_PREFIX=lskw- python3 -m pytest tests/test_mysql_backup.py` runs 2 tests against MySQL 8.4. They need rootless Podman and these images already present locally: `docker.io/library/debian:bookworm`, `quay.io/fedora/fedora:44`, `docker.io/library/mysql:8.4` and `docker.io/rclone/rclone`. They never pull an image or publish a port. The Debian and Fedora labs copy the repository into their containers and mount no host path; the MySQL labs mount the repository read-only and one temporary directory read-write, and use an internal Podman network. The Debian and Fedora containers install their packages from the distribution mirrors, so they need outbound network access from the container. Not run in the documentation wave (no containers). Results from the lab wave: 7 passed in 201 s and 2 passed in 70 s ([validation record](docs/kaizen/2026-10-linux-lab-wave/04-validation-record.md)). After a run, `podman ps --all --format '{{.Names}}' | grep '^lskw-'` must print nothing.
- **ShellCheck.** CI does not run it. It runs inside the lab containers (`test_shellcheck_reports_no_warnings`, ShellCheck 0.9.0 on Debian 12 and 0.11.0 on Fedora 44): `shellcheck -x --severity=warning` over 41 shell sources. The lab wave measured 0 findings; before it there were 28 warnings, which the wave judged to be false positives and annotated inline with `# shellcheck disable=` directives and a reason.
- **PowerShell.** `install.ps1` needs `pwsh` or Windows PowerShell; it was not run in the documentation wave.
- **Not needed.** No check renders a document, so Pandoc, Mermaid, a browser and LibreOffice are not required.

## Capabilities

The engine has 48 active `SKILL.md` files: 44 specialists in 16 numbered categories, the `linux-sysadmin` hub and 3 meta skills. The authoring template in `templates/` is excluded.

| Category | Skill | What it does |
|---|---|---|
| **01 Provisioning and bootstrap (4)** | `linux-cloud-init` | Authors and debugs cloud-init user-data, Ubuntu autoinstall and RHEL Kickstart for first boot. |
| | `linux-config-management` | Keeps repeatable server state with Ansible, etckeeper, check mode and drift remediation. |
| | `linux-package-management` | Installs, pins, upgrades and diagnoses packages and repositories with apt, dnf, snap and Flatpak. |
| | `linux-server-provisioning` | Provisions a fresh server interactively: identity, admin access, updates, firewall, services. |
| **02 Users, access and secrets (2)** | `linux-access-control` | Creates, revokes and audits users, groups, SSH keys, sudo/wheel, PAM and permissions. |
| | `linux-secrets` | Scans for leaked credentials, encrypts configuration with age, sops or GPG, and rotates secrets. |
| **03 Networking and DNS (2)** | `linux-dns-server` | Operates BIND or Unbound: zones, validation, reloads, reverse zones and transfers. |
| | `linux-network-admin` | Diagnoses and configures interfaces, routes, client DNS, VLANs and time sync (Netplan, NetworkManager). |
| **04 Web and mail services (3)** | `linux-mail-server` | Operates Postfix, Exim and Dovecot, mail queues, TLS and SPF/DKIM/DMARC. |
| | `linux-site-deployment` | Releases one site from a pinned revision with vhost cutover, rollback and external verification. |
| | `linux-webstack` | Installs, tunes and diagnoses Nginx, Apache/httpd, PHP-FPM and Node.js, including PHP security patching and staged branch upgrades. |
| **05 Services and virtualisation (2)** | `linux-service-management` | Operates systemd units, timers, targets, journals, restart policy and cgroup limits. |
| | `linux-virtualization` | Runs KVM/libvirt VMs and LXD system containers: lifecycle, snapshots, storage, networking. |
| **06 Storage and filesystems (1)** | `linux-disk-storage` | Diagnoses disk and inode pressure, cleans up measurably, manages swap and NFS/CIFS mounts. |
| **07 Security and hardening (5)** | `linux-firewall-ssl` | Changes UFW/firewalld policy, issues and renews Certbot certificates, validates TLS exposure. |
| | `linux-intrusion-detection` | Operates fail2ban and runs qualified rkhunter/chkrootkit checks. |
| | `linux-ngo-cyber-resilience` | Designs practical Linux security and incident resilience for NGOs and small mission-led teams. |
| | `linux-security-analysis` | Performs a read-only, evidence-backed security assessment across all host layers. |
| | `linux-server-hardening` | Remediates verified findings across SSH, firewall, MAC, services, permissions and updates. |
| **08 Observability and logging (3)** | `linux-log-management` | Analyses time-bounded journald and service logs and manages logrotate retention. |
| | `linux-observability` | Adds Prometheus/node_exporter metrics, central log shipping and health endpoints. |
| | `linux-system-monitoring` | Takes a read-only host-health snapshot of CPU, memory, I/O, network and backups. |
| **09 Troubleshooting and recovery (2)** | `linux-disaster-recovery` | Recovers databases, files, configuration, boot state or filesystems from a verified backup. |
| | `linux-troubleshooting` | Triages a production incident across resources, services, web, database, TLS and deployments. |
| **10 Automation and scripting (2)** | `linux-bash-scripting` | Writes and reviews portable `sk-*` scripts on the `common.sh` contract, with dry runs and gates. |
| | `linux-repo-sync` | Runs unattended or menu-driven Git updates that preserve local work. |
| **11 Databases and caching (3)** | `linux-inmemory-stores` | Installs, secures, sizes and diagnoses Redis or Memcached. |
| | `linux-mysql-mariadb` | Installs, secures, tunes, backs up and restores MySQL/MariaDB, including binlogs and PITR. |
| | `linux-postgresql` | Installs, authenticates, tunes, backs up and restores PostgreSQL, including WAL and PITR. |
| **12 Containers and orchestration (3)** | `linux-container-deployment` | Runs, updates and supervises containers and Compose/Quadlet stacks under systemd. |
| | `linux-container-engine` | Installs, hardens and diagnoses Docker or Podman engines, including rootless mode. |
| | `linux-image-hygiene` | Measures and reclaims container storage and schedules safe pruning. |
| **13 Backup and archiving (3)** | `linux-archive-integrity` | Creates, signs, encrypts, verifies and restores metadata-preserving tar archives. |
| | `linux-filesystem-snapshots` | Creates, replicates, mounts and rolls back LVM, Btrfs or ZFS snapshots. |
| | `linux-rsync-sync` | Designs, previews, runs and verifies rsync mirrors, offsite copies and hard-linked backups. |
| **14 Performance and kernel (3)** | `linux-kernel-modules` | Inspects, loads, parameterises, persists and blacklists kernel modules. |
| | `linux-perf-profiling` | Gathers read-only evidence of a regression with vmstat, iostat, pidstat, sar and perf. |
| | `linux-sysctl-tuning` | Applies measured, persistent network, writeback, swap and congestion-control sysctls. |
| **15 Compliance and auditing (3)** | `linux-auditd-rules` | Designs, tests, persists and queries auditd rules for forensic attribution. |
| | `linux-benchmark-scanning` | Runs read-only OpenSCAP or Lynis scans and drafts remediation. |
| | `linux-file-integrity` | Establishes, checks and safely updates an AIDE baseline and triages drift. |
| **16 Network equipment (3)** | `cisco-ios-patterns` | Reviews IOS/IOS-XE configuration and plans bounded router or switch changes. |
| | `netmiko-ssh-automation` | Builds bounded, read-only-by-default Netmiko SSH collection for a named inventory. |
| | `network-config-validation` | Preflights device configuration for dangerous commands, overlaps and exposure. |
| **Hub (1)** | `linux-sysadmin` | Routes a server request to the right specialist across every category. |
| **Meta (3)** | `kaizen-improvement-system` | Audits and improves this engine and the server products it produces. |
| | `skill-safety-audit` | Reviews a new or changed skill for unsafe installers, credential capture or policy bypass. |
| | `skill-writing` | Creates or upgrades a skill under the canonical chwezi-dev-engine authoring standard. |
| **Total** | **48** | |

## References

The full list is in [`docs/references.md`](docs/references.md): books (citations only; no book text is stored in this repository), adapted repositories with their licences and commits, tool projects, standards and product documentation.

- **Adapted repositories.** The engine adapts material from Everything Claude Code, `addyosmani/agent-skills` (MIT), `obra/superpowers` (MIT), `DietrichGebert/ponytail` (MIT) and `pbakaus/impeccable` (Apache-2.0). `donvito/codex-astra-luna-orchestrator` is a concept reference only. The `skill-writing` standard comes from the chwezi-dev-engine.
- **Standards.** IETF RFCs for DNS, SMTP submission, TLS, HSTS, ACME, SPF, DKIM and DMARC; CIS Benchmarks and DISA STIG profiles through OpenSCAP; Mozilla's server-side TLS guidance; Red Hat Enterprise Linux 9 and Ubuntu Server documentation.
