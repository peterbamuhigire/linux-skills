# System Reconstruction

## What This System Is

`linux-skills` is a two-layer Ubuntu/Debian operations engine:

- a **knowledge layer** built from `SKILL.md` files and curated references
- an **execution layer** built from `sk-*` scripts, `common.sh`, and `install-skills-bin`

The system is intentionally manual-first. Skills must remain usable even if no scripts are
installed. Scripts are meant to accelerate and standardize the same workflows, not replace operator
understanding.

## Core Components

### `linux-sysadmin`

This is the routing hub. Its job is to classify work and hand it to the correct specialist skill.
Operationally, it behaves like a dispatcher for:

- provisioning
- security
- operations
- networking
- recovery
- script development

### `linux-bash-scripting`

This is the meta-skill for the execution layer. It defines:

- the six-section script template
- standard flags
- the `common.sh` contract
- safety rules
- interaction rules for both human and agent callers

### Specialist skills

Each `linux-*` skill is a domain module. The main design rule is that every domain remains
self-contained. That means:

- manual commands are primary
- `sk-*` tools are optional fast paths
- the skill still works when the automation layer is incomplete

### `common.sh`

This is the shared runtime contract. It centralizes:

- output primitives
- guard functions
- confirmation and prompts
- temporary file handling
- atomic writes
- flag parsing
- cleanup behavior
- audit logging

This is what turns individual shell scripts into a coherent engine.

### `install-skills-bin`

This is the distribution layer for scripts. The intended operating model is:

- `install-skills-bin core` installs the tier-1 baseline toolkit
- `install-skills-bin <skill-name>` installs a skill's scripts on first use

This is a reasonable middle ground between shipping everything everywhere and forcing manual
per-script installs.

## Skill And Script Interaction

The intended lifecycle is:

1. Start from `linux-sysadmin` or a specific domain skill.
2. Follow the manual workflow in the skill.
3. If scripts exist and are installed, use the `Optional fast path`.
4. Use `install-skills-bin` to install the scripts declared in the skill manifest.
5. Rely on `common.sh` for consistent runtime behavior.

This relationship is one of the repository's best architectural choices. It keeps:

- domain knowledge in skills
- automation in scripts
- policy in the engine spec

## Real-World Usage Flow

### Provisioning flow

1. Clone the repo to `~/.claude/skills`
2. Run `scripts/setup-claude-code.sh`
3. Run `install-skills-bin core`
4. Use `linux-server-provisioning` and supporting skills
5. Install additional per-skill scripts as needed

### Diagnosis flow

1. Start with `linux-troubleshooting`
2. Capture a quick triage snapshot
3. Follow the appropriate diagnosis branch
4. Hand off to the owning specialist skill
5. Verify the fix

### Security flow

1. Run `linux-security-analysis` or `sk-audit`
2. Record findings by severity
3. Hand off to `linux-server-hardening`
4. Re-run the audit to verify closure

### Recovery flow

1. Confirm this is real data loss or corruption
2. Identify the right backup
3. Restore with `linux-disaster-recovery`
4. Verify service and data state

## Design Philosophy

The engine is built around five ideas:

### 1. Self-contained skills

Every skill should remain useful even if scripts are missing.

### 2. Safety-first mutation

The engine intends to require:

- explicit confirmation
- dry-run support
- validation before reload
- audit logging

### 3. Idempotent automation

Scripts are meant to be safe to re-run and to produce deterministic outcomes.

### 4. Dual-use execution

The same scripts should work for:

- human operators
- Claude Code in non-interactive mode

The `--yes` contract is the key design innovation here.

### 5. Incremental engine growth

The repository does not force full automation up front. It uses:

- manual-first knowledge
- a staged script inventory
- a core-versus-lazy-install script model

## Current Reality Versus Intended Reality

### Intended reality

The design describes a credible Linux operations engine with:

- a strong script contract
- a controlled install path
- test-backed trust
- domain-aligned automation

### Current reality

Today, the repository is:

- mature as a knowledge system
- strong as an engine design
- still early as an implemented engine

That is the central truth of the current evaluation.
