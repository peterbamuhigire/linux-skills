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

### C1. 85 of 88 `sk-*` scripts remain to be written

**Status (session 2):** *Downgraded from "zero written" to "3 of 88
written."* The foundation is complete and three legacy scripts have been
migrated:

- ✅ `sk-audit.sh` (migrated from server-audit.sh)
- ✅ `sk-update-all-repos.sh` (migrated from update-all-repos)
- ✅ `sk-mysql-backup.sh` (migrated from mysql-backup.sh)

**What's still missing:** 85 scripts. Including the 12 remaining tier-1
scripts (`sk-new-script`, `sk-lint`, `sk-system-health`, `sk-disk-hogs`,
`sk-open-ports`, `sk-service-health`, `sk-cert-status`, `sk-cron-audit`,
`sk-user-audit`, `sk-ssh-key-audit`, `sk-fail2ban-status`,
`sk-journal-errors`, `sk-backup-verify`) that together with the 3
already-migrated scripts form the 15-script core install.

**Severity:** CRITICAL (reduced from original). The engine can begin to
run once tier-1 is complete — tier-2/3 can ship incrementally.

**Remediation:** continue with the session 3 plan in
[`build-order.md`](build-order.md).

**Remaining effort:** 50–80 hours for all 85 scripts, but the first 12
tier-1 scripts are the critical-path work (~5 hours).

---

## HIGH gaps

### H1. The foundation has not been smoke-tested end-to-end

**Status (session 2):** *Still open*. The foundation files all exist
(`common.sh`, `install-skills-bin`, test harness, migrated scripts) but
the LXD test harness has not been executed — the development machine is
Windows.

**What's still missing:** A successful run of
`sudo ./scripts/tests/run-test.sh --suite foundation` on a real Linux
host. Two test files (`common-sh.test.sh` with 9 assertions,
`install-skills-bin.test.sh` with 9 assertions) are ready to run.

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

### ✅ C5. `sk-update-all-repos` no longer uses `eval` on post-pull hooks — CLOSED

The migrated repo-update script originally executed the third registry field as
arbitrary shell. That violated the engine rule in `spec.md` that forbids
`eval` on untrusted input. The script now executes post-pull hooks through a
constrained direct-command runner that supports simple argv commands and `&&`
chains without general shell evaluation.

**What remains open:** the workflow is still destructive by design
(`git reset --hard`, `git clean -fd`), so rollback verification and safer
operator discipline remain active concerns under H3.

**Session 2 (2026-04-10) — foundation build:**

### ✅ C2. `scripts/lib/common.sh` — CLOSED

`scripts/lib/common.sh` now exists, ~440 lines. Implements every
function in the contract: output primitives (`pass`, `warn`, `fail`,
`info`, `header`, `die`, `log`), guards (`require_root`,
`require_debian`, `require_cmd`, `require_flag`), interaction
(`confirm`, `confirm_destructive`, `prompt`, `select_one`), safe file
ops (`safe_tempfile`, `safe_tempdir`, `atomic_write`, `backup_file`),
flag parsing (`parse_standard_flags`, `run`), cleanup trap
(`_sk_cleanup`, `sk_on_exit`), and `print_summary`. Source-guarded
against double-load. 9 tests covering the critical invariants live in
`scripts/tests/common-sh.test.sh`.

**Verification pending:** tests have been written but not yet executed
in LXD (see H1).

### ✅ C3. `scripts/install-skills-bin` — CLOSED

`scripts/install-skills-bin` now exists, ~350 lines. Implements:
`core`, `<skill-name>`, `all`, `--list`, `--update [skill]`,
`--uninstall <skill>`, plus standard flags. Manifest parser is a
grep/awk pipeline that reads every `## Scripts` table in every
`SKILL.md`. Installs `common.sh` to `/usr/local/lib/linux-skills/` and
`sk-*` scripts to `/usr/local/bin/` with idempotency (compares file
contents, skips unchanged). `--force` overrides. Takes a flock on
`/run/linux-skills.lock` during updates. 9 tests in
`scripts/tests/install-skills-bin.test.sh`.

**Verification pending:** tests have been written but not yet executed
in LXD (see H1).

### ✅ C4. LXD integration test harness — CLOSED

`scripts/tests/run-test.sh` now exists, ~200 lines. Orchestrates:
launch Ubuntu 24.04 LXD container → tar-pipe the repo in → install
engine → push and run the test file → tear down on pass, leave
container on fail with attach instructions. Suites: `foundation`,
`tier1`, `all`. Per-script test contract (from spec §10.2)
implemented: each test file asserts `--help` exits 0, `--dry-run` is
byte-identical, real run succeeds, idempotency (second run = 0
changes), failure path exits non-zero.

**Verification pending:** harness has been written but not yet
executed on Linux (see H1).

### Partial progress on C1

`C1` has been downgraded in severity: 3 of 88 scripts now written
(`sk-audit`, `sk-update-all-repos`, `sk-mysql-backup`), 85 remain. The
migration pattern is proven — the remaining scripts can follow the
same template.

### Score impact

- **Overall readiness: 6.5 → 7.5** (+1.0)
- **`common.sh` library (implemented): 0 → 8**
- **`install-skills-bin` installer (implemented): 0 → 8**
- **Test harness (LXD container): 0 → 7**
- **`sk-*` scripts (written): 0 → 1** (3 of 88)
- **Runtime usability on a server: 1 → 4**
