# Build order

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The recommended phase-by-phase work plan to move `linux-skills` from a
knowledge base to a working engine. This is the concrete, sequential
playbook for the next sessions. Every phase ends with an exit criterion
that must be green before moving to the next.

**Prime directive:** build the foundation first. Do not write feature
scripts until the foundation is proven. If the foundation is broken,
fix it before writing more scripts — every subsequent script inherits
its bugs.

## Table of contents

- [Phase 0: Pre-flight](#phase-0-pre-flight)
- [Phase 1: Foundation](#phase-1-foundation)
- [Phase 2: Tier 1 scripts 1–5 (foundation proof)](#phase-2-tier-1-scripts-15-foundation-proof)
- [Phase 3: Tier 1 completion (scripts 6–15)](#phase-3-tier-1-completion-scripts-615)
- [Phase 4: Tier 2 by theme](#phase-4-tier-2-by-theme)
- [Phase 5: Tier 3 on demand](#phase-5-tier-3-on-demand)
- [Phase 6: Publishing + polish](#phase-6-publishing--polish)
- [Time estimates](#time-estimates)
- [Out-of-order work that can happen in parallel](#out-of-order-work-that-can-happen-in-parallel)

---

## Phase 0: Pre-flight

Before writing any code, lock down the environment and assumptions.

### Checklist

- [ ] **Target Ubuntu version chosen.** Default: 24.04 LTS. Document in
      `spec.md` §11 under a new "Target platform" subsection.
- [ ] **LXD installed on the development machine.** `sudo snap install
      lxd; sudo lxd init --auto` (or full `lxd init` for storage choices).
- [ ] **`shellcheck` installed.** `sudo apt install shellcheck`.
- [ ] **Test image pulled.** `lxc launch ubuntu:24.04 warmup; lxc stop
      warmup` (first launch caches the image).
- [ ] **Repo is clean and committed.** `git status` shows nothing
      pending.
- [ ] **This analysis is committed.** Future sessions see the current
      state.

### Exit criterion

Every box above is checked. You can launch a fresh Ubuntu 24.04
container in under 30 seconds.

---

## Phase 1: Foundation

The foundation is three artifacts that must all exist before any
tier-1 script can be written.

### 1A. `scripts/lib/common.sh`

**Deliverable:** `scripts/lib/common.sh`, ~500–700 lines, implementing
every function in the contract at
[`linux-bash-scripting/references/common-sh-contract.md`](../../linux-bash-scripting/references/common-sh-contract.md).

**Order of implementation within the file:**

1. Globals and color initialization.
2. Output primitives (`pass`, `warn`, `fail`, `info`, `header`, `die`,
   `log`).
3. The cleanup trap.
4. Flag parsing (`parse_standard_flags` and the standard flag set).
5. Guards (`require_root`, `require_debian`, `require_cmd`,
   `require_flag`).
6. Safe file operations (`safe_tempfile`, `safe_tempdir`, `atomic_write`,
   `backup_file`).
7. Interaction (`confirm`, `confirm_destructive`, `prompt`, `select_one`).
8. `run` wrapper (command echo + dry-run support).

**Tests to write for common.sh itself (not against `sk-*` scripts):**

- `--yes` + missing `require_flag` → exits 2 with clear message.
- `--dry-run` + `run sudo foo` → prints but skips.
- `safe_tempfile` + normal exit → temp file removed.
- `safe_tempfile` + Ctrl-C → temp file still removed (trap fires).
- `atomic_write` over an existing file → permissions and owner
  preserved.
- `confirm_destructive` in interactive mode → rejects `y`, accepts `yes`.
- `confirm_destructive` in `--yes` mode without a decision flag →
  refuses to auto-confirm.

**Effort:** 2–3 hours.

### 1B. `scripts/install-skills-bin`

**Deliverable:** `scripts/install-skills-bin`, ~300–500 lines.

**Sub-commands to implement in order:**

1. `--list` — lists available skills and whether each is installed.
2. `<skill-name>` — installs one skill's scripts.
3. `core` — installs all tier-1 scripts.
4. `all` — installs everything (opt-in, for golden images).
5. `--uninstall <skill-name>` — removes a skill's scripts.
6. `--update [skill-name]` — the upgrade path from spec §3.3.

**Key sub-component:** the manifest parser that reads `## Scripts`
tables from every `SKILL.md`. Write it first as a standalone function,
test against every existing SKILL.md, then integrate.

**Tests:**

- Parser reads every existing `SKILL.md` without errors.
- `install-skills-bin core` on a fresh container installs all 15 tier-1
  scripts to `/usr/local/bin/` mode 0755.
- `install-skills-bin linux-webstack` installs just the webstack scripts.
- `install-skills-bin --list` matches reality.
- `install-skills-bin --update` no-op when nothing has changed.

**Effort:** 1–2 hours.

### 1C. `scripts/tests/` — LXD integration test harness

**Deliverable:** `scripts/tests/run-test.sh` (the harness) plus one test
file per tier-1 script (`scripts/tests/sk-audit.test.sh`, etc.).

**Harness responsibilities:**

1. Launch a fresh LXD container (`lxc launch ubuntu:24.04 sk-test-<rand>`).
2. Push the repo into the container (`lxc file push`).
3. Run `install-skills-bin core` inside.
4. Execute the test file for the script under test.
5. On pass, destroy the container.
6. On fail, leave the container running and print
   `lxc exec sk-test-<name> -- bash` so the operator can attach.
7. Overall summary at the end: N pass, M fail.

**Per-script test contract** (from spec §10.2):

1. `--help` exits 0 and contains every decision flag.
2. `--dry-run` runs end-to-end, changes nothing (byte-diff check).
3. Real run (with `--yes` + flags) achieves the intended state, exits 0.
4. Idempotency: second real run reports "0 changes" and exits 0.
5. Failure path: one deliberately broken input exits non-zero with a
   clear error.

**Effort:** 4–6 hours for the harness + first test file; 15 minutes
per subsequent test file.

### Exit criterion for Phase 1

- [ ] `scripts/lib/common.sh` exists, passes `shellcheck` with zero
      warnings.
- [ ] `scripts/install-skills-bin` exists, passes `shellcheck`, parses
      every `SKILL.md` without error.
- [ ] `scripts/tests/run-test.sh` exists, can launch and tear down an
      LXD container cleanly.
- [ ] `common.sh` self-tests all pass.

---

## Phase 2: Tier 1 scripts 1–5 (foundation proof)

Build the first five tier-1 scripts against the foundation. Do not
proceed to scripts 6–15 until these five pass integration tests in LXD.

### Script order (and rationale)

1. **`sk-audit`** — migrate from the existing `scripts/server-audit.sh`.
   - Rename to `scripts/sk-audit.sh`.
   - Replace inline color/output helpers with `common.sh` functions.
   - Add the six-section template header.
   - Keep the existing 14 audit sections verbatim.
   - Add `--json` output mode (new requirement from spec §5).
   - This is the **smoke test for `common.sh`**: can an existing working
     script be refactored onto the library cleanly? If not, fix
     `common.sh`.
2. **`sk-update-all-repos`** — rename from `scripts/update-all-repos`
   to `scripts/sk-update-all-repos.sh`. Minimal changes: wrap the
   existing menu in the standard flag handling so `--yes --all` works
   from Claude Code. Keep interactive behavior for humans. Tests:
   script runs on a container with no repos configured without error.
3. **`sk-new-script`** — creates a new `sk-*` script from the template.
   Takes `--skill <name> --name <script>`. Copies the template to
   `<skill-dir>/scripts/<name>.sh`, substitutes placeholders, runs
   `shellcheck` on the result. This is the tool that makes writing
   scripts 6–88 much faster.
4. **`sk-lint`** — runs `shellcheck` plus custom engine checks (the
   script sources `common.sh`, does not use `set -e`, includes the
   six-section header, `--help` exits 0). Tests: clean scripts pass,
   dirty scripts fail with useful output.
5. **`sk-system-health`** — one-screen snapshot of load, CPU, memory,
   disk, swap, top processes. Read-only, idempotent by construction
   (no state changes), straightforward to test. Good first "real
   feature" script that exercises output primitives heavily.

### Exit criterion for Phase 2

- [ ] All 5 scripts installed via `install-skills-bin core` on a fresh
      LXD container.
- [ ] All 5 scripts pass their per-script integration test.
- [ ] `shellcheck` clean on all 5 + `common.sh` + installer + harness.
- [ ] Manual smoke test: operator runs each script from bash
      interactively and confirms output is sensible.
- [ ] **Real-VM test**: run the foundation smoke test on a fresh cloud
      VM (DigitalOcean droplet or Hetzner Cloud), not just LXD, to
      confirm the LXD environment isn't hiding bugs.

If any of these fail: **stop**. Fix the foundation (common.sh or
installer) before writing more scripts. Update the spec if a design
decision needs to change. Update this file with lessons learned.

---

## Phase 3: Tier 1 completion (scripts 6–15)

With the foundation proven, build the remaining 10 tier-1 scripts. These
can be written in parallel (one per Claude session, or dispatched as
sub-agents). Each still follows the full per-script test contract.

| # | Script | Skill | Complexity |
|---|---|---|---|
| 6 | sk-disk-hogs | linux-disk-storage | low |
| 7 | sk-open-ports | linux-system-monitoring | low |
| 8 | sk-service-health | linux-service-management | low |
| 9 | sk-cert-status | linux-firewall-ssl | low |
| 10 | sk-cron-audit | linux-service-management | medium |
| 11 | sk-user-audit | linux-access-control | medium |
| 12 | sk-ssh-key-audit | linux-access-control | medium |
| 13 | sk-fail2ban-status | linux-intrusion-detection | low |
| 14 | sk-journal-errors | linux-log-management | low |
| 15 | sk-backup-verify | linux-disaster-recovery | medium |

### Exit criterion for Phase 3

- [ ] All 15 tier-1 scripts installed by `install-skills-bin core`.
- [ ] All 15 pass integration tests.
- [ ] A fresh LXD container running `install-skills-bin core` then
      every `sk-*` script in sequence produces clean output and zero
      stack traces.
- [ ] `docs/analysis/README.md` updated with a new revision row:
      "tier 1 complete, N scripts shipped, M findings from testing."

---

## Phase 4: Tier 2 by theme

Tier 2 is 46 scripts. Build them theme by theme, not script by script,
so each theme is coherent and testable as a group.

### Build order for themes (by safety criticality, highest-risk first)

1. **Hardening & access control (11 scripts)**
   - `sk-harden-ssh`, `sk-harden-sysctl`, `sk-harden-php`
   - `sk-ufw-reset`, `sk-ufw-audit`
   - `sk-cert-renew`, `sk-apparmor-status`
   - `sk-new-sudoer`, `sk-user-suspend`
   - `sk-file-integrity-init`, `sk-file-integrity-check`
   - **Every one of these is destructive.** Extra-careful LXD testing
     with rollback verification. Real-VM testing before claiming done.
2. **Web stack & site deployment (10 scripts)**
   - `sk-nginx-new-site`, `sk-nginx-test-reload`
   - `sk-apache-new-site`, `sk-apache-test-reload`
   - `sk-php-fpm-pool`
   - `sk-astro-deploy`, `sk-php-site-deploy`, `sk-static-site-deploy`
   - `sk-access-log-report`, `sk-error-log-report`
3. **Databases & backups (9 scripts)**
   - `sk-mysql-backup` (migrate from existing), `sk-mysql-restore`
   - `sk-mysql-tune`, `sk-mysql-user-audit`
   - `sk-postgres-backup`, `sk-postgres-restore`
   - `sk-site-backup`, `sk-site-restore`
   - `sk-config-snapshot`
4. **Services, disk, troubleshooting (11 scripts)**
   - `sk-service-restart`, `sk-timer-list`
   - `sk-disk-cleanup`, `sk-inode-check`, `sk-swap-check`
   - `sk-load-investigate`, `sk-why-slow`, `sk-why-500`,
     `sk-why-cant-connect`
   - `sk-journal-tail`, `sk-logrotate-check`
5. **Provisioning & packages (5 scripts)**
   - `sk-provision-fresh`
   - `sk-apt-update-safe`, `sk-apt-upgrade-safe`
   - `sk-unattended-status`, `sk-snap-audit`

### Exit criterion per theme

- [ ] Every script in the theme installed by `install-skills-bin
      <skill>`.
- [ ] Every script passes integration tests.
- [ ] Every destructive script's rollback path verified.
- [ ] `docs/analysis/gaps.md` updated: any gap the theme revealed is
      documented.
- [ ] Theme commit: `feat: tier-2 <theme> — N scripts`.

---

## Phase 5: Tier 3 on demand

Tier 3 is 27 scripts for specialized servers (mail, DNS, virtualization,
cloud-init, observability, secrets, config management). Build them
**only when a server that needs them exists**. These ship as per-skill
lazy installs, never core.

Reason: tier 3 is where the highest risk of ongoing maintenance lives.
Building them speculatively means maintaining code no one uses.

### Recommended build triggers

- First real mail server → build Theme H (mail-server, 4 scripts).
- First real virtualization host → Theme I (virtualization, 4 scripts).
- First real observability stack → Theme K (observability, 3 scripts)
  + Theme K (config-management, 3 scripts).
- First real DNS server → Theme G (dns-server, 2 scripts).
- First cloud-init deployment → Theme J (cloud-init, 2 scripts).

### Exit criterion

Tier 3 has no single exit criterion — it's built on demand. When all 27
are built and tested, mark the engine 1.0 feature-complete.

---

## Phase 6: Publishing + polish

Once the 88 scripts are all built and tested, the engine is
feature-complete but not finished. Polish work:

1. **Book-preparation pass.** Each skill's `SKILL.md` and `references/`
   files are book chapters. Run a polish edit for voice consistency,
   example quality, annotation density. Not a content change — a
   writing pass.
2. **Generate a one-page PDF cheat-sheet** listing every `sk-*` script
   with its one-line purpose. Useful operator reference.
3. **Record a 5-minute demo video** of `install-skills-bin core` on a
   fresh VM followed by the top 5 most useful tier-1 scripts. Embed in
   the README.
4. **Publish the book.** Out of scope for this repo (per the book goal
   memory), but the content is ready.

---

## Time estimates

These are good-faith estimates assuming focused AI-assisted work.

| Phase | Work | Estimate |
|---|---|---|
| 0 | Pre-flight | 1 hour |
| 1A | `common.sh` | 3 hours |
| 1B | `install-skills-bin` | 2 hours |
| 1C | LXD test harness | 5 hours |
| 1 total | Foundation | **~11 hours** |
| 2 | Tier 1 scripts 1–5 + foundation proof | **~4 hours** |
| 3 | Tier 1 scripts 6–15 | **~5 hours** |
| 4 | Tier 2 (46 scripts) | **~25–35 hours** |
| 5 | Tier 3 (27 scripts, staggered over weeks) | **~15–20 hours cumulative** |
| 6 | Publishing + polish | **~10 hours** |
| **Total** | | **~70–90 hours** |

This is aligned with the critique earlier in the session ("50–80 hours of
coding away from a working engine"). The difference is that book-ready
polish adds ~10 hours of additional editing time at the end.

Session estimates:

- **Session 1 (foundation):** phases 0 + 1 + 2 = ~16 hours. Realistically
  2–3 sessions.
- **Session 2 (tier 1 completion):** phase 3 = ~5 hours. 1 session.
- **Sessions 3–8 (tier 2):** phase 4 = 25–35 hours across 5–6 sessions,
  one per theme.
- **Sessions 9+ (tier 3):** as demand drives it.

---

## Out-of-order work that can happen in parallel

While the main thread is building scripts, some work can happen in
parallel without blocking:

- **Filling gap M1** (bash idioms reference) — 1 hour, any session.
- **Filling gap M2** (troubleshooting common signatures) — 1.5 hours,
  any session.
- **Deepening `linux-network-admin` references** if they're found
  thin — 30 minutes.
- **Adding worked examples** (gap L3) — 2 hours.
- **Updating this readiness analysis** after each session — 30 minutes.
- **Creating `AGENTS.md`** for cross-platform AI compatibility — 15
  minutes.

None of these block the main script-generation work. They are good
candidates for "fill a short gap while waiting for a test to finish."

---

## Rules for every future session

1. **Start by reading `docs/analysis/README.md`** to know the current
   state.
2. **End by updating `docs/analysis/README.md`** with a new revision
   history row summarizing what changed.
3. **Never write a script without its test.**
4. **Never skip the integration test.**
5. **Never claim a script is done without running it in LXD and on a
   real VM.**
6. **Honor the memory rules** — they exist because past sessions
   learned things the hard way.
7. **Commit often.** The session might end unexpectedly; small commits
   are recoverable.
8. **Update `gaps.md`** when you discover a new gap — immediately, not
   "later."
