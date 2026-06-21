# linux-skills Agent Guide

## Purpose

This repository is a Linux server management skills system centered on portable `SKILL.md` files.
It is optimized for Claude Code, but the same skills are intended to work cleanly with Codex
without duplicating logic or requiring a different directory layout.

The repository contains:

- 40 specialist skills grouped into 15 numbered category directories (`01-provisioning-and-bootstrap` through `15-compliance-and-auditing`), e.g. `04-web-and-mail-services/linux-webstack/`, `07-security-and-hardening/linux-security-analysis/`, `12-containers-and-orchestration/linux-container-engine/`, and `15-compliance-and-auditing/linux-auditd-rules/` (the `linux-sysadmin/` hub stays at the repo root)
- A colocated `SKILL.md` in each skill directory
- Optional `references/` and `scripts/` folders inside each skill directory
- Repo-wide engine and operational docs under `docs/`
- Shared executable tooling under `scripts/`

Do not assume the repo must live under a particular folder name. For Claude Code, the repo is often
cloned to `~/.claude/skills`. For Codex, use the repository in place and treat the existing skill
directories as the source of truth.

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

Start from these skills unless the task is already narrowly scoped:

- `linux-sysadmin`: routing hub for Linux server tasks
- `linux-bash-scripting`: mandatory meta-skill before writing or reviewing `sk-*` scripts
- `skill-writing`: meta-skill for creating or upgrading portable skills
- `skill-safety-audit`: review gate for new or imported skill content

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

## Quality Expectations

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

**Resolve its location on THIS device from your global engine-routing table** (`~/.claude/CLAUDE.md`,
or `AGENTS.md` for Codex) — never assume an absolute path; it varies per machine. Then read its
`README.md` → `doctrine/design-doctrine.md` → glob `skills/**/SKILL.md` fresh and route by
frontmatter (read SKILL.md directly, not via the Skill tool). Content and structure stay in THIS
engine; presentation comes from design-system-skills. Hard rule: never use a banned AI-slop font
(Inter, Geist, Roboto, Arial, Open Sans, Lato, Space Grotesk, bare system stacks) as primary
type — state the chosen typeface and reason before producing any artifact.
<!-- /design-system-skills:trigger -->
