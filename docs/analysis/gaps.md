# Gaps

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

What is missing, weak, or unresolved about `linux-skills` as of 2026-04-10,
ranked by severity. Every gap has a specific remediation — they are
work items, not complaints.

**Severity definitions:**

- **CRITICAL** — blocks the engine from being used at all.
- **HIGH** — the engine runs but with meaningful limitations or risk.
- **MEDIUM** — a capability is weaker than it should be, but there are
  workarounds.
- **LOW** — polish or future-looking improvement.

## Table of contents

- [CRITICAL gaps](#critical-gaps)
- [HIGH gaps](#high-gaps)
- [MEDIUM gaps](#medium-gaps)
- [LOW gaps](#low-gaps)
- [Closed since last analysis](#closed-since-last-analysis)

---

## CRITICAL gaps

### C1. Zero `sk-*` scripts exist

**What's missing:** Of the 88 scripts in
[`script-inventory.md`](../engine-design/script-inventory.md), **zero**
are written to the current spec. Only 4 legacy scripts exist in
`scripts/` (`server-audit.sh`, `mysql-backup.sh`, `update-all-repos`,
`setup-claude-code.sh`), none of which follow the six-section template or
source a non-existent `common.sh`.

**Why CRITICAL:** the entire engine's runtime value depends on these
scripts. Without them, `linux-skills` is a knowledge base — useful, but
not the command-line toolkit described in the spec.

**Remediation:** build them. Start with the foundation (common.sh,
installer, test harness), then tier-1 scripts 1–5, verify in LXD, then
the remaining 83. See [`build-order.md`](build-order.md).

**Effort:** 50–80 hours of focused implementation.

---

### C2. `scripts/lib/common.sh` does not exist

**What's missing:** The shared library that every `sk-*` script must
source. Specified in full in
[`spec.md §6`](../engine-design/spec.md) and in the contract reference
at [`linux-bash-scripting/references/common-sh-contract.md`](../../linux-bash-scripting/references/common-sh-contract.md).
Zero lines of actual bash exist.

**Why CRITICAL:** without the library, the script template fails on the
very first `source` line. Every script in tier 1 depends on it. It must
be the first file written in the next session.

**Remediation:** implement the functions listed in the contract:
output primitives (`pass`, `warn`, `fail`, `info`, `header`, `die`,
`log`), guards (`require_root`, `require_debian`, `require_cmd`,
`require_flag`), interaction (`confirm`, `confirm_destructive`, `prompt`,
`select_one`), safe file ops (`safe_tempfile`, `safe_tempdir`,
`atomic_write`, `backup_file`), flag parsing (`parse_standard_flags`,
`run`), and the cleanup trap. Target: ~500–700 lines of bash.

**Effort:** 2–3 hours.

---

### C3. `scripts/install-skills-bin` does not exist

**What's missing:** The installer dispatcher that reads `## Scripts`
manifests from `SKILL.md` files and copies `scripts/*.sh` to
`/usr/local/bin/` with the `sk-` prefix. Specified in
[`spec.md §3`](../engine-design/spec.md). Zero lines written.

**Why CRITICAL:** without the installer, Claude Code cannot self-bootstrap
a skill's scripts, and the Hybrid C install model is just a diagram. The
installer is load-bearing for every future demo of the engine.

**Remediation:** implement the 5 sub-commands: `core`, `<skill-name>`,
`all`, `--list`, `--update`, `--uninstall`. Include the manifest parser
(grep-based, per §7 of spec). Target: ~300–500 lines.

**Effort:** 1–2 hours.

---

### C4. No LXD integration test harness

**What's missing:** `scripts/tests/` directory with a test runner that
launches an LXD container, pushes the repo, runs `install-skills-bin
core`, executes a per-script test, and destroys the container. Specified
in [`spec.md §10`](../engine-design/spec.md). Zero lines written.

**Why CRITICAL:** per spec §10, "no `sk-*` script is considered done
until it has a passing integration test." Without the harness, no
script can be declared done. Without the harness, there is no CI. Without
CI, the foundation is unverified and every subsequent script inherits
untested assumptions.

**Remediation:** write a bash or Python test runner that orchestrates
LXD. Each test asserts: `--help` works, `--dry-run` is byte-identical,
real run succeeds, idempotent second run shows zero changes, failure
path exits non-zero with clear error. Target: ~300 lines plus per-script
test files.

**Effort:** 4–6 hours for the harness; 15–30 minutes per script for the
test file.

---

## HIGH gaps

### H1. The foundation has not been smoke-tested end-to-end

**What's missing:** Even once C1–C4 are implemented, the full install
flow (`git clone → install-skills-bin core → sk-audit → correct
output`) has never been run on a clean Ubuntu server. The spec describes
the flow; nobody has walked it.

**Why HIGH:** unverified architectural assumptions compound. Rate of
discovery of design bugs is highest in the first end-to-end walk-through.
If the library interface is awkward, if the manifest parser mis-parses a
table row, if the LXD test harness has a bootstrap bug — all of these
surface on the first end-to-end run.

**Remediation:** after writing common.sh, install-skills-bin, the harness,
and tier-1 scripts 1–5, do a single manual full-stack test: fresh LXD
container → bootstrap → install core → run each tier-1 script → verify
output. Document the result in
[`build-order.md`](build-order.md).

**Effort:** 1–2 hours.

---

### H2. No `shellcheck` CI wiring

**What's missing:** `spec.md §9` rule 15 says "every script passes
`shellcheck` with zero warnings." The tooling to enforce this on every
commit is not configured. No GitHub Actions workflow, no pre-commit
hook.

**Why HIGH:** a rule not enforced is aspirational. Session-to-session,
different agents will produce scripts at different levels of strictness.
Without `shellcheck` in CI, the strictness level drifts downward over
time.

**Remediation:** add `.github/workflows/lint.yml` that runs `shellcheck
scripts/**/*.sh` on every push and PR. Also add a `pre-commit` hook
script for local use. Block merges on failure.

**Effort:** 30 minutes.

---

### H3. Destructive scripts have no rollback verification

**What's missing:** spec rule 9 (destructive operations require
confirmation + audit log), rule 15 (idempotency), and the `backup_file`
function in `common.sh` together give each destructive script a
rollback path. But there is no *test* that proves the rollback path
works. If `sk-harden-ssh` writes a bad config and the verification fails,
does the backup-and-restore path actually restore the original file?

**Why HIGH:** a rollback you haven't tested is not a rollback. In
production, this is how you lock yourself out of a server during
hardening.

**Remediation:** every test for a destructive script (in the LXD
harness) should include a "simulate downstream failure after mutation"
case that asserts the original file state is restored. This becomes a
test pattern used by all destructive-script tests.

**Effort:** a pattern to invent once, ~1 hour. Then 10 minutes per
destructive script test.

---

### H4. No upgrade-path test for `install-skills-bin --update`

**What's missing:** spec §3.3 specifies `install-skills-bin --update`
which does `git pull` then re-installs changed scripts. No test exists
for the "upstream added a new script that didn't exist before" case, the
"upstream changed an existing script" case, the "upstream removed a
script" case, or the "operator edited /usr/local/bin/sk-* manually"
case.

**Why HIGH:** the upgrade path is the single most error-prone part of
any config management system. A broken update = silent divergence
between servers = impossible debugging.

**Remediation:** explicit test cases in the LXD harness for each of the
four update scenarios.

**Effort:** 2 hours.

---

## MEDIUM gaps

### M1. `linux-bash-scripting` references are thin compared to other skills

**Data:** 473 lines of `.md` references, versus 1,000–1,900 for most
other skills.

**Why:** the meta-skill's value is in the `script-template.sh` file (not
counted by `wc -l` on `.md` files) and the short `common-sh-contract.md`
and `interactive-ux.md`. Adding more prose here risks duplicating content
from `spec.md`.

**Severity: MEDIUM** — the skill is functional as-is but could benefit
from a "common bash idioms" reference (parameter expansion cheatsheet,
trap handler patterns, signal handling, process substitution tricks)
that consolidates Pro Bash content not yet written down.

**Remediation:** add `linux-bash-scripting/references/idioms.md`
(300–500 lines) covering the book content from Pro Bash and Vickler not
already in the spec or common.sh contract. Deferred until after the
script layer is built (this is polish).

**Effort:** 1 hour.

---

### M2. `linux-troubleshooting` has only one reference file (1 vs 2–3 elsewhere)

**Data:** 1 file, 833 lines (the expanded `diagnosis-tree.md`). Most
other skills have 2 or 3 reference files.

**Why:** when I expanded it manually after the wave-2 agent rate-limited,
I consolidated into one long file rather than splitting across multiple
smaller ones. The 833 lines are book-quality, but a second file
(`common-signatures.md`) that catalogues repeated error strings →
root-cause mapping would strengthen it.

**Severity: MEDIUM.**

**Remediation:** write `linux-troubleshooting/references/common-signatures.md`
(300–450 lines). Error string in left column, root cause and fix on
the right. Deferred.

**Effort:** 1.5 hours.

---

### M3. `linux-network-admin` references trimmed by agent to hit budget

**Data:** 947 lines across 2 files. The diagnostics-tree file was
trimmed from ~607 to 450 lines by the agent during its re-run pass to
hit target.

**Why:** agents self-trimmed to hit line budgets. The content is still
complete, but some example YAML and annotation was lost.

**Severity: MEDIUM.**

**Remediation:** review the two files; if anything feels under-annotated,
expand it. Deferred — not blocking.

**Effort:** 30 minutes.

---

### M4. No example `## Scripts` manifest has been parsed by any tool

**What's missing:** spec §7 defines the `## Scripts` manifest format
(a markdown table parsed by grep). Every SKILL.md has this section
populated with ~88 entries total. But the parser (part of
`install-skills-bin`, not yet written) has never read a single one. If
the format has an ambiguity — a dash in a purpose line that confuses a
`---` separator detector, a pipe in a purpose line that breaks column
splitting — we won't find out until the first `install-skills-bin` run.

**Severity: MEDIUM.**

**Remediation:** when building the installer, the first test should be
parsing every existing SKILL.md manifest. Any parse error is a format
spec bug; fix the spec and the SKILL.md, not the parser.

**Effort:** part of building `install-skills-bin` (no extra time).

---

### M5. No example cloud-init user-data for a real deployment has been tested

**Data:** `linux-cloud-init/references/user-data-reference.md` has 5
complete worked templates (web server, Docker host, LXD guest, Postgres,
linux-skills bootstrap). None have been boot-tested.

**Why MEDIUM:** cloud-init is unforgiving of small YAML errors. The
templates are well-written against the Canonical Ubuntu Server Guide,
but nothing catches "this line has a tab instead of spaces" until
cloud-init runs.

**Remediation:** when the script layer is being built, test the
linux-skills bootstrap user-data by launching a disposable LXD
container with `lxc launch ubuntu:24.04 test --config=user.user-data="$(cat user-data.yaml)"`.
Document the result. Fix any template errors.

**Effort:** 30 minutes per template, 2.5 hours total.

---

## LOW gaps

### L1. No cross-referencing index between skills

**What's missing:** a master index that shows which skills reference
which others. The content is there (every skill has a "See also"
section), but there's no generated map. A human reading the repo for the
first time would benefit from a visual "these 8 skills all route to
`linux-access-control` for SSH keys" diagram.

**Severity: LOW.** Readability polish.

**Remediation:** `docs/analysis/skills-coverage.md` (this session) partly
addresses this with a table. A graphviz diagram would be nicer. Deferred
— not blocking anything.

**Effort:** 1 hour.

---

### L2. No AGENTS.md / AGENTS registry

**What's missing:** a `AGENTS.md` file in the repo root telling future
Claude sessions how this repo is structured, what conventions apply, and
which memory rules are standing. Partially covered by `CLAUDE.md` but
specific to Claude Code.

**Severity: LOW.** The CLAUDE.md file is enough for now.

**Remediation:** if the project spreads to Cursor, VS Code Copilot, or
Gemini CLI, add `AGENTS.md` as the cross-platform equivalent.

**Effort:** 15 minutes.

---

### L3. No snapshot of a successful multi-skill workflow

**What's missing:** a "day in the life" reference document showing how a
sysadmin (or Claude) combines multiple skills in a single incident
response. E.g., "disk filled at 03:14 → `linux-disk-storage` identified
culprit → `linux-log-management` rotated the runaway → `linux-observability`
added an alert to prevent recurrence → commit to git via
`linux-config-management`."

**Severity: LOW.** Nice-to-have for the book, not required for the
engine to work.

**Remediation:** write `docs/analysis/worked-examples.md` covering 3–5
multi-skill workflows. Deferred.

**Effort:** 2 hours.

---

### L4. No performance benchmarks for the scripts

**What's missing:** spec §9 rule 15 covers *correctness* (idempotent,
safe). It doesn't cover performance. `sk-audit` on a 100k-file web root,
`sk-disk-hogs /`, `sk-file-integrity-check` on a large `/etc` — these
could be slow, and nobody has measured.

**Severity: LOW.** Performance will matter once the scripts are in daily
use. Not blocking.

**Remediation:** add a `time <script>` assertion to each integration
test, with a reasonable upper bound. Deferred until the scripts exist.

**Effort:** 15 minutes per script, part of test writing.

---

## Closed since last analysis

*(This section grows with every session. An empty "Closed" section means
no gaps have been resolved yet.)*

- *None yet — this is the first analysis.*
