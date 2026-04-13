# linux-skills Agent Guide

## Purpose

This repository is a Linux server management skills system centered on portable `SKILL.md` files.
It is optimized for Claude Code, but the same skills are intended to work cleanly with Codex
without duplicating logic or requiring a different directory layout.

The repository contains:

- Top-level skill directories such as `linux-webstack/`, `linux-security-analysis/`, and `linux-troubleshooting/`
- A colocated `SKILL.md` in each skill directory
- Optional `references/` and `scripts/` folders inside each skill directory
- Repo-wide engine and operational docs under `docs/`
- Shared executable tooling under `scripts/`

Do not assume the repo must live under a particular folder name. For Claude Code, the repo is often
cloned to `~/.claude/skills`. For Codex, use the repository in place and treat the existing skill
directories as the source of truth.

## Baseline Skills

Start from these skills unless the task is already narrowly scoped:

- `linux-sysadmin`: routing hub for Linux server tasks
- `linux-bash-scripting`: mandatory meta-skill before writing or reviewing `sk-*` scripts
- `skill-writing`: meta-skill for creating or upgrading portable skills
- `skill-safety-audit`: review gate for new or imported skill content

## Routing

Use `linux-sysadmin` as the default entry point for server work, then route quickly:

- Provisioning and bootstrap: `linux-server-provisioning`, `linux-cloud-init`
- Deployment and web stack: `linux-site-deployment`, `linux-webstack`, `linux-service-management`
- Security: `linux-security-analysis`, `linux-server-hardening`, `linux-access-control`, `linux-firewall-ssl`, `linux-intrusion-detection`, `linux-secrets`
- Operations: `linux-system-monitoring`, `linux-log-management`, `linux-disk-storage`, `linux-package-management`
- Networking: `linux-network-admin`, `linux-dns-server`, `linux-mail-server`
- Automation and platform: `linux-config-management`, `linux-observability`, `linux-virtualization`
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
