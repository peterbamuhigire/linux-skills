# linux-skills Agent Guide

## Universal agent integration

See `.skills-engine/engine-manifest.yaml` for the declarative contract used by the optional universal coordination package. The router and domain SKILL.md files remain authoritative.

The package may read the router, discover skills, inspect Git, and run only declared checks. Missing evidence is NOT ASSESSED; writes, pulls, publication, submissions, ledger/filing changes, deployment, or control changes require explicit approval.

## Mandatory Digital Research currentness gate for Kaizen

Every Kaizen audit, skill edit, reference update, validator change, and
standardisation decision MUST begin with the Digital Research Engine at
`C:\wamp64\www\digital-research-skills`. Read its `source-evaluation` and
`source-verification` skills and the currentness gate reference
`docs/continuous-improvement/kaizen-currentness-gate.md`.

Before admitting any standard, policy, law, technology, platform capability,
software version, command, security control, benchmark, or lifecycle claim,
record source scope, publication/version date, access date, freshness class,
review date, support status, and uncertainty. Use current authoritative
primary sources; quarantine stale/ambiguous/unsupported claims and mark them
`NOT_ASSESSED`. Books are durable concept inputs only.

The shared control plane is adapted to operational safety in
[`docs/control-plane-adoption.md`](docs/control-plane-adoption.md); the central
registry is `C:\wamp64\www\skills-web-dev\docs\engine-control-plane.json`.

## Purpose

This repository is a Linux server management skills system centred on portable `SKILL.md` files.
The canonical operating content is runner-neutral and can be loaded by Claude Code, Codex, or
another agent runner without duplicating logic or requiring a particular directory layout.

The repository contains:

- 40 specialist skills grouped into 15 numbered category directories (`01-provisioning-and-bootstrap` through `15-compliance-and-auditing`), e.g. `04-web-and-mail-services/linux-webstack/`, `07-security-and-hardening/linux-security-analysis/`, `12-containers-and-orchestration/linux-container-engine/`, and `15-compliance-and-auditing/linux-auditd-rules/` (the `linux-sysadmin/` hub stays at the repo root)
- A colocated `SKILL.md` in each skill directory
- Optional `references/` and `scripts/` folders inside each skill directory
- Repo-wide engine and operational docs under `docs/`
- Shared executable tooling under `scripts/`

Do not assume the repo must live under a particular folder name. A runner may use any configured
skill root or the repository in place. Claude Code commonly uses `~/.claude/skills`, but that is an
optional adapter path; Codex and generic agents should treat the existing skill directories as the
source of truth without requiring that path.

## Portable entry points

- Generic or manual use: resolve the repository root from this file or `README.md`, then load
  `linux-sysadmin/SKILL.md` as the default route.
- Codex or another agent runner: load `AGENTS.md` and the selected `SKILL.md` directly. No
  runner-specific setup script or fixed home-directory path is required.
- Claude Code: `CLAUDE.md` and `scripts/setup-claude-code.sh` are optional Claude-specific
  overlays/bootstrap. They must not be treated as prerequisites for the canonical skills. The
  bootstrap requires an explicit `--dry-run` review, exact target flags, separate network/user/
  privileged-write authority, and a recovery-file path before a real mutation is allowed.

## Two-Family Support (Debian/Ubuntu + RHEL)

Every specialist skill and `sk-*` script supports **both** the Debian family
(Debian, Ubuntu) and the **RHEL family** (Fedora, RHEL, CentOS Stream, Rocky,
Alma, Oracle). When acting on a task:

- Read the skill's **`## Distro support`** matrix (its first H2) to pick the
  right command/path/service for the target distro.
- In scripts, never hardcode `apt`/`ufw`/`apache2`. Use the `common.sh`
  primitives: `detect_distro`, `pkg_install`, `pkg_is_installed`, `ensure_epel`,
  `svc_name`, `firewall_allow`, `web_conf_dir`, `web_reload`, `require_family`.
- Deep-dive RHEL references: firewalld, SELinux, httpd/conf.d,
  NetworkManager/nmcli, Kickstart — each lives under its owning skill's
  `references/`.
- Design, phasing, and status: `docs/multi-distro/plan.md`. The invariant
  `scripts/tests/check-distro-matrix.sh` must pass.

## Baseline Skills

Kaizen is mandatory for the engine and every operational product. Load `meta/kaizen-improvement-system/SKILL.md` for audits and improvement planning; cap published audits at 65/100 and target 95/100 with dual-distro, safety, rollback, recovery, and reviewer evidence.

Start from these skills unless the task is already narrowly scoped:

- `linux-sysadmin`: routing hub for Linux server tasks
- `linux-bash-scripting`: mandatory meta-skill before writing or reviewing `sk-*` scripts
- `skill-writing`: meta-skill for creating or upgrading portable skills
- `skill-safety-audit`: review gate for new or imported skill content

For current or uncertain distro, security, compliance, vendor, platform, legal, or safety claims, route to `C:\wamp64\www\digital-research-engine` and load its source-evaluation and source-verification skills before standardising a command or policy. This Linux engine is an operational consumer of that research engine, not a substitute for current-source verification.

## Routing

Use `linux-sysadmin` as the default entry point for server work, then route quickly:

- Provisioning and bootstrap: `linux-server-provisioning`, `linux-cloud-init`, `linux-package-management`, `linux-config-management`
- Deployment and web stack: `linux-site-deployment`, `linux-webstack`, `linux-mail-server`, `linux-service-management`
- Security: `linux-security-analysis`, `linux-server-hardening`, `linux-access-control`, `linux-firewall-ssl`, `linux-intrusion-detection`, `linux-secrets`
- Operations: `linux-system-monitoring`, `linux-log-management`, `linux-observability`, `linux-disk-storage`
- Networking: `linux-network-admin`, `linux-dns-server`
- Virtualization and automation: `linux-virtualization`, `linux-repo-sync`
- Databases and caching: `linux-mysql-mariadb`, `linux-postgresql`, `linux-inmemory-stores`
- Containers and orchestration: `linux-container-engine`, `linux-container-deployment`, `linux-image-hygiene`
- Backup and archiving: `linux-rsync-sync`, `linux-archive-integrity`, `linux-filesystem-snapshots`
- Performance and kernel: `linux-sysctl-tuning`, `linux-kernel-modules`, `linux-perf-profiling`
- Compliance and auditing: `linux-auditd-rules`, `linux-file-integrity`, `linux-benchmark-scanning`
- Incident and recovery: `linux-troubleshooting`, `linux-disaster-recovery`

When the task is about creating or upgrading skills in this repo, use `skill-writing`. When the
task is about script authoring or review under `scripts/`, use `linux-bash-scripting` first.

Skill authoring and release follow [`docs/engine-design/skill-authoring-standard.md`](docs/engine-design/skill-authoring-standard.md).
Start new skills from [`templates/skill-template.md`](templates/skill-template.md), add routing
fixtures, and run the zero-debt validator, routing smoke test, canonical quick validator, canonical
engine scanner, distro-matrix test, safety review, and anti-slop release gate. Never add findings to
`quality-baseline.json`; it is a zero-debt assertion, not a waiver.

## How To Use Skills In This Repo

1. Read the target skill's `SKILL.md` first.
2. Treat the top contract sections as the portable execution layer:
   `Use when`, `Do not use when`, `Required inputs`, `Workflow`, `Quality standards`,
   `Anti-patterns`, `Outputs`, and `References`.
3. Use the rest of the skill body as the detailed manual procedure.
4. Load `references/` files only when the active task needs the extra depth.
5. Treat `scripts/` and listed `sk-*` tools as optional accelerators unless the task is explicitly about script development.

## Working Rules

- Preserve existing Claude Code behavior. Do not move skill directories or split logic into a new `skills/` tree unless there is no viable alternative.
- Keep `SKILL.md` concise and execution-oriented. Move heavy material into `references/`.
- Do not assume optional scripts are installed. Manual commands remain the baseline truth.
- Prefer local repository references over invented guidance. If a skill points to `docs/` or `references/`, follow those files.
- Keep repo-level policy in `AGENTS.md` and Claude-specific policy in `CLAUDE.md`; do not bury repo policy inside unrelated skills.
- If a skill changes in a way that affects `sk-*` scripts or manifests, update the related script docs and manifests in the same change.
- Keep platform evidence in [`docs/continuous-improvement/platform-test-matrix-2026-08.md`](docs/continuous-improvement/platform-test-matrix-2026-08.md); a local structural or fixture result must not be reported as live Linux or production evidence.

## Quality Expectations

### Machine-error editorial gate (ME1-ME7)

Apply Digital Research's `docs/continuous-improvement/machine-errors-editorial-gate-2026-09-03.md`
to runbooks, incident explanations, change plans, and operator-facing notes. Check ME1 semantic
repetition, ME2 decorative symmetry, ME3 over-explanation, ME4 inflated risk or benefit, ME5 generic
examples, ME6 repeated rhetorical tics, and ME7 paragraphs with no command, condition, evidence,
decision, or recovery step. Preserve repeated commands, warnings, rollback steps, and safety gates
when they are functionally required; record the exception. Unavailable host, lab, or source evidence
is `NOT_ASSESSED`.

- Skills must be composable: one clear responsibility per skill, with explicit handoffs.
- Outputs must be actionable: findings, commands, decisions, verification steps, or produced artifacts.
- References must be curated, structured, and directly useful. Avoid raw dumps.
- Platform-specific behavior should be optional layering, not the only way a skill works.
- Safety-sensitive operations must remain explicit about confirmation, validation, and verification.

## Codex Notes

Codex can use this repository effectively without a special folder structure if:

- `SKILL.md` stays portable and self-explanatory
- task-to-skill routing is clear from this file and `linux-sysadmin`
- references are local and explicit
- Claude-specific assumptions are presented as examples, not universal requirements

When updating the repo for compatibility, prefer minimal layering over restructuring.

<!-- design-system-skills:trigger v1 -->
### Design / typography / UI/UX (cross-cutting — consult IN ADDITION)

Any work touching how an artifact LOOKS — font/typeface choice, type scale, colour, layout/grid,
visual identity, web/desktop/mobile UI screens, or the visual formatting of a DOCX/PPTX/PDF/XLSX
— routes to the **`design-system-skills`** engine, the single home for ALL design/UI/UX skills
and the anti-AI-slop doctrine.

**Resolve its location on THIS device from the active runner's global
engine-routing table or `AGENTS.md`** — never assume an absolute path; it
varies per machine. Then read its
`README.md` → `doctrine/design-doctrine.md` → glob `skills/**/SKILL.md` fresh and route by
frontmatter (read SKILL.md directly, not via the Skill tool). Content and structure stay in THIS
engine; presentation comes from design-system-skills. Hard rule: never use a banned AI-slop font
(Inter, Geist, Roboto, Arial, Open Sans, Lato, Space Grotesk, bare system stacks) as primary
type — state the chosen typeface and reason before producing any artifact.
<!-- /design-system-skills:trigger -->
