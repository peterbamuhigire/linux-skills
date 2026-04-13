---
name: skill-writing
description: Guide for creating effective skills that work across Claude Code, Codex, Gemini CLI, and other portable skill systems. Use when creating a new skill or updating an existing skill for cross-agent reuse.
license: Complete terms in LICENSE.txt
compatibility: Designed for Claude Code, Codex, and Gemini CLI with a portable SKILL.md plus repo-level instructions where needed
---

# Skill Creator

## Use when

- Creating a new portable skill package.
- Upgrading an existing `SKILL.md` to be clearer, smaller, and more cross-platform.
- Deciding what belongs in `SKILL.md` versus `references/`, `scripts/`, or `assets/`.

## Do not use when

- The task is only to execute an existing skill rather than author one.
- The change is repo-specific policy that belongs in `AGENTS.md` or `CLAUDE.md`, not in a skill package.

## Required inputs

- The skill name, target workflow, and likely trigger phrases.
- Any scripts, references, assets, or templates the skill needs.
- The platforms the skill must support and any non-portable features to avoid.

## Workflow

1. Define the skill boundary, trigger description, and expected outputs.
2. Keep the active `SKILL.md` concise and move heavy detail into `references/`.
3. Use only portable frontmatter fields unless a platform-specific extension is truly required.
4. Validate naming, description quality, workflow clarity, and packaging before publishing.

## Quality standards

- The skill must be execution-oriented, not essay-like.
- Discovery text should make activation obvious from natural user phrasing.
- Supporting resources should be progressive: `SKILL.md` first, references/scripts on demand.

## Anti-patterns

- Packing large reference dumps into `SKILL.md`.
- Mixing unrelated workflows into one skill.
- Relying on one platform's proprietary fields when portability is a goal.

## Outputs

- A portable `SKILL.md` with clear activation guidance and workflow.
- Any supporting `references/`, `scripts/`, or `assets/` that the workflow requires.
- Packaging or validation steps for distribution.

## References

- [`references/generation-template.md`](references/generation-template.md)
- [`references/skill-authoring-best-practices.md`](references/skill-authoring-best-practices.md)
- [`references/output-patterns.md`](references/output-patterns.md)
- [`references/workflows.md`](references/workflows.md)

Skills are modular, self-contained packages that extend AI agent capabilities with specialized
knowledge, workflows, and tools. The most portable form is a concise `SKILL.md` plus optional
`references/`, `scripts/`, and `assets/`. Claude Code and Gemini CLI both align closely with the
**Agent Skills open standard** (agentskills.io); Codex can use the same skill packages effectively
when the repo also exposes clear routing and working rules through `AGENTS.md`.

---

## The Agent Skills Open Standard

Both Claude Code and Gemini CLI implement the same base standard. Skills you write using only
standard fields work on **all compatible platforms** without modification.

### Standard SKILL.md Format

```yaml
---
name: skill-name          # Required. Lowercase, hyphens only. Must match directory name.
description: What this skill does and when to use it.  # Required. Max 1024 chars.
license: MIT              # Optional. License name or reference to LICENSE.txt.
compatibility: Requires Python 3.10+  # Optional. Environment requirements.
metadata:                 # Optional. Arbitrary key-value store.
  author: your-name
  version: "1.0"
allowed-tools: Read Grep  # Optional. Pre-approved tools (experimental, cross-platform).
---

Skill body content here — any Markdown.
```

### Standard Frontmatter Fields

| Field | Required | Standard Rule |
|-------|----------|---------------|
| `name` | Yes | 1–64 chars. Lowercase `a-z`, digits, hyphens. No leading/trailing/consecutive hyphens. **Must match directory name.** |
| `description` | Yes | 1–1024 chars. Describe what + when. Front-load the key use case. |
| `license` | No | License name or bundled file reference |
| `compatibility` | No | Max 500 chars. Environment or platform requirements. |
| `metadata` | No | Key-value map. Use for author, version, tags. |
| `allowed-tools` | No | Space-delimited. Pre-approved tools. Experimental. |

---

## Claude Code Extensions (Claude Code Only)

Claude Code adds fields beyond the standard. Use these only when targeting Claude Code:

| Field | Purpose | Default |
|-------|---------|---------|
| `disable-model-invocation: true` | Only you can invoke it (not auto-triggered by Claude) | false |
| `user-invocable: false` | Hide from `/` menu — Claude loads it, user doesn't invoke it | true |
| `argument-hint: [issue-number]` | Hint shown in autocomplete for expected arguments | — |
| `context: fork` | Run in isolated subagent context | inline |
| `agent: Explore` | Which subagent type to use with `context: fork` | general-purpose |
| `model: claude-opus-4-6` | Override model for this skill | session model |
| `effort: high` | Effort level override. Options: low/medium/high/max | session default |
| `paths: src/**/*.ts` | Glob patterns — auto-activates only when working these files | all files |
| `shell: powershell` | Shell for inline commands. `bash` (default) or `powershell` | bash |
| `hooks` | Skill lifecycle hooks | — |

### Claude Code: String Substitutions (Body)

Available in skill body when invoked in Claude Code:

| Variable | Expands to |
|----------|-----------|
| `$ARGUMENTS` | All arguments after `/skill-name` |
| `$ARGUMENTS[0]`, `$0` | First argument |
| `${CLAUDE_SESSION_ID}` | Current session ID |
| `${CLAUDE_SKILL_DIR}` | Absolute path to skill directory |

### Claude Code: Dynamic Context Injection

Run shell commands before Claude sees the skill. Output replaces the placeholder:

```markdown
## PR context
- Diff: !`gh pr diff`
- Files: !`gh pr diff --name-only`
```

---

## Gemini CLI Discovery

Skills activate via the `activate_skill` tool. User confirms, then full SKILL.md loads.

**Discovery paths:**
```
.agents/skills/<name>/SKILL.md     ← workspace (highest priority)
.gemini/skills/<name>/SKILL.md     ← workspace (alternative)
~/.agents/skills/<name>/SKILL.md   ← user-level
~/.gemini/skills/<name>/SKILL.md   ← user-level (alternative)
```

Management: `gemini skills list|install|link|uninstall|enable|disable`

---

## Directory Structure

```
skill-name/           ← Directory name MUST match name field
├── SKILL.md          ← Required: frontmatter + instructions
├── scripts/          ← Optional: executable code (Python, Bash, JS)
├── references/       ← Optional: docs loaded on demand
└── assets/           ← Optional: templates, images, fonts
```

### What Goes Where

| Content | Location | When Loaded |
|---------|----------|-------------|
| Core instructions and workflow | SKILL.md | Every activation |
| Detailed reference / large docs | references/*.md | When Claude reads them |
| Executable utilities | scripts/ | When Claude runs them |
| Templates, images, fonts | assets/ | When used in output |

**Never create:** README.md, INSTALLATION_GUIDE.md, CHANGELOG.md, or other meta-docs inside a skill.

---

## Core Principles

### 1. Context Window is a Public Good
Only add content Claude doesn't already have. Every token in SKILL.md costs context on every
activation. Challenge every paragraph: "Does Claude really need this?"

### 2. Set the Right Degree of Freedom
- **High freedom (prose):** Multiple valid approaches, context-dependent decisions
- **Medium freedom (pseudocode + params):** A preferred pattern, some variation OK
- **Low freedom (exact scripts):** Fragile operations, consistency critical

### 3. Description is the Trigger Mechanism
The `description` field is the only thing agents read before deciding to activate.
Make it scannable. Front-load the use case. Include keywords users naturally say.
Claude Code truncates descriptions at 250 chars in the listing — keep the core use case first.

### 4. Progressive Disclosure
```
Level 1: name + description (~100 tokens) — always in context, all skills
Level 2: SKILL.md body (<500 lines) — loaded on activation
Level 3: references/, scripts/, assets/ — loaded only when needed
```

---

## Writing Cross-Platform Skills

To ensure a skill works on Claude Code **and** Gemini CLI:

✅ Use only standard fields: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`  
✅ Keep `name` lowercase, hyphens only, matching the directory name  
✅ Keep `description` under 250 chars (Claude Code truncation limit)  
✅ Reference supporting files from SKILL.md body so both platforms discover them  
✅ Keep SKILL.md under 500 lines  

❌ Don't use `disable-model-invocation`, `context: fork`, `$ARGUMENTS`, `` !`cmd` `` if targeting both platforms  

## Codex Compatibility

Codex is not hard-wired to the same discovery paths as Claude Code or Gemini CLI, so portability
depends on instruction design more than folder names.

To make a skill work well in Codex:

✅ Keep the main execution contract in `SKILL.md`: use cases, required inputs, workflow, quality bar, anti-patterns, outputs  
✅ Keep heavy reference content in `references/` and point to it explicitly  
✅ Add or update a repo-level `AGENTS.md` so Codex knows the repo purpose, routing rules, and baseline expectations  
✅ Avoid hidden assumptions that the repo must live under `~/.claude/skills` or `.agents/skills` unless that path is only an example for one platform  
✅ Preserve any Claude-specific optimizations as optional layers, not as the only way the skill makes sense  

For dual-compatible repos, treat `SKILL.md` as the portable unit and `AGENTS.md`/`CLAUDE.md` as the
host-specific instruction layer.

---

## Skill Creation Process

1. **Understand** — Get concrete examples of how the skill will be used
2. **Plan** — Identify what scripts, references, and assets belong in the skill
3. **Initialize** — Run `scripts/init_skill.py <skill-name> --path <dir>`
4. **Build** — Write SKILL.md + resources. Use imperative language ("Use X", "Follow Y")
5. **Package** — Run `scripts/package_skill.py <skill-folder>` → creates `.skill` zip file
6. **Iterate** — Test on real tasks, update based on how Claude performs

### SKILL.md Generation Prompt

See **[references/generation-template.md](references/generation-template.md)** for the full
generation template to use when asking Claude to write a SKILL.md from scratch.

### Best Practices

- Write in imperative/infinitive form: "Use X", "Follow Y", "Implement Z"
- Keep SKILL.md under 500 lines — move depth to `references/`
- Keep references one level deep from SKILL.md (no deep nesting)
- Add a table of contents to reference files longer than 100 lines
- Test description triggers across multiple phrasings
- One skill per workflow — split unrelated workflows into separate skills
- Security: run `skill-safety-audit` on new skills before deploying

### Security Checklist

- No secrets, API keys, or credentials in any skill file
- Inspect scripts for hidden installers or data exfiltration
- Watch for prompt injection patterns in references
- Run `skill-safety-audit` workflow before sharing

---

## Authoring Best Practices

See **[references/skill-authoring-best-practices.md](references/skill-authoring-best-practices.md)**
for detailed patterns, output format guidance, and workflow design.

See **[references/output-patterns.md](references/output-patterns.md)** for template and example patterns.
