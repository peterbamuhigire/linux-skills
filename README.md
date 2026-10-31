# Linux Skills

Linux Skills is an operations engine for administering Linux servers and the network equipment around them. It gives an AI agent (Claude Code, Codex and others) or a person 48 skills that cover a host's working life, from provisioning and hardening to recovery, plus Cisco IOS review. A hub skill, `linux-sysadmin`, routes each request to the narrowest specialist.

Every procedure names its target, preconditions, a bounded change, a rollback route and a verification step. Changes are preview-first and need explicit authority. Evidence that is unavailable is recorded as `NOT ASSESSED`, never assumed.

## At a glance

- **48 skills**: 44 specialists in 16 numbered categories, the `linux-sysadmin` hub and 3 meta skills.
- **Two Linux families**: Debian/Ubuntu and RHEL (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Each Linux specialist carries a `## Distro support` matrix.
- **26 `sk-*` Bash scripts** share one `common.sh` library; 13 are tier 1 and install first.
- **45 skills in the plugin**: the Claude Code and Codex manifests list the same set.
- **Routing**: 109 fixtures. The expected skill ranks first for 96 and in the top three for all 109.
- **Tests**: 119 passed and 9 skipped; the skips are opt-in container labs. All figures are from 31 October 2026.

### Start here

1. **Get the engine and preview the install.** Nothing is copied until you drop `--dry-run`.

   ```sh
   git clone https://github.com/peterbamuhigire/linux-skills
   cd linux-skills
   bash install.sh --scope project --dry-run   # macOS, Linux or Git Bash; drop --dry-run to install
   ```

2. **Check what is installed.** `doctor` prints `(nothing installed)` until you install without `--dry-run`.

   ```sh
   node scripts/install-engine.js doctor --scope project
   ```

3. **Ask for work in plain words.** For example: "Take a read-only host-health snapshot of CPU, memory, I/O, network and process pressure". That request matches `linux-system-monitoring`.

Claude Code users can install the plugin instead, and Windows users have `install.ps1`: see [Install](#install).

## Contents

- **Start:** [At a glance](#at-a-glance), [When to use it](#when-to-use-it), [Find the right skill](#find-the-right-skill), [How it works](#how-it-works), [What is inside](#what-is-inside)
- **Install and check:** [Install](#install), [Updating installed scripts](#updating-installed-scripts), [Codex and manual use](#codex-and-manual-use), [Validation](#validation)
- **Quality:** [Quality and improvement](#quality-and-improvement), [What the October 2026 kaizen improved](#what-the-october-2026-kaizen-improved)
- **Kaizen record:** [Defects fixed](#defects-fixed-in-october-2026), [Checks and tests added](#checks-and-tests-added-in-october-2026), [Procedures, sources and packaging](#procedures-sources-and-packaging-in-october-2026)
- **Open items:** [Open findings](#open-findings-that-matter-to-a-user), [Date-triggered gates](#date-triggered-gates)
- **Sources and people:** [References](#references), [Contributing, author and licence](#contributing-author-and-licence)

## When to use it

Use it when an agent or a person has to administer Linux servers or review Cisco IOS configuration, and the work needs a plan, a bounded change, a rollback route and evidence.

It is written for Linux administrators, infrastructure and network engineers, service owners and support teams, and for AI agents (Claude Code, Codex and others) acting for them. For Windows hosts, use the paired engine `windows-admin-engine-skills`.

It produces:

- server provisioning plans, and cloud-init, autoinstall and Kickstart files;
- Ansible desired-state playbooks;
- hardening work and read-only security assessments;
- firewall, TLS and certificate configurations;
- site release and rollback runbooks;
- database backup, restore and point-in-time recovery procedures;
- container deployment specifications;
- observability and log-shipping configurations;
- incident diagnosis trees and recovery procedures;
- 26 `sk-*` Bash scripts built on a shared `common.sh` contract;
- for network devices, bounded IOS change plans, Netmiko collection scripts and static configuration preflight reports.

Its procedures follow the IETF RFCs for DNS, SMTP submission, TLS, HSTS, ACME, SPF, DKIM and DMARC. Compliance work uses CIS Benchmark and DISA STIG profiles through OpenSCAP and the SCAP Security Guide. TLS work follows Mozilla's server-side TLS guidance.

## Find the right skill

Start at `linux-sysadmin` when unsure. The tasks below are worded after the routing fixtures in `tests/fixtures/routing.json`. The ranker in `scripts/routing_smoke_test.py` puts the listed skill first for each wording.

| Task | Skill |
|---|---|
| Set up a fresh server after first boot: admin user, SSH keys, updates, firewall | `linux-server-provisioning` |
| Write cloud-init user-data for a new VM | `linux-cloud-init` |
| Create or revoke a user, sudo rights or SSH keys | `linux-access-control` |
| Fix a 502 from Nginx or Apache with PHP-FPM | `linux-webstack` |
| Release one site revision with a rollback route | `linux-site-deployment` |
| Allow HTTPS through the firewall, or check a certificate and its renewal | `linux-firewall-ssl` |
| Audit a host's security posture read-only, then fix confirmed findings | `linux-security-analysis`, then `linux-server-hardening` |
| Back up and restore MySQL or MariaDB | `linux-mysql-mariadb` |
| Back up and restore PostgreSQL | `linux-postgresql` |
| Triage a production incident | `linux-troubleshooting` |
| Restore files, a database or boot state from a verified backup | `linux-disaster-recovery` |
| Write or review a portable `sk-*` Bash script | `linux-bash-scripting` |

## How it works

1. **Route.** The hub skill, `linux-sysadmin`, sends the request to the narrowest specialist. Claude Code reads `CLAUDE.md`, which imports `AGENTS.md`. Any other runner loads `AGENTS.md`, then the chosen `SKILL.md`.
2. **Follow the contract.** Each skill opens with `Use when`, `Do not use when`, `Required inputs`, `Workflow`, `Quality standards`, `Anti-patterns`, `Outputs` and `References`. The rest of the skill is the detailed procedure.
3. **Pick the distro path.** Linux specialists carry a `## Distro support` matrix covering the Debian/Ubuntu and RHEL families. Network-appliance specialists declare their vendor scope instead.
4. **Preview, then change.** Mutating work is preview-first and needs explicit authority.
5. **Treat scripts as accelerators.** The `sk-*` scripts share `common.sh` for distro detection and package, firewall and service primitives. The manual commands in each skill remain the baseline.

Skills sit in `NN-category/<skill>/SKILL.md` with optional `references/` and `scripts/` folders. The hub is `linux-sysadmin/`.

## What is inside

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

## Install

### Prerequisites

- Git.
- `diffutils` (`cmp`) for script installation and update. The installer reports missing dependencies before it writes anything.
- Node.js 18 or later for the clone installers and the plugin's destructive-command hook.
- Python 3.11 or later for the validators, tests and the Codex model-policy helper. The validators also need `PyYAML` and the tests need `pytest` (see [Validation](#validation)).
- Bash 4 on target servers for the `sk-*` scripts.

### Claude Code plugin (recommended)

The repository is its own marketplace (`.claude-plugin/marketplace.json`, marketplace `chwezi-linux`, plugin `linux`, version 1.1.0):

```text
/plugin marketplace add https://github.com/peterbamuhigire/linux-skills
/plugin install linux@chwezi-linux
```

### Clone installer

`install.sh` and `install.ps1` delegate to `scripts/install-engine.js`. The scope is `user` (`~/.claude`, the default) or `project` (`.claude` under the current directory). Add `--dry-run` to preview. The [Start here](#start-here) steps preview a project-scope install.

Run `install.sh` through `bash`. The file is committed without the executable bit (mode 100644), so `./install.sh` stops with "Permission denied" (exit 126). On Windows, run the PowerShell form instead:

```powershell
.\install.ps1 --scope project               # Windows PowerShell
```

On 31 October 2026, `bash install.sh --scope project --dry-run` on Linux listed the files it would copy into `.claude` under the current directory and wrote nothing. `doctor` then reported "nothing installed".

`install.ps1` was not run: the machine used had no PowerShell, so that path is `NOT_ASSESSED`.

### Server toolkit

On a managed Debian/Ubuntu or RHEL-family host, install the tier-1 `sk-*` scripts to `/usr/local/bin` and `common.sh` to `/usr/local/lib/linux-skills/`. Tier 1 is 13 scripts. Other skills' scripts install on first use (`sudo scripts/install-skills-bin <skill-name>`).

The installer needs root even with `--dry-run`. `--list` does not. It shows each script's skill, whether it is tier 1 and whether it is installed.

```sh
scripts/install-skills-bin --list
sudo scripts/install-skills-bin --dry-run core
sudo scripts/install-skills-bin core
```

`scripts/setup-claude-code.sh` is an optional, gated Claude Code bootstrap for a server. Review its `--dry-run` plan first. It needs explicit target, authority and recovery-file flags.

## Updating installed scripts

Installed copies do not follow the checkout. After updating the repository, compare the installed library and any script you rely on with the repository copy, then reinstall:

```sh
diff /usr/local/lib/linux-skills/common.sh scripts/lib/common.sh
sudo scripts/install-skills-bin core --force      # tier 1; use <skill-name> for another skill's scripts
```

- `--list` prints `yes` under INSTALLED? even when the installed file differs from the repository copy, so use `diff` or `cmp`.
- Without `--force` the installer refuses to replace a differing script.
- Read the diff first. The [pass 2](docs/updates/2026-10-31-kaizen-pass-2.md) and [lab wave](docs/kaizen/2026-10-linux-lab-wave/operator-note.md) operator notes list which scripts changed.

## Codex and manual use

- **Codex.** The `.codex-plugin/plugin.json` compatibility manifest exposes the same 45 operational skills as Claude without copying skill content. See [marketplace packaging and checks](docs/marketplace.md) for verified support and public-upload limitations.
- **Checked.** Both the engine package and this checkout are checked against a hard 5,000-file ceiling. [Native offline tests](docs/kaizen/2026-10-engine-kaizen/portfolio-refresh.md) confirm installation in both CLIs and all 45 declared skills visible in Codex.
- **Model policy.** Before substantive Codex work, check the policy with `python3 .codex/ensure_model_policy.py --runtime codex --check`. Claude skips this step.
- **Manual use.** No installer is needed. Clone the repository anywhere. Read `CLAUDE.md` (Claude Code) or `AGENTS.md` (any runner), then load `linux-sysadmin/SKILL.md` as the default route. Validate changes as described under [Validation](#validation).

## Validation

Run from the repository root. The commands use `python3`.

CI runs the same forms on Ubuntu 24.04 with Python 3.12 ([`skill-quality.yml`](.github/workflows/skill-quality.yml), [`bash-suites.yml`](.github/workflows/bash-suites.yml), [`source-ingestion-guardrail.yml`](.github/workflows/source-ingestion-guardrail.yml)).

### Dependencies

- Python 3.11 or later. `PyYAML` is imported by the skill validator, the routing test, the hygiene metrics and the quick validator. `pytest` runs the test suite. The repository has no requirements file.
- Install both into a virtual environment (`python3 -m venv "$VENV" && "$VENV/bin/pip" install PyYAML pytest`) and run the commands below with `"$VENV/bin/python"`. A system Python without `pytest` fails `python3 -m pytest` with "No module named pytest".
- To keep a run from writing into the checkout, set `PYTHONDONTWRITEBYTECODE=1` and add `-p no:cacheprovider` to pytest.
- Node.js 18 or later for the manifest generator and the hook tests. Bash for the shell suites.
- The figures below are from 31 October 2026 on Python 3.14.8, Node.js 22 and `pytest` 9.0.3, on `main`.

### Registered checks

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
| Hygiene gate (date-triggered) | `python3 scripts/kaizen_metrics.py --baseline docs/kaizen/2026-10-engine-kaizen-pass-2/metrics-final.json --output "$OUT" --quiet` | Exit 0, no output. Fails from 2026-12-01 ([gates](#date-triggered-gates)). Without `--output --quiet` it prints the JSON report |
| Plugin hook tests | `node hooks/test-destructive-bash-gate.js` and `node hooks/test-plugin-hook-config.js` | 61/61 and 7/7 passed |
| Canonical engine scanner | `python3 -X utf8 <chwezi-dev-engine checkout>/skills/sdlc-meta/skill-engine-audit/scripts/engine_compliance.py --root . --active-root . --details` | 48 skills, 48 fully compliant, 0 safe fixes applied |
| Skill quick validator | `python3 -X utf8 meta/skill-writing/scripts/quick_validate.py <skill-directory>` | `linux-sysadmin`: "Skill is valid." |
| Whitespace | `git diff --check` | No output |

The canonical engine scanner needs the engineering-catalogue checkout. On some machines its folder is still named `skills-web-dev`.

### Checks that need more than Python and Node

- **Root, in a disposable machine.** `sudo bash scripts/tests/install-skills-bin.test.sh` is run by CI under `sudo` in a disposable job and again in a Fedora 44 container.
  - The installer refuses to run unprivileged ("must run as root"). Run without root on 31 October 2026, the suite gave 11 passed and 10 failed, and the failures followed from that refusal.
  - So this check is `NOT_ASSESSED` on a workstation. Run it only as root inside a disposable container or VM.
- **Container labs (opt-in).** Two commands:
  - `LINUX_SKILLS_LAB=1 python3 -m pytest -rP tests/test_distro_labs.py` runs 7 tests in Debian 12 and Fedora 44 containers.
  - `LINUX_SKILLS_MYSQL_BACKUP_LAB=1 LINUX_SKILLS_LAB_PREFIX=lskw- python3 -m pytest tests/test_mysql_backup.py` runs 2 tests against MySQL 8.4.
- **Container lab requirements.** Rootless Podman, with these images already present locally: `docker.io/library/debian:bookworm`, `quay.io/fedora/fedora:44`, `docker.io/library/mysql:8.4` and `docker.io/rclone/rclone`. The labs never pull an image or publish a port.
  - The Debian and Fedora labs copy the repository into their containers and mount no host path. Those containers install packages from the distribution mirrors, so they need outbound network access from the container.
  - The MySQL labs mount the repository read-only and one temporary directory read-write, and use an internal Podman network.
  - Lab wave results: 7 passed in 201 s and 2 passed in 70 s ([validation record](docs/kaizen/2026-10-linux-lab-wave/04-validation-record.md)). They were not re-run on 31 October 2026, because no containers were used then.
  - After a run, `podman ps --all --format '{{.Names}}' | grep '^lskw-'` must print nothing.
- **ShellCheck.** CI does not run it. It runs inside the lab containers (`test_shellcheck_reports_no_warnings`, ShellCheck 0.9.0 on Debian 12 and 0.11.0 on Fedora 44): `shellcheck -x --severity=warning` over 41 shell sources.
  - The lab wave measured 0 findings.
  - Before it there were 28 warnings. The wave judged them to be false positives and annotated them inline with `# shellcheck disable=` directives and a reason.
- **PowerShell.** `install.ps1` needs `pwsh` or Windows PowerShell. It has not been run.
- **Not needed.** No check renders a document, so Pandoc, Mermaid, a browser and LibreOffice are not required.

## Quality and improvement

Three kaizen cycles ran in October 2026. Each evidence folder under `docs/kaizen/` holds the numbered files 00 to 06 (scope and evidence, baseline scorecard, backlog, experiment log, validation record, final report, next cycle) and the raw samples behind them.

[`docs/README.md`](docs/README.md) indexes the rest of `docs/`.

| Cycle | Evidence folder | Read first |
|---|---|---|
| 29 October 2026, first cycle | [`docs/kaizen/2026-10-engine-kaizen/`](docs/kaizen/2026-10-engine-kaizen/) | [Final report](docs/kaizen/2026-10-engine-kaizen/05-final-report.md) |
| 31 October 2026, pass 2 | [`docs/kaizen/2026-10-engine-kaizen-pass-2/`](docs/kaizen/2026-10-engine-kaizen-pass-2/) | [Final report](docs/kaizen/2026-10-engine-kaizen-pass-2/05-final-report.md), [operator note](docs/updates/2026-10-31-kaizen-pass-2.md) |
| 31 October 2026, Linux lab wave (rootless Podman labs) | [`docs/kaizen/2026-10-linux-lab-wave/`](docs/kaizen/2026-10-linux-lab-wave/) | [Final report](docs/kaizen/2026-10-linux-lab-wave/05-final-report.md), [operator note](docs/kaizen/2026-10-linux-lab-wave/operator-note.md) |

**Latest published score** (lab wave final report):

- Ten equally weighted dimensions: raw mean **77.9**; published score `min(raw, 65)` = **65.0**.
- The raw mean moved 50.5 (first-cycle baseline), 74.0 (first-cycle final), 75.6 (pass 2 final) and 77.9 (lab wave final).
- The 95/100 raw target is not met. The raw mean is 17.1 points short, and the 65 cap is a reporting ceiling that does not close that gap.
- The first-cycle report also records a stricter 45/100 ceiling requested for that cycle.
- Scores are reviewer judgements against named evidence, not a percentage of anything.

Next: [what improved](#what-the-october-2026-kaizen-improved), [open findings](#open-findings-that-matter-to-a-user) and [date-triggered gates](#date-triggered-gates).

## What the October 2026 kaizen improved

The three cycles kept every experiment they ran; none was reverted.

Experiment logs: [29 October](docs/kaizen/2026-10-engine-kaizen/03-experiment-log.md), [pass 2](docs/kaizen/2026-10-engine-kaizen-pass-2/03-experiment-log.md) and the [lab wave](docs/kaizen/2026-10-linux-lab-wave/03-experiment-log.md).

The three lists after the figures hold kept changes only: [defects](#defects-fixed-in-october-2026) first, then [checks and tests](#checks-and-tests-added-in-october-2026), then [procedures, sources and packaging](#procedures-sources-and-packaging-in-october-2026).

- Each hash is an ancestor of `main` (`git merge-base --is-ancestor`).
- "Lab" means a throwaway rootless Podman container, not a production host.
- Figures marked "re-measured" were run on 31 October 2026. The rest come from the evidence file named.

### Figures across the three cycles

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
| ShellCheck warnings | not recorded | not recorded | 28 | 0 | Lab wave validation record; not re-measured (no ShellCheck or container available) |
| Opt-in container lab tests | not recorded | 1 | 1 | 9 | Validation records; 9 re-measured as the default run's skips |

- The raw mean is a reviewer judgement against named evidence. No command re-measures it.
- The pass 2 column of the full-suite row is the lab wave's baseline, which is the pass 2 end state.

## Defects fixed in October 2026

1. **Debian automatic security updates matched no security archive (critical).** `92bafbd`
   - Problem: the provisioning, hardening and package-management procedures gave Debian the Ubuntu pattern `"${distro_id}:${distro_codename}-security"`. On Debian 12 the dry run printed "No packages found that can be upgraded unattended" with a security update pending.
   - Fix: the Debian form is now an `Origins-Pattern` with `#clear` and `label=Debian-Security`. The Ubuntu form is kept and marked not run.
   - Verified in a Debian 12 lab: the dry run lists the pending upgrade (1 passed in 124 s), and the same driver fails 4 checks against the old text. Ubuntu is `NOT_ASSESSED`.
2. **The SSH hardening drop-in lost to cloud-init (critical).** `6f30e09`
   - Problem: OpenSSH keeps the first value it reads, so `99-hardening.conf` lost to a cloud image's `50-cloud-init.conf` and left `PasswordAuthentication yes`.
   - Fix: the drop-in is now `00-linux-skills-ssh.conf` in five procedures, with the precedence rule stated.
   - Verified with `sshd -T` on a fixture (3 of 6 new tests failed before, 6 of 6 pass). In the lab wave, real `sshd` on Debian 12 and Fedora 44 gave: password login refused, key login works, the old name loses. A real cloud image is `NOT_ASSESSED`; the lab imitates `50-cloud-init.conf`.
3. **`sk-pg-backup` wrote world-readable role password hashes and could publish a partial dump (critical).** `cae7544`
   - Problem: output was directory 755 and files 644.
   - Fix: it now stages privately (0700, 0600), checks each dump with `pg_restore --list` before renaming it into place, and prunes only its own files.
   - Verified with stubs (10 of 11 new cases failed against the old script, 11 of 11 pass) and on real PostgreSQL 15.19 and 18.6 in labs, including seven controlled failures that publish nothing.
   - Still open: dumps are not encrypted, and files written by earlier versions keep their old modes until an operator tightens them.
4. **Temporary cleanup and atomic writes trusted filenames (critical).** `c1a3385`
   - Fix: a private temporary registry and trusted-parent checks replace that trust. Atomic write rejects symlinks and keeps mode and owner with checked operations.
   - Verified: an independent review found a writable-ancestor gap in the first attempt. It was repaired and the suites rerun. The `common.sh` suite had 29 cases then (45, re-measured).
   - Still open: ACL, xattr and SELinux metadata preservation remain unassessed.
5. **A failed GPG step left readable plaintext MySQL backups (critical).** `c47b4ae`
   - Problem: a lab reproduced mode 0644 plaintext.
   - Fix: backups now stage privately, clean up on failure and prune with validated retention. A restore procedure was run.
   - Verified on `mysql:8.4` with synthetic data: mode 0600, a repeated backup, a clean restore into a second instance, and injected GPG and retention failures. Production-size data is not assessed.
6. **`systemctl reload ssh` does not exist on the RHEL family (major).** `dad557e`
   - Problem: the apply and rollback blocks failed on Fedora 44 with `Unit ssh.service not found` (exit 5).
   - Fix: they now name `sshd` (an alias on Debian 12), both distro matrices carry an SSH unit row, and every reload after an edit follows `sshd -t &&`. In the lab, a bad drop-in followed by a plain reload stopped the daemon on Fedora.
   - Verified by running the blocks as written: 5 lab tests passed in 217 s, and 8 static tests pass. Enterprise RHEL is `NOT_ASSESSED`.
7. **Root-run scripts trusted configuration files and a predictable `/tmp` path (major).** `ec2a269`, `054c45c`
   - Problem: the backup scripts sourced `/etc/linux-skills/*.conf` unchecked, and the non-root audit fallback wrote to `/tmp/linux-skills-<user>` (mode 755, log 644).
   - Fix: `sk_source_trusted_config` now refuses a symlink, or a file or directory not owned by root or the caller or writable by group or others (exit 3). The fallback uses a validated 0700 directory.
   - Verified by new `common.sh` cases that failed before: 29 to 39 to 42 passed across the two commits.
8. **`sk-audit` inferred health from grep and defaults (major).** `4dcaba2`
   - Fix: it now reads effective `sshd -T` values, matches the firewall exactly and labels cached update results, with explicit unknown states.
   - Verified by eight fixture cases (`tests/test_audit_ssh.py`, part of the 119 passed).
9. **The installer hid a missing `cmp`.** `a4e6f7f`
   - Fix: a dependency check now stops it before any write. A minimal Fedora image had failed idempotence.
   - Verified: 21 installer cases passed in each family container in the 29 October record. They need root, so they were not re-run here.
10. **Smaller defects.** `a31dc52`, `85a96dd`, `9ce3518`
    - Every `die` printed a banner reading `exited N at line 1` and `last command: exit "$code"` in all 26 scripts. It now reports only its own cause (`common.sh` suite 42 to 45, re-measured).
    - `sk-pg-backup` made the Debian client wrapper print `could not change directory to "/root"` on each call. Client calls now run from `/`, and the usage text no longer says a failed run leaves nothing (it can leave a globals file).
    - `journalctl -u dnf-automatic` printed no entries on dnf5. The guidance is split by dnf generation and holds on Fedora 44 (dnf5 5.4.6.0).

## Checks and tests added in October 2026

11. **Container labs for the engine's own procedures and scripts.** `2293b73`, `cf670be`
    - Problem: the lab steps were prose, and nothing in the repository could re-run them.
    - Fix: `tests/test_distro_labs.py` (opt-in) runs documented fenced blocks verbatim in Debian 12 and Fedora 44 containers. They cover the SSH drop-in, `sk-pg-backup`, the PostgreSQL "Verify a logical backup" procedure (written in pass 2 as untested, `62f2e56`) and Debian automatic updates.
    - Verified: the restore ran in about 0.3 s with eleven reconciliation figures equal; 7 tests passed in 201 s.
12. **The least-privilege MySQL backup account, verified.** `fe5f9f9`
    - Problem: pass 2 specified the `CREATE USER` and `GRANT` lines from the manual and never ran them (`d42cd1f`).
    - Verified on `mysql:8.4`: they back up every schema, restore with rows, triggers, routines, events and views reconciled, and refuse eight write attempts. 2 tests passed in 70 s.
    - Correction: the page was wrong that `PROCESS` is required. Without it, `mysqldump` 8.4.13 exits 0 with an access-denied line about tablespaces and omits general-tablespace statements.
13. **ShellCheck as a zero-warning gate.** `4dabff3`
    - Problem: it had been run once by hand. ShellCheck 0.9.0 and 0.11.0 reported 28 warnings (exit 1).
    - Fix: the lab test `test_shellcheck_reports_no_warnings` now passes with 0 over 41 shell sources in both containers. The intended findings are annotated inline (29 `# shellcheck disable=` lines).
    - Limit: it runs inside the labs, not in CI.
14. **Stronger distro checks.** `4518733`, `ae84c01`
    - Problem: the matrix check proved a section existed, not that it was right.
    - Fix: it now rejects boilerplate and empty catalogues (ten adversarial cases). `tests/test_distro_parity.py` fails when a procedure names a Debian-only service unit that its matrix never pairs.
    - Verified: 8 unpaired uses in 7 skills became 0, with five negative fixtures. `check-distro-matrix.sh` passes 41 of 41 (re-measured).
15. **Routing measured, and fixtures where skills were touched.** `6e75a2f`, `221871c`, `16e45f2`
    - Problem: passing the top three had been mistaken for coverage.
    - Fix: P@1 and owned-negative checks were added, with fixtures for the skills each cycle edited.
    - Re-measured on 31 October 2026: 109 fixtures, P@1 96/109, P@3 109/109, and 17 of 48 skills at 3 positives and 2 owned negatives. 31 skills still lack that coverage. The lexical ranker's artefacts are recorded, not tuned.
16. **CI gates.** `923342b`, `f904f7b`, `199265f`, `af0e9e0`
    - Problem: tests had run outside required CI.
    - Fix: CI now runs the Python suite with pinned action revisions and limited permissions, plus a Fedora 44 fixture job.
    - Fix: a hygiene step fails on new link, anchor, heading or expired-source debt against the pass-2 baseline. `kaizen_metrics.py` gained `--quiet`, and an unavailable Fedora image pin was refreshed.
    - Limit: hosted CI last ran on `f904f7b`; all three workflows succeeded on 29 October. The pass 2 and lab wave commits had not been pushed, so it has not run on them.

## Procedures, sources and packaging in October 2026

17. **A PHP 502 procedure that observes before it acts.** `4e28dae`
    - Problem: a short example restarted PHP-FPM without identifying the failing upstream.
    - Fix: `php-upgrade-502.md` and `tests/labs/web_502.sh` now cover diagnosis, repair, a repeat, rejection of an invalid configuration and an upstream rollback.
    - Verified on Debian and Fedora on 29 October with a synthetic 502; no real firewall or ACME change.
18. **Source and link debt repaid.** `bdda0a2`, `1ef490f`, `fc0c8af`
    - Ten expired source rows were re-opened at their primary sources (8 verified, 2 partial).
    - The dangling local paths (5), dangling anchors (10) and skills with duplicate headings (10) were repaired. All four measures read 0 now (re-measured).
    - The 29 October refresh also added a dated register that separates candidate exposure from installed-host vulnerability. Ten source rows carry a review-by date of 2026-11-30 (see [Date-triggered gates](#date-triggered-gates)).
19. **Claude and Codex packages from one set of skill folders.** `93122fb`, `57bd07d`, `041c738`
    - Both manifests list the same 45 skills (re-measured). `scripts/check_marketplace.py` checks parity, paths and a 5,000-file ceiling (a limit set above 5,000 is rejected).
    - Native offline discovery was recorded for Claude 2.1.312 and Codex 0.165.0. Live client loading and public listing are `NOT_ASSESSED`.

## Open findings that matter to a user

- **Installed copies of the `sk-*` scripts can be older than this checkout.** `scripts/install-skills-bin --list` prints `yes` under INSTALLED? even when the installed file differs. See [Updating installed scripts](#updating-installed-scripts).
- **Hosts set up from the earlier procedures need two read-only checks.** The [lab wave operator note](docs/kaizen/2026-10-linux-lab-wave/operator-note.md) has the commands.
  - A Debian host configured from the older "Unattended security upgrades" text may not be patching itself.
  - `systemctl reload ssh` does not exist on the RHEL family.
- **Not tested.** The labs ran Debian 12, Fedora 44 and MySQL 8.4 in rootless Podman containers.
  - These are `NOT_ASSESSED`: Ubuntu 22.04 and 24.04, enterprise RHEL and its rebuilds, Debian 13, a real cloud image with cloud-init, enforcing SELinux, firewalld, UFW and nftables, and ACME issuance.
  - 22 of the 26 `sk-*` scripts have not been run in any lab ([lab wave final report](docs/kaizen/2026-10-linux-lab-wave/05-final-report.md#residual-risk-and-scope)).
- **Known behaviours of the backup scripts.** The [lab wave next-cycle file](docs/kaizen/2026-10-linux-lab-wave/06-next-cycle.md) has the details and the open decisions.
  - `sk-mysql-backup` against MySQL 8.4 without the `PROCESS` privilege exits 0, but prints an access-denied line about tablespaces and leaves out general-tablespace statements.
  - `sk-pg-backup` writes the globals file first, so a run that fails on a later database leaves globals and no dumps.
  - `sk-capture` may fail to write its default output under `tcpdump`'s privilege drop (unverified).

To assess packages, use the [current vulnerability triage runbook](docs/security/current-vulnerability-triage.md) and its dated source register. The watchlist is a review queue, not proof that a host is vulnerable or fully patched.

The [platform evidence](docs/continuous-improvement/platform-test-matrix-2026-08.md) distinguishes disposable tests from live service, recovery and production evidence.

## Date-triggered gates

Only the 2026-12-01 gate is enforced by a validator. The other dates are review dates written in the evidence; they are not scheduled automation.

| Date | What happens | Enforced |
|---|---|---|
| 2026-11-07 | Re-audit date set by the [lab wave next-cycle file](docs/kaizen/2026-10-linux-lab-wave/06-next-cycle.md) | No |
| 2026-11-12 | PostgreSQL 14 reaches its final release. The provisioning steps still expect "PostgreSQL 14.x (22.04)" ([currency record](docs/kaizen/2026-10-engine-kaizen-pass-2/currency.md)) | No |
| 2026-11-16, 2026-11-30, 2026-12-15 | Review-by dates in the [pass-2 currency record](docs/kaizen/2026-10-engine-kaizen-pass-2/currency.md): the PostgreSQL row, most other rows, and the PHP, MySQL 8.0 and Let's Encrypt rows | No |
| 2026-12-01 (first failing day) | The CI step "Check bounded hygiene regressions" fails (see below) | Yes |
| 2026-12-28 | Next full model-policy evaluation ([model review](docs/continuous-improvement/model-review-2026-10-29.md)) | No |
| 2026-12-31 | PHP 8.2 reaches end of life and PHP 8.4 leaves active support (currency record, row P2-C05) | No |

- **2026-12-01.** Ten source rows (`LSR01` to `LSR10` in [`P03-linux-web-service-preservation.md`](docs/continuous-improvement/skills-kaizen/P03-linux-web-service-preservation.md)) carry a review-by date of 2026-11-30.
  - Re-verify the sources and move the dates, as pass 2 did for ten earlier rows.
  - Do not weaken the gate.
- **How it was checked.** Run 31 October 2026: `kaizen_metrics.py --baseline docs/kaizen/2026-10-engine-kaizen-pass-2/metrics-final.json --as-of 2026-11-30` exits 0. With `--as-of 2026-12-01` it exits 1 with `expired_source_records: 10`.
- **Currency IDs.** The pass-2 currency rows are `P2-C01` to `P2-C11`. `kaizen_metrics.py` does not read them. It lists ten records, all in the file named above.

## References

The full list is in [`docs/references.md`](docs/references.md): books (citations only; no book text is stored in this repository), adapted repositories with their licences and commits, tool projects, standards and product documentation.

- **Adapted repositories.** The engine adapts material from Everything Claude Code, `addyosmani/agent-skills` (MIT), `obra/superpowers` (MIT), `DietrichGebert/ponytail` (MIT) and `pbakaus/impeccable` (Apache-2.0).
- **Concept reference.** `donvito/codex-astra-luna-orchestrator`. The `skill-writing` standard comes from the chwezi-dev-engine.
- **Standards.** IETF RFCs for DNS, SMTP submission, TLS, HSTS, ACME, SPF, DKIM and DMARC; CIS Benchmarks and DISA STIG profiles through OpenSCAP; Mozilla's server-side TLS guidance; Red Hat Enterprise Linux 9 and Ubuntu Server documentation.

## Contributing, author and licence

- **Contributing.** Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the [skill authoring standard](docs/engine-design/skill-authoring-standard.md). Run the checks under [Validation](#validation) after any change to a skill, script or route.
- **Licence.** MIT; see [`LICENSE`](LICENSE).
- **Author.** Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256784464178.
