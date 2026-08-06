# linux-skills

See [`docs/control-plane-adoption.md`](docs/control-plane-adoption.md) for
infrastructure agents, thin commands, safety hooks, rollback evidence, and
incident handoffs.

**Author:** Peter Bamuhigire | [techguypeter.com](https://techguypeter.com) | +256 784 464 178

A two-family Linux server-management engine for safe, family-aware operations.
It routes an operational request to the smallest useful specialist skill,
produces an explicit handoff and verification target, and keeps human-readable
procedures as the source of truth. Optional sk-* scripts accelerate repeatable
work but never replace the skills or manual verification.

The repository currently contains **44 portable SKILL.md units**: 40 numbered
specialist skills, the linux-sysadmin routing hub, and the skill-writing,
skill-safety-audit, and kaizen-improvement-system meta-skills. The catalogue
spans 15 operational categories, RHEL-family references, engine specifications,
and optional command-line automation.

## Capabilities

This engine covers the Linux operational lifecycle:

- Debian/Ubuntu and RHEL-family provisioning and package management.
- Bash scripting, common.sh abstractions, and family-aware automation.
- Users, SSH access, secrets, permissions, and least-privilege controls.
- Networking, DNS, NTP, NetworkManager, Netplan, mail, web stacks, and TLS.
- Systemd services, virtualization, containers, databases, and caching.
- Monitoring, logging, observability, alerting, and health endpoints.
- Storage, filesystems, performance, kernel tuning, and kernel modules.
- Backups, archive integrity, filesystem snapshots, restore, and disaster recovery.
- Security analysis, hardening, firewalls, SELinux/AppArmor, intrusion detection,
  auditd, file integrity, and benchmark/compliance scanning.
- Troubleshooting, incident learning, migrations, cutovers, and stabilisation.
- Product audits for servers, scripts, runbooks, automation, backup systems,
  recovery procedures, and other operational deliverables.

The engine works with Claude Code and Codex. SKILL.md is the portable execution
unit; AGENTS.md and CLAUDE.md provide repository and host-specific overlays.

## Start here

1. Read AGENTS.md for repository rules and routing boundaries.
2. Start with linux-sysadmin/SKILL.md when the request spans components or the
   correct specialist is not known.
3. Load the selected specialist SKILL.md, including its Distro support matrix,
   before issuing family-specific commands.
4. For script authoring or review, load
   10-automation-and-scripting/linux-bash-scripting/SKILL.md first.
5. For skill authoring or engine changes, load meta/skill-writing/SKILL.md and
   meta/skill-safety-audit/SKILL.md.
6. For engine or product improvement, load
   meta/kaizen-improvement-system/SKILL.md.
7. For current or uncertain distro, security, compliance, vendor, platform,
   legal, or safety claims, route through the separate
   the [Digital Research Engine](https://github.com/peterbamuhigire/digital-research-skills) and use its source-evaluation and
   source-verification workflows before standardising the claim.

The canonical cross-engine paths are maintained in the project-level agent
instructions. Do not copy other engines into this repository.

## Two-family operating model

Every numbered specialist is designed for both major Linux families:

| Family | Supported distributions and normal operating layer |
|---|---|
| Debian family | Debian, Ubuntu, Mint, Pop!_OS, Raspbian, and compatible derivatives; apt, ufw, AppArmor where enabled, and Netplan where present |
| RHEL family | Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle Linux, and compatible derivatives; dnf, firewalld, SELinux, NetworkManager, and httpd conventions |

This is one body with family-aware mappings, not duplicated distro forks. Each
specialist starts with a Distro support matrix. Scripts use the shared library
instead of embedding family-only assumptions.

### Shared common.sh primitives

| Operational need | Use | Do not hardcode in shared logic |
|---|---|---|
| Detect family | detect_distro and SK_DISTRO_FAMILY | Parsing one assumed distro only |
| Package operations | pkg_install, pkg_remove, pkg_update, pkg_is_installed | apt or dnf directly |
| Repository enablement | ensure_epel where appropriate | Assuming EPEL exists on Fedora or Debian |
| Service names | svc_name | apache2, httpd, or another fixed unit name |
| Firewall changes | firewall_allow | ufw or firewall-cmd in a shared path |
| Web configuration | web_conf_dir and web_reload | sites-available or conf.d without mapping |
| Family gate | require_family debian, rhel, or any | A Debian-only guard in a two-family skill |

The full contract is in
10-automation-and-scripting/linux-bash-scripting/references/common-sh-contract.md.
The migration status and runtime boundary are in docs/multi-distro/plan.md.

### Important family differences

| Concern | Debian family | RHEL family | Engine reference |
|---|---|---|---|
| Packages | apt, apt-get, snap where appropriate | dnf, RPM, EPEL where required | linux-package-management |
| Firewall | UFW | firewalld zones and services | 07-security-and-hardening/linux-firewall-ssl/references/firewalld-reference.md |
| Mandatory access control | AppArmor | SELinux contexts, booleans, and AVCs | 07-security-and-hardening/linux-server-hardening/references/selinux-reference.md |
| Apache | apache2 and site directories | httpd and /etc/httpd/conf.d/ | 04-web-and-mail-services/linux-webstack/references/httpd-reference.md |
| Networking | Netplan and standard tools | NetworkManager and nmcli | 03-networking-and-dns/linux-network-admin/references/networkmanager-reference.md |
| Provisioning | cloud-init and autoinstall | cloud-init and Kickstart | 01-provisioning-and-bootstrap/linux-cloud-init/references/kickstart-reference.md |
| Administrative group | sudo conventions | wheel conventions | linux-access-control |
| Containers | Docker, LXD, and compatible tools | Podman, Docker, and compatible tools | linux-container-engine |
| Time synchronisation | systemd-timesyncd or chrony | chrony is common | linux-network-admin |

When only one family is available, the other branch is unassessed, not silently
marked as passing. A real Fedora/RHEL host is still required to validate live
SELinux, firewalld, httpd, NetworkManager, and RHEL-family script behaviour.

## Routing map

Use linux-sysadmin as the default router, then select the narrowest skill:

| Area | Specialist skills |
|---|---|
| Foundation | linux-bash-scripting, linux-sysadmin, skill-writing, skill-safety-audit, kaizen-improvement-system |
| Provisioning and packages | linux-server-provisioning, linux-cloud-init, linux-package-management, linux-config-management |
| Access and secrets | linux-access-control, linux-secrets |
| Networking and DNS | linux-network-admin, linux-dns-server |
| Web and mail | linux-site-deployment, linux-webstack, linux-mail-server |
| Services and virtualisation | linux-service-management, linux-virtualization |
| Storage | linux-disk-storage |
| Security | linux-security-analysis, linux-server-hardening, linux-firewall-ssl, linux-intrusion-detection |
| Observability | linux-system-monitoring, linux-log-management, linux-observability |
| Troubleshooting and recovery | linux-troubleshooting, linux-disaster-recovery |
| Repository automation | linux-repo-sync |
| Databases and caching | linux-mysql-mariadb, linux-postgresql, linux-inmemory-stores |
| Containers | linux-container-engine, linux-container-deployment, linux-image-hygiene |
| Backup and archiving | linux-rsync-sync, linux-archive-integrity, linux-filesystem-snapshots |
| Performance and kernel | linux-sysctl-tuning, linux-kernel-modules, linux-perf-profiling |
| Compliance and auditing | linux-auditd-rules, linux-file-integrity, linux-benchmark-scanning |

Routing must include the user's outcome, host role, family/version, authority
boundary, relevant constraints, and concrete verification target. If a symptom
spans multiple components, route to linux-troubleshooting first.

## Safe operations contract

The engine defaults to read-only inspection. A mutation requires explicit
authority, defined scope, a stop condition, and a recovery path.

Before a change:

1. State the user-visible objective, affected host or service, authority, and
   stop condition.
2. Capture a read-only baseline: distro/version, service and socket state,
   relevant configuration, logs, storage and memory, security context, and
   current backup or snapshot identity.
3. Select the smallest reversible change, expected measure, guardrail, rollback
   action, and recovery owner.
4. Validate the family mapping, syntax, dependencies, authorization, and a
   no-op or dry-run path.
5. Stop when the precondition, backup, rollback, or authorization is missing.

During and after a change:

- Apply one bounded change at a time and record command, timestamp, operator,
  authority, and result.
- Validate configuration before reload or restart: nginx -t, sshd -t,
  visudo -c, or the service-specific equivalent.
- Verify both technical state and user-visible outcome.
- If a guardrail regresses, stop, restore the known-good state, verify
  rollback/recovery, and preserve before/after evidence.
- Prefer atomic file replacement, least privilege, explicit confirmations for
  destructive actions, and family-neutral primitives.
- Treat a second authorised run as a first-class test: it must leave the
  intended state unchanged and report no change where appropriate.

The complete standard is in
docs/continuous-improvement/safe-reversible-operations-standard.md.

## Automation and Bash

The sk-* scripts are optional accelerators installed from this repository. They
source /usr/local/lib/linux-skills/common.sh when installed and follow a common
contract:

- set -uo pipefail, explicit error handling, and quoted variables.
- No untrusted eval, validated inputs, cleanup traps, and safe temporary files.
- --help, --dry-run, and safe non-interactive flags where applicable.
- Explicit confirmation for destructive operations.
- Atomic configuration writes with preserved permissions and security labels.
- Family detection and service/package/firewall abstraction.
- Useful exit codes, operational logs for destructive work, and clear
  changed/no-change/failed outcomes.
- Idempotence by default; deliberately non-idempotent work requires an explicit
  force decision and warning.

The curated script inventory is in
docs/engine-design/script-inventory.md. The design contract is in
docs/engine-design/spec.md.

## Observability, backup, and recovery

Operational completion is not established by a zero exit code alone. The
responsible specialist must identify the evidence that proves the result:

- Service health, listeners, configuration tests, logs, and user-visible probes.
- CPU, memory, disk, inode, network, journal, and application health signals.
- Prometheus/node-exporter, log shipping, /health endpoints, and alert quality
  where the product needs ongoing monitoring.
- Backup identity, encryption/integrity, retention, offsite copy, and restore
  verification.
- Recovery sequence, data-loss boundary, rollback decision, and post-restore
  validation.
- Incident learning record, owner, due date, and standardisation evidence.

Backups are not reliable merely because a job completed. A restore or recovery
path must be tested at an appropriate scope and recorded as evidence. Backup
credential files must remain mode 600.

## Kaizen and continuous improvement

Kaizen is mandatory for this engine and every operational product it produces:
scripts, skills, runbooks, infrastructure changes, monitoring, backup plans,
recovery procedures, migration plans, and audit reports.

The operating loop is:

**Observe -> Baseline -> Select -> Experiment -> Check -> Standardise -> Teach -> Re-measure**

Apply it to the system, not just to documentation. Baseline what can be
measured: operator toil, queue/wait time, rework, duplicate commands, context
switching, failed handoffs, change failure, incident frequency, restore time,
alert quality, failed-path behaviour, distro parity, idempotence, least
privilege, and user impact. Do not invent a baseline when evidence is
unavailable; mark it unassessed and define how it will be collected.

The Linux-specific improvement practices are:

- Value-stream mapping: identify waiting, rework, duplicate work, context
  switching, failed handoffs, and unnecessary output (muda).
- 5S for operational knowledge: sort stale content, set family mappings and
  recovery steps in order, clean references and scripts, standardise the
  workflow, and sustain it through incidents and audits.
- PDCA and QC Story: define the problem, observe the current condition, identify
  root causes, set a measurable target and guardrails, experiment, check
  evidence, standardise the successful change, and schedule follow-up.
- Small reversible experiments: use a bounded change, dry-run, idempotence
  check, failed-path test, rollback, and recovery verification before adoption.
- Blameless incident learning: fix system and process conditions, preserve
  accountability, and keep actions open until technical and user-visible
  evidence exists.
- Platform ownership: gather feedback from operators and internal users, reduce
  cognitive load, and maintain skills, scripts, tests, and references as one
  product.

Detailed references:

- meta/kaizen-improvement-system/SKILL.md
- linux-sysadmin/kaizen-operations-loop.md
- docs/continuous-improvement/kaizen-adoption-2026-08.md
- docs/continuous-improvement/value-stream-5s-qc-story.md
- docs/continuous-improvement/safe-reversible-operations-standard.md
- docs/continuous-improvement/incident-learning-standard.md
- docs/continuous-improvement/two-family-validation-and-recovery.md

### Engine audits

An engine audit assesses routing, skill depth, safety, family parity, script
quality, evidence, references, observability, recovery, accessibility of the
operating guidance, and maintenance hygiene.

The published score is deliberately hard-capped:

~~~text
published_audit_score = min(raw_score, 65)
~~~

The cap is a reporting ceiling, not permission to ignore weaknesses. Every gap
must produce a plan targeting **95/100**, with:

- gap and root cause;
- change, hypothesis, owner, and due point;
- measure and acceptance evidence;
- operational, security, data, or user-impact risk;
- rollback or recovery plan; and
- re-measurement date.

### Product audits

The same contract applies to every product produced by this engine, including a
website deployment, service configuration, database operation, backup plan,
mobile or desktop support runbook, shell script, migration, monitoring setup,
security hardening change, disaster-recovery procedure, or operational report.

A product audit must distinguish:

1. intended outcome and user/operator context;
2. baseline and observed evidence;
3. family-specific behaviour and unassessed branches;
4. safety, authorization, least privilege, and data protection;
5. idempotence, failure handling, rollback, restore, and recovery;
6. observability, alerting, and user-visible verification;
7. maintainability, handoff, standardisation, and the next experiment.

Use docs/continuous-improvement/linux-product-audit-checklist.md and route
uncertain external claims through Digital Research.

## Design and presentation boundary

This engine owns Linux content, structure, commands, operations, and evidence.
For work that changes how an artifact looks, routes in addition to the
design-system-skills engine:

- typography, type scale, colour, layout, grid, and visual identity;
- UI/UX screens for web, desktop, or mobile products;
- visual formatting of reports, runbooks, DOCX, PDF, PPTX, or spreadsheet output;
- anti-AI-slop and visual-quality decisions.

Resolve the design engine path from the global routing table. Read its README,
design doctrine, and relevant SKILL.md files directly. Do not mirror its files
here.

## Testing and quality gates

Run these checks from the repository root:

~~~powershell
# Skill contracts and the zero-debt baseline
python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json

# Routing fixtures and top-three precision
python -X utf8 scripts/routing_smoke_test.py

# Source-ingestion guardrail
python -X utf8 scripts/source_ingestion_guardrail.py
~~~

On a Linux or WSL host, also run:

~~~bash
# Every numbered specialist must expose a Distro support matrix
bash scripts/tests/check-distro-matrix.sh

# Foundation/integration tests where the required runtime is available
sudo ./scripts/tests/run-test.sh --suite foundation
~~~

The repository quality gates also include skill-writing conformance, routing
fixtures, safety review, shell linting for changed scripts, and anti-slop
release review when the corresponding change is in scope. A skill or script is
not ready merely because it parses: its outputs, failure path, evidence, and
handoff must be useful to an operator.

### Current validation limitation

The current development host is Windows PowerShell. Bash and WSL are not
available in this environment, so Bash-only distro-matrix and Linux runtime
integration tests cannot be executed here. Static validation and routing checks
can still run, but they do not replace live Debian-family and RHEL-family
execution. A real Fedora/RHEL host or suitable Linux/WSL test environment is
still required for live validation of SELinux, firewalld, httpd,
NetworkManager, and the migrated scripts.

## Repository layout

~~~
linux-skills/
|-- AGENTS.md                         Repository and routing instructions
|-- CLAUDE.md                         Claude-specific overlay
|-- README.md                         This capability guide
|-- linux-sysadmin/                   Cross-domain routing hub
|-- meta/                             Authoring, safety, and Kaizen skills
|-- 01-provisioning-and-bootstrap/   Provisioning and package operations
|-- 02-users-access-and-secrets/     Access control and secrets
|-- 03-networking-and-dns/           Network and DNS operations
|-- 04-web-and-mail-services/        Web, deployment, and mail
|-- 05-services-and-virtualization/  Services and virtualisation
|-- 06-storage-and-filesystems/      Disks, filesystems, and swap
|-- 07-security-and-hardening/       Security, MAC, firewall, intrusion
|-- 08-observability-and-logging/    Monitoring, logs, and observability
|-- 09-troubleshooting-and-recovery/ Troubleshooting and disaster recovery
|-- 10-automation-and-scripting/     Bash and repository automation
|-- 11-databases-and-caching/        MySQL, PostgreSQL, Redis, Memcached
|-- 12-containers-and-orchestration/ Container engines and images
|-- 13-backup-and-archiving/         Rsync, archives, snapshots
|-- 14-performance-and-kernel/       Profiling, sysctl, modules
|-- 15-compliance-and-auditing/      Auditd, FIM, benchmark scanning
|-- docs/                            Engine design and improvement records
|-- scripts/                         Optional sk-* tools and validators
|-- commands/                        Focused command references
|-- notes/                           Setup and operational notes
~~~

## Installation and use

The repository can be cloned into the host's skill location or used in place.
For a fresh managed server:

~~~bash
git clone <repository-url> ~/.claude/skills
bash ~/.claude/skills/scripts/setup-claude-code.sh
sudo install-skills-bin core
~~~

The installed command location is /usr/local/bin/sk-*, the shared library is
/usr/local/lib/linux-skills/common.sh, and operational logs belong under
/var/log/linux-skills/ when a script requires persistent logging.

Do not assume optional scripts are installed. Read the relevant skill and follow
its manual procedure when the accelerator is absent or unsuitable.

## Non-negotiable operating rules

- Detect the distro family before choosing packages, paths, services, firewall,
  or mandatory-access-control commands.
- Default to read-only inspection and do not infer production-change authority.
- Confirm destructive work using the shared confirmation contract.
- Validate configuration before reload, restart, migration, or cutover.
- Never use automated git reset --hard or git clean -fd to update a server;
  preserve local work with the repository-sync workflow.
- Keep backup credentials at mode 600 and protect secrets in logs and output.
- Keep scripts and skills in lockstep when a skill change affects a script.
- Do not claim RHEL, security, compliance, vendor, or safety facts are current
  without appropriate source verification.
- Mark unavailable evidence as unassessed and define the recovery or research
  step; do not turn absence of evidence into a pass.
- Preserve the existing engine layout and do not mirror other engines' files
  into this repository.

## Related engines

This engine is an operational consumer of the shared engine portfolio. Route to
the appropriate canonical engine when the work crosses domains:

- digital-research-engine for current or uncertain external facts, source
  verification, OSINT, and evidence packs.
- skills-web-dev for software, APIs, databases, cloud, DevOps, and application
  implementation that sits above host operations.
- srs-skills for formal requirements, architecture, testing, deployment, and
  governance documentation.
- design-system-skills for UI/UX, visual design, typography, and visual
  presentation decisions.
- chwezi-accounting-doctrine for accounting, financial controls, and finance
  operations integrated with Linux systems.

The canonical cross-engine routing table is maintained in project-level agent
instructions rather than copied into this repository.
