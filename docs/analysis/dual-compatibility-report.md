# Dual Compatibility Report

**Date:** 2026-04-13  
**Scope:** Upgrade `linux-skills` so it remains fully functional in Claude Code and becomes directly usable by Codex without restructuring the repository.

## What Was Wrong

### 1. Structural assumptions were implicit

- The repository already had a strong skill layout, but some instructions implied Claude-specific clone paths such as `~/.claude/skills`.
- There was no Codex-facing repo instruction file explaining how to route work across skills without relying on Claude's automatic loading model.

### 2. Skill contracts were uneven

- Most `SKILL.md` files had strong operational content but did not consistently expose a portable execution contract.
- Key sections that help cross-agent execution were often missing or inconsistent:
  `Use when`, `Do not use when`, `Required inputs`, `Workflow`, `Quality standards`,
  `Anti-patterns`, `Outputs`, and `References`.
- Claude can tolerate richer prose with more implied behavior; Codex performs better when the activation and workflow contract is explicit near the top.

### 3. Repo policy and skill policy were mixed

- Claude-specific repo behavior lived in `CLAUDE.md`, but there was no equivalent repo-level instruction layer for Codex.
- Safety guidance for imported skills referenced paths and conventions that were not guaranteed to exist in this repo.

## What Was Improved

### Portable skill contract added to every skill

All `SKILL.md` files now expose a concise, execution-oriented contract near the top:

- `Use when`
- `Do not use when`
- `Required inputs`
- `Workflow`
- `Quality standards`
- `Anti-patterns`
- `Outputs`
- `References`

This was layered on top of the existing content rather than replacing it, so the current Claude Code behavior is preserved while Codex gets a clearer entry surface.

### Root Codex instruction layer added

A new root `AGENTS.md` now defines:

- repository purpose
- baseline skills
- task-to-skill routing
- working rules
- quality expectations
- Codex-specific guidance for using the existing layout as-is

This avoids any need to move skills into a new folder or duplicate instructions.

### Cross-platform authoring guidance strengthened

`skill-writing/SKILL.md` was updated to:

- explicitly include Codex in its compatibility goal
- explain the role of `AGENTS.md` for Codex
- reinforce the pattern of portable `SKILL.md` plus host-specific repo instructions

### Safety guidance aligned to the repo

`skill-safety-audit/SKILL.md` now:

- includes standard frontmatter metadata
- references `AGENTS.md` and `CLAUDE.md` as the active policy layer
- avoids implying a mandatory `skills/` subfolder

### Repo entry guidance improved

`README.md` now points non-Claude agents to `AGENTS.md` and explicitly describes the dual-compatible model.

## What Was Added

- Root [`AGENTS.md`](../../AGENTS.md)
- Portable execution-contract sections across all skill files
- [`docs/analysis/dual-compatibility-report.md`](dual-compatibility-report.md)
- Codex-specific compatibility guidance inside `skill-writing/SKILL.md`

## Why The Changes Matter

- **Claude compatibility is preserved:** the original skill bodies, references, manifests, and workflow structure remain in place.
- **Codex compatibility is improved:** skills now advertise activation signals, required inputs, outputs, and references in a form that works without Claude-specific loading assumptions.
- **No fragmentation:** the same `SKILL.md` remains the core unit for both systems.
- **No unnecessary restructuring:** top-level skill directories remain where they are.
- **Composability improves:** routing between skills is now more explicit, especially for cross-domain or incident-driven work.

## Recommendations

### High-value next steps

- Add a short compatibility note to any skill body section that still uses `~/.claude/skills` examples, clarifying when the path is an example versus a requirement.
- Add a lightweight validation script that checks every `SKILL.md` for the portable contract headings.
- Add one short example task per major skill showing expected inputs and outputs for faster agent activation.

### Optional structural optimizations

- Add nested `AGENTS.md` files only if a subdomain becomes large enough to need local routing rules, such as `scripts/` or `docs/engine-design/`.
- Create a repo-level skill index document generated from frontmatter if the skill count keeps growing.

These are optional. The current repository can already function as a dual-compatible skills system without them.
