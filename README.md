# Linux Skills

Linux Skills is an operations engine for administering Linux servers and the network equipment around them. Its 48 skills cover the working life of a host: provisioning and first boot, users and secrets, networking and DNS, web and mail services, systemd and virtualisation, storage, hardening, intrusion detection, observability, troubleshooting and disaster recovery, Bash automation, databases and caches, containers, backup and archiving, performance and kernel tuning, compliance auditing, and Cisco IOS/IOS-XE configuration review. A hub skill, `linux-sysadmin`, routes each request to the narrowest specialist. Every specialist carries a `## Distro support` matrix covering both the Debian/Ubuntu and RHEL families (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Every procedure declares its target, preconditions, a bounded change, a rollback route and a verification step. Mutating work is preview-first and needs explicit authority; evidence that is unavailable is recorded as `NOT ASSESSED`, never assumed.

The engine produces server provisioning plans and cloud-init, autoinstall and Kickstart files; Ansible desired-state playbooks; hardening and read-only security assessments; firewall, TLS and certificate configurations; site release and rollback runbooks; database backup, restore and point-in-time recovery procedures; container deployment specifications; observability and log-shipping configurations; incident diagnosis trees; recovery procedures; and 26 `sk-*` Bash scripts built on a shared `common.sh` contract. For network devices it produces bounded IOS change plans, Netmiko collection scripts and static configuration preflight reports. Its procedures follow the IETF RFCs for DNS, SMTP submission, TLS, HSTS, ACME, SPF, DKIM and DMARC. Compliance work uses CIS Benchmark and DISA STIG profiles through OpenSCAP and the SCAP Security Guide, and TLS work follows Mozilla's server-side TLS guidance. It is written for Linux administrators, infrastructure and network engineers, service owners and support teams, and for AI agents (Claude Code, Codex and others) acting on their behalf.

## Installation

**Prerequisites.** Git. Node.js 18 or later for the clone installers and the plugin's destructive-command hook. Python 3.11 or later for the validators, tests and the Codex model-policy helper. Bash 4 on target servers for the `sk-*` scripts.

**Claude Code plugin (recommended).** The repository is its own marketplace (`.claude-plugin/marketplace.json`, marketplace `chwezi-linux`, plugin `linux`, version 1.1.0):

```text
/plugin marketplace add https://github.com/peterbamuhigire/linux-skills
/plugin install linux@chwezi-linux
```

**Clone installer.** `install.sh` and `install.ps1` delegate to `scripts/install-engine.js`. Scope is `user` (`~/.claude`, the default) or `project` (`.claude` under the current directory). Add `--dry-run` to preview.

```sh
git clone https://github.com/peterbamuhigire/linux-skills
cd linux-skills
./install.sh --scope project        # macOS, Linux or Git Bash
.\install.ps1 --scope project       # Windows PowerShell
node scripts/install-engine.js doctor --scope project
```

**Server toolkit.** On a managed Debian/Ubuntu or RHEL-family host, install the tier-1 `sk-*` scripts to `/usr/local/bin` and `common.sh` to `/usr/local/lib/linux-skills/`. Other skills' scripts install on first use (`sudo scripts/install-skills-bin <skill-name>`).

```sh
sudo scripts/install-skills-bin --dry-run core
sudo scripts/install-skills-bin core
```

`scripts/setup-claude-code.sh` is an optional, gated Claude Code bootstrap for a server. Review its `--dry-run` plan first. It needs explicit target, authority and recovery-file flags.

**Codex.** No installer is needed. Load `AGENTS.md`, then the selected `SKILL.md`. Before substantive work, check the Codex model policy with `python .codex/ensure_model_policy.py --runtime codex --check`. Claude skips this step.

**Manual use.** Clone the repository anywhere. Read `CLAUDE.md` (Claude Code) or `AGENTS.md` (any runner), then load `linux-sysadmin/SKILL.md` as the default route. Validate changes with `python -X utf8 scripts/validate_skills.py` and `python -X utf8 -m pytest tests`.

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
| | `linux-webstack` | Installs, tunes and diagnoses the shared Nginx, Apache/httpd, PHP-FPM and Node.js stack. |
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

Citations only. No book text is stored in this repository (see `AGENTS.md`, "Never store book extractions").

### Books

Cited as grounding in skill references:

- Atef, G. (2023) *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite*.
- Blum, R. and Bresnahan, C. *Linux Command Line and Shell Scripting Bible*, 5th edn. Wiley.
- Canonical. *Ubuntu Server Guide Documentation (Linux 20.04 LTS, Focal)*.
- Duguin, S. *Cybersecurity for NGOs: Attack Prevention and Threat Response*.
- Gotangco, J. *Red Hat Enterprise Linux 9 for System Administrators*.
- Gregg, B. *Systems Performance: Enterprise and the Cloud*, 2nd edn; and *BPF Performance Tools*.
- Hitchcock, K. (2022) *Linux System Administration for the 2020s: The Modern Sysadmin Leaving Behind the Culture of Build and Maintain*. Apress.
- Johnson, R. *Fedora Linux Essentials Definitive Reference*.
- Kalsi, T. *Practical Linux Security Cookbook*. Packt.
- Kerrisk, M. *The Linux Programming Interface*.
- Kirch, O. and Dawson, T. (2000) *Linux Network Administrator's Guide*, 2nd edn. O'Reilly.
- Taylor, D. and Perry, B. *Wicked Cool Shell Scripts*. No Starch Press.
- Tevault, D. A. *Mastering Linux Security and Hardening*, 3rd edn. Packt.
- van Vugt, S. *Red Hat RHCSA 8 Cert Guide (EX200)*, 2nd edn.
- Vickler. *Linux Command Lines and Shell Scripting*.
- *Beginner's Guide to the Unix Terminal* (the repository gives no author).
- *Pro Bash* (the repository gives no author).
- *RHEL 9 Recipes*, recipes 37 and 39 (the repository gives no author).

Named in planning documents (`docs/engine-upgrade-july-2026/05-reading-list.md`, `docs/evaluation/2026-04-13/suggested-reading.md`) and "deepen with" notes for further grounding:

- Beyer, B. et al. *Site Reliability Engineering*; and *The Site Reliability Workbook*.
- *Accelerate* (the repository gives the title only).
- Gregg, B. *Linux Performance*.
- Hertzog and Mas. *The Debian Administrator's Handbook*.
- Limoncelli, T. et al. *The Practice of System and Network Administration*.
- Nemeth, E., Snyder, Hein, Whaley and Mackin. *UNIX and Linux System Administration Handbook*, 5th edn.
- Rankin, K. *Linux Hardening in Hostile Networks*.
- Riggs and Ciolli. *PostgreSQL 16 Administration Cookbook*. Packt.
- Schwartz, B. et al. *High Performance MySQL*, 4th edn. O'Reilly.
- Ward, B. *How Linux Works*, 3rd edn.
- *Redis in Action*.
- *Terraform: Up & Running*.

### Repositories

Adapted into the engine:

- Everything Claude Code (ECC): https://github.com/affaan-m/ECC. The three `16-network-equipment` skills were adapted from ECC's `cisco-ios-patterns`, `netmiko-ssh-automation` and `network-config-validation` (imported 2026-09-20). The Pi-hole and VLAN references were adapted from `homelab-pihole-dns` and `homelab-vlan-segmentation`, and the OSI-layer network diagnostic workflow in `linux-troubleshooting` from `agents/network-troubleshooter.md`, and the Freeze Mode rule in `rules/common/core.md` from `skills/safety-guard/SKILL.md`. The installer's Git Bash path fix follows ECC's `install.sh`. `docs/agent-runtime-safety.md` draws on ECC's shortform, longform and security guides.
- addyosmani/agent-skills: https://github.com/addyosmani/agent-skills (MIT, commit `2686b62`). Four tier-1 lint rules in `meta/skill-writing/scripts/quick_validate.py` were paraphrased from `scripts/lib/skill-lint.js` (my-10-kaizen M10-03).
- obra/superpowers: https://github.com/obra/superpowers (MIT, commit `8ca22db`). The narrated-description check (SP-14) in `quick_validate.py` and the canonical `skill-writing` standard with a drift check (SP-04, M10-03/M10-04). The `docs/superpowers/` plans use its planning format.
- DietrichGebert/ponytail: https://github.com/DietrichGebert/ponytail (MIT). This is the thin `CLAUDE.md` → `@AGENTS.md` host-file bridge and single-source drift check (PT-01, PT-02, M10-02, commit `42b3c1b`).
- pbakaus/impeccable: https://github.com/pbakaus/impeccable (Apache-2.0). The `PROJECT.md` (`project_schema: 1`) read rule (IM-11, M10-12, commit `30ac859`) and the "Impeccable-derived AS overlay" quality gate in `AGENTS.md`.
- donvito/codex-astra-luna-orchestrator: https://github.com/donvito/codex-astra-luna-orchestrator. A concept reference for the `.codex/` model-policy helper (inspected at commit `21f4561`; implemented independently).
- chwezi-dev-engine `skill-writing` standard: https://github.com/peterbamuhigire/chwezi-dev-engine/blob/main/skills/sdlc-meta/skill-writing/SKILL.md.

Tool projects documented by the skills:

- age: https://github.com/FiloSottile/age, and age-plugin-yubikey: https://github.com/str4d/age-plugin-yubikey
- Ansible `community.sops`: https://github.com/ansible-collections/community.sops
- audit documentation: https://github.com/linux-audit/audit-documentation
- ComplianceAsCode (SCAP Security Guide): https://github.com/ComplianceAsCode/content
- detect-secrets: https://github.com/Yelp/detect-secrets
- fail2ban wiki: https://github.com/fail2ban/fail2ban/wiki
- FlameGraph: https://github.com/brendangregg/FlameGraph
- git-filter-repo: https://github.com/newren/git-filter-repo
- gitleaks: https://github.com/gitleaks/gitleaks
- LXD configuration: https://github.com/lxc/lxd/blob/master/doc/configuration.md
- Mozilla SSL Configuration Generator: https://github.com/mozilla/ssl-config-generator
- node_exporter: https://github.com/prometheus/node_exporter
- sops: https://github.com/getsops/sops
- testssl.sh: https://github.com/drwetter/testssl.sh
- TruffleHog: https://github.com/trufflesecurity/trufflehog

### Standards and official sources

- IETF RFCs: 1035 (DNS), 1323 (TCP extensions), 1337 (TIME-WAIT hazards), 1918 (private addressing), 1995 (IXFR), 1996 (DNS NOTIFY), 2308 (negative caching), 2317 (classless reverse delegation), 5246 (TLS 1.2), 5280 (X.509 PKI), 6376 (DKIM), 6409 (message submission), 6797 (HSTS), 6962 (Certificate Transparency), 7208 (SPF), 7469 (HPKP, deprecated), 7489 (DMARC), 8314 (implicit TLS for mail), 8375 (`home.arpa`), 8446 (TLS 1.3), 8555 (ACME), 8617 (ARC), 8659 (CAA), 8996 (deprecating TLS 1.0/1.1).
- CIS Benchmarks (Ubuntu/Debian and RHEL), DISA STIG and PCI-DSS profiles as delivered through OpenSCAP and the SCAP Security Guide: https://www.open-scap.org/
- Red Hat Enterprise Linux 9 documentation, including *Deploying web servers and reverse proxies*: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/
- Red Hat Enterprise Linux Security Hardening Guide (reading list).
- NIST incident-response and recovery guidance (named in `docs/evaluation/2026-04-13/suggested-reading.md` without a document number).
- Ubuntu Server documentation: https://ubuntu.com/server/docs
- Linux kernel documentation, `Documentation/admin-guide/sysctl/`, and the Linux man pages cited per skill.
- freedesktop.org systemd manuals (journald, journal-remote, journalctl): https://www.freedesktop.org/software/systemd/man/ ; XDG Base Directory specification: https://specifications.freedesktop.org/basedir/latest/
- Cisco IOS XE hardening guide: https://sec.cloudapps.cisco.com/security/center/resources/IOS_XE_hardening
- Mozilla server-side TLS configuration: https://ssl-config.mozilla.org

Product documentation: Apache HTTP Server 2.4 (https://httpd.apache.org/docs/2.4/), nginx (https://nginx.org/en/docs/), PHP-FPM and OPcache (https://www.php.net/manual/), MySQL 8.0 Reference Manual (https://dev.mysql.com/doc/refman/8.0/), Podman (https://docs.podman.io/), Docker Engine, Compose and pruning (https://docs.docker.com/), cloud-init (https://cloudinit.readthedocs.io/), Certbot (https://eff-certbot.readthedocs.io/), Let's Encrypt documentation and rate limits (https://letsencrypt.org/docs/), Ansible (https://docs.ansible.com/), rclone (https://rclone.org/docs/), Fluent Bit (https://docs.fluentbit.io/), rsyslog (https://www.rsyslog.com/doc/), Postfix (https://www.postfix.org/documentation.html), netfilter (https://www.netfilter.org/documentation/), nftables wiki (https://wiki.nftables.org/), UFW (https://wiki.ubuntu.com/UncomplicatedFirewall), OpenSSL (https://www.openssl.org/docs/), Lynis (https://cisofy.com/lynis/), AIDE (https://aide.github.io/), rkhunter (https://rkhunter.sourceforge.net/), chkrootkit (https://www.chkrootkit.org/), sops (https://getsops.io), age (https://filippo.io/age), pre-commit (https://pre-commit.com), jq (https://stedolan.github.io/jq/manual/), GNU awk (https://www.gnu.org/software/gawk/manual/gawk.html), Debian manpages (https://manpages.debian.org/) and pytest cache (https://docs.pytest.org/en/stable/how-to/cache.html).

### Websites and articles

- "journalctl" article on 0pointer.de: https://0pointer.de/blog/projects/journalctl.html
- LXD 2.0 blog series on stgraber.org: https://stgraber.org/2016/03/11/lxd-2-0-blog-post-series-012/
- Mail-deliverability checkers and sender portals: MXToolbox (https://mxtoolbox.com), mail-tester (https://www.mail-tester.com/), dmarcian DMARC inspector (https://dmarcian.com/dmarc-inspector/), Google Postmaster Tools (https://postmaster.google.com), Microsoft SNDS (https://sendersupport.olc.protection.outlook.com/snds/), Yahoo Sender Hub (https://senders.yahooinc.com/), Spamhaus (https://check.spamhaus.org/)
- TLS test services: Qualys SSL Labs (https://www.ssllabs.com/ssltest/), Mozilla Observatory (https://observatory.mozilla.org/), HSTS preload list (https://hstspreload.org), testssl.sh (https://testssl.sh)
- OpenAI image-generation and image-prompting guides, cited by `docs/ai-prompting/domain-prompt-compilation-contract.md`: https://developers.openai.com/api/docs/guides/image-generation
- Linux Skills repository: https://github.com/peterbamuhigire/linux-skills
