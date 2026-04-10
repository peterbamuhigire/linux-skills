# Risks

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

What can go wrong as we move from the skill layer to the script layer,
and how to mitigate. This is not a list of every bug that could ever
occur — it's the specific risks that arise *because* of the architectural
decisions in the current spec.

Every risk is tagged with a likelihood (L/M/H), impact (L/M/H), and a
mitigation.

## Table of contents

- [R1. common.sh interface is awkward to use in practice](#r1-commonsh-interface-is-awkward-to-use-in-practice)
- [R2. The `--yes` contract is too strict and frustrates operators](#r2-the---yes-contract-is-too-strict-and-frustrates-operators)
- [R3. Idempotency is hard to verify automatically](#r3-idempotency-is-hard-to-verify-automatically)
- [R4. Destructive scripts lock operators out of production servers](#r4-destructive-scripts-lock-operators-out-of-production-servers)
- [R5. LXD test harness doesn't match production reality](#r5-lxd-test-harness-doesnt-match-production-reality)
- [R6. Ubuntu version drift breaks documented commands](#r6-ubuntu-version-drift-breaks-documented-commands)
- [R7. The `SKILL.md` manifest parser chokes on edge cases](#r7-the-skillmd-manifest-parser-chokes-on-edge-cases)
- [R8. `install-skills-bin --update` creates silent divergence](#r8-install-skills-bin---update-creates-silent-divergence)
- [R9. Scripts and skills drift out of sync over time](#r9-scripts-and-skills-drift-out-of-sync-over-time)
- [R10. Book source material ages out](#r10-book-source-material-ages-out)
- [R11. 88 scripts is more maintenance than one operator can sustain](#r11-88-scripts-is-more-maintenance-than-one-operator-can-sustain)
- [R12. `shellcheck` strictness pushes developers toward workarounds](#r12-shellcheck-strictness-pushes-developers-toward-workarounds)

---

## R1. common.sh interface is awkward to use in practice

**Likelihood:** M. **Impact:** H.

**Risk:** The `common.sh` contract at
[`common-sh-contract.md`](../../linux-bash-scripting/references/common-sh-contract.md)
specifies ~25 functions with specific signatures. When we actually start
writing scripts, some will feel clunky — the `select_one` menu may
return awkwardly, `parse_standard_flags` may be hard to extend for
script-specific flags, `atomic_write` may not compose with stdin
pipelines cleanly.

Writing the contract without writing a single caller is a risk: theory
only survives contact with practice.

**Mitigation:**

1. **Build tier-1 scripts 1–5 together with `common.sh`.** Do not
   declare common.sh "done" until at least 5 scripts have been written
   against it and work correctly.
2. **Accept that `common.sh` will be revised once the first scripts
   ship.** This is not a failure mode — it's the only way to get the
   interface right. Document every revision in the spec.
3. **Treat `common-sh-contract.md` as an aspirational first draft, not
   a binding contract.** Update both the library and the contract
   together when something changes.

---

## R2. The `--yes` contract is too strict and frustrates operators

**Likelihood:** M. **Impact:** M.

**Risk:** The rule "`--yes` never picks a default, always requires the
caller to specify every required decision" is correct for AI agents but
may feel burdensome for a human admin who just wants to
`sudo sk-harden-ssh --yes` and have it Just Work. If human operators
learn to avoid `--yes` and always run interactively, the scripts don't
behave consistently between operator use and CI use.

**Mitigation:**

1. **Keep the rule.** It's load-bearing for AI invocation.
2. **Make `--help` carry its weight.** Every decision flag must be
   listed, with the default if the script were interactive, so the human
   can glance at `--help` and construct a one-liner.
3. **Provide `sk-<name> --yes-with-defaults` as an opt-in escape valve**
   ONLY for scripts where all decisions have safe production defaults.
   Audit each such script carefully. This is explicit and surveilled,
   not silent.
4. **Document the rule prominently in `linux-bash-scripting/SKILL.md`**
   so operators understand *why* they have to pass flags.

---

## R3. Idempotency is hard to verify automatically

**Likelihood:** M. **Impact:** M.

**Risk:** Spec rule 15 says every mutating script must be idempotent.
The LXD test harness checks this by running the script twice and
asserting "second run shows zero changes." But "zero changes" is fuzzy
— how does the test know? A script that writes the same line with a
timestamp in it will pass a naive diff-check but still be non-idempotent
from a human perspective. A script that regenerates a config file with
reordered keys will "show changes" in a byte-diff but be semantically
idempotent.

**Mitigation:**

1. **Define idempotency precisely in the test harness:** "the script
   exits 0 on the second run, and the visible system state (which is
   script-specific) is unchanged." For each script, document *which*
   state files to check.
2. **Use `--dry-run` on the second run.** A script with a correctly
   implemented `--dry-run` will report "0 changes needed" on a
   re-invocation, which is a stricter test than filesystem diff.
3. **Snapshot-diff the relevant paths,** not the whole `/etc`. E.g. for
   `sk-harden-ssh`, diff only `/etc/ssh/sshd_config*` before and after.
4. **Catch "silent drift"** where a script writes no file change but
   does restart a service. Test the restart count too.

---

## R4. Destructive scripts lock operators out of production servers

**Likelihood:** M. **Impact:** CRITICAL.

**Risk:** The most dangerous scripts in the inventory are `sk-harden-ssh`,
`sk-ufw-reset`, `sk-harden-sysctl`, `sk-file-integrity-init`, and the
`sk-*-restore` scripts. A bug in any of them can cost access to the
server — a locked-out admin, a firewalled SSH port, a kernel setting that
breaks networking.

**Mitigation:**

1. **Every destructive script has `backup_file` before the mutation
   and a rollback path if verification fails.** Enforced by
   `common.sh` design.
2. **Every destructive script tests its reload validator BEFORE
   reloading.** `sshd -t` before `systemctl restart ssh`. `nginx -t`
   before `nginx -s reload`.
3. **`sk-ufw-reset` never resets via SSH without first opening the new
   SSH rule and verifying it works.** Specific rule: the new profile is
   built, `ufw --dry-run enable` is run, the operator's current SSH
   source IP is explicitly allowed, THEN enable.
4. **Every destructive script has a timed rollback option.** Similar to
   `netplan try`: apply, wait 120s for a `continue` command, auto-revert
   if no confirmation. (This is a pattern to add to `common.sh`:
   `with_timed_revert`.)
5. **Every destructive test in LXD simulates a downstream failure** and
   asserts the rollback restores the original state. See
   [gaps.md H3](gaps.md#h3-destructive-scripts-have-no-rollback-verification).

---

## R5. LXD test harness doesn't match production reality

**Likelihood:** M. **Impact:** M.

**Risk:** LXD containers are not quite the same as real Ubuntu servers.
Differences:

- Systemd in a container has a restricted cgroup view.
- Networking is bridged, not physical.
- Kernel modules can't be loaded inside an unprivileged container.
- `sysctl` writes are limited in unprivileged containers.
- Disk is typically ZFS-backed — different performance profile.

Scripts that pass LXD tests may still fail on a real VPS.

**Mitigation:**

1. **Use LXD for fast development-cycle tests** (seconds per run).
2. **Also run the foundation smoke test on a real fresh cloud VM**
   once before declaring tier 1 done. Document in
   [`build-order.md`](build-order.md) §2.
3. **For scripts that interact with kernel modules or sysctl
   aggressively** (e.g. `sk-harden-sysctl`), run those in a privileged
   LXD container AND on a real VM.
4. **For scripts that interact with the network stack**
   (`sk-netplan-apply`, `sk-ufw-reset`), require a real VM for the
   acceptance test.

---

## R6. Ubuntu version drift breaks documented commands

**Likelihood:** H over 2–3 years. **Impact:** M.

**Risk:** The reference material is anchored to Ubuntu 22.04 / 24.04.
When 26.04 LTS ships, some commands will move (already saw this with
`ifconfig` → `ip`, `iptables` → `nftables`, `apt-key` → `gpg` +
`/etc/apt/keyrings/`). Scripts that hard-code commands will break.

**Mitigation:**

1. **`require_debian` in `common.sh` reads `/etc/os-release`** and can
   gate by VERSION_CODENAME. Scripts that depend on specific version
   features declare it explicitly:
   ```bash
   require_debian --min-version=22.04
   ```
2. **Prefer long-lived abstractions.** Use `systemctl` not raw
   `/etc/init.d/`. Use `ip` not `ifconfig`. Use `ss` not `netstat`. Use
   `/etc/apt/keyrings/` not `apt-key`.
3. **Pin to current stable in reference files,** with a "Ubuntu 22.04+"
   note at the top. When 26.04 ships, revisit each skill in a
   scheduled review (not ad-hoc).
4. **Memory rule already in place:** `feedback_scripts_follow_skills.md`
   ensures that when a skill is updated for a new Ubuntu version, the
   scripts are updated in the same session. This rule must be honored.
5. **Add a `version-compat.md` reference file** to `linux-bash-scripting`
   documenting the specific version guards and their rationale.

---

## R7. The `SKILL.md` manifest parser chokes on edge cases

**Likelihood:** M. **Impact:** L.

**Risk:** Spec §7 defines the `## Scripts` manifest as a markdown table
parsed by grep/awk. Edge cases that could break it:

- A script purpose line containing a literal `|` (pipe).
- A script purpose line containing a backtick or HTML entity.
- Multi-line cell content in a table.
- Unicode characters (em-dashes, curly quotes).
- Trailing whitespace on the separator row.
- A `## Scripts` heading inside a code block that the parser mistakes
  for a real section.

**Mitigation:**

1. **Write a strict parser and test it against every existing `SKILL.md`
   manifest as the first validation step in `install-skills-bin`.** Any
   parse error is a format spec bug; fix the spec AND the offending
   SKILL.md, don't loosen the parser.
2. **Audit all existing manifests** for the edge cases above before
   building the parser. Use a one-off script:
   ```bash
   for f in linux-*/SKILL.md; do
       awk '/^## Scripts/{flag=1; next} /^## /{flag=0} flag && /^\|/' "$f" \
           | grep -nE '`|\|.*\|.*\|.*\|.*\|' || true
   done
   ```
3. **Never allow `|` in a purpose line.** Use "or" instead. Documented
   constraint in spec §7.

---

## R8. `install-skills-bin --update` creates silent divergence

**Likelihood:** M. **Impact:** M.

**Risk:** `install-skills-bin --update` does `git pull` then reinstalls
scripts. Failure modes:

- Git pull fails (merge conflict because operator edited a file locally
  in the cloned repo) — installer continues with stale scripts.
- `common.sh` changed upstream but `install-skills-bin` forgets to
  refresh `/usr/local/lib/linux-skills/common.sh`.
- A script was renamed upstream (`sk-audit` → `sk-security-audit`); the
  old copy lingers in `/usr/local/bin/`.
- A script was removed upstream; it stays in `/usr/local/bin/`.
- Upgrading during a cron-scheduled run on another script causes both
  to fail.

**Mitigation:**

1. **`install-skills-bin --update` takes a lock.** `flock` on a file in
   `/run/linux-skills.lock`. Cron jobs fail gracefully if another update
   is running.
2. **After `git pull`, the installer diffs the `scripts/` directory**
   and reports what changed (added, removed, renamed) before applying.
3. **Renamed scripts** are detected by the installer (old script has
   `## Source: scripts/old-name.sh` header, new manifest points at
   `scripts/new-name.sh`). The installer removes the old binary.
4. **`install-skills-bin --update --dry-run`** shows the plan without
   doing anything. Operators can preview before committing.
5. **Every update writes an entry to
   `/var/log/linux-skills/install-updates.log`** with the git SHA before
   and after, and the list of files changed.

---

## R9. Scripts and skills drift out of sync over time

**Likelihood:** H. **Impact:** M.

**Risk:** Skills are living documents. When a skill is updated (new
Ubuntu version, better approach, CVE-driven change), the scripts that
wrap it must be updated too. Without discipline, the skill and the
script diverge and the "optional fast path" stops matching the manual
commands.

**Mitigation:**

1. **Memory rule `feedback_scripts_follow_skills.md` is standing.** When
   a skill changes, affected scripts are updated in the same session.
2. **`sk-lint` checks that the script matches the skill's manifest.**
   If `SKILL.md ## Scripts` lists `sk-foo` but `scripts/sk-foo.sh`
   doesn't exist, that's a lint failure. Vice versa.
3. **Every skill's `## Scripts` manifest must include a `## Source`
   comment pointing at the script**, and every script must include a
   pointer back to the skill in its header comment. Two-way reference.
4. **Periodic drift audit in `docs/analysis/`:** once per session, the
   readiness analysis grep-checks that every manifest entry has a
   matching script file and vice versa.

---

## R10. Book source material ages out

**Likelihood:** H over 5+ years. **Impact:** L.

**Risk:** The 9 source books were published between 2000 (Linux Network
Admin Guide) and 2023 (Mastering Ubuntu). Some of the 2000s content
already needed modernization (e.g. `ifconfig` → `ip`). The 2020s content
will age. In 5 years, 30% of the command patterns documented here will
be obsolete.

**Mitigation:**

1. **The skill layer is live documentation, not a static book.** When
   something becomes obsolete, update the reference file and the
   scripts in the same session. The memory rule enforces this.
2. **Skills cite specific book chapters but don't depend on them.** The
   content has been rewritten in the project's own voice and will
   evolve independently.
3. **Newer books can be added as source material over time.** No need
   to restart from scratch.
4. **The per-session readiness analysis will catch content drift**
   because the gap list includes "outdated content" as a category.

---

## R11. 88 scripts is more maintenance than one operator can sustain

**Likelihood:** M. **Impact:** H.

**Risk:** Writing 88 scripts is one thing. Maintaining them over 5
years while Ubuntu evolves, packages change, and dependencies update is
another. A single-operator project (even with AI help) has a realistic
ceiling of 30–50 well-maintained scripts. 88 may be over-ambitious.

**Mitigation:**

1. **Tier-based maintenance cadence.** Tier 1 scripts (15) get
   quarterly review. Tier 2 (46) get semi-annual review. Tier 3 (27)
   get annual review or review-on-complaint.
2. **Deprecation policy.** Any tier 3 script that hasn't been used in
   12 months is a candidate for removal. Track via `/var/log/linux-skills/`
   audit entries.
3. **AI-assisted maintenance is first-class.** Memory rules and this
   analysis ensure that future Claude sessions can pick up maintenance
   work without full context re-read.
4. **The book is a forcing function.** Publishing commits us to
   maintaining the scripts. If a script is too hard to maintain, it
   doesn't make the book.
5. **If the 88 scripts prove too many, cut tier 3 first.** Tier 1 and
   Tier 2 (61 scripts) are the genuine must-haves.

---

## R12. `shellcheck` strictness pushes developers toward workarounds

**Likelihood:** M. **Impact:** L.

**Risk:** `shellcheck` is strict. Some warnings are pedantic ("SC2086:
Double quote to prevent globbing") in contexts where globbing is
intentional. Developers who want to ship a script will either:

- Disable the warning inline with `# shellcheck disable=SC2086`
  everywhere (noise).
- Switch to a different shell or tool.
- Stop running `shellcheck` locally.

**Mitigation:**

1. **Make `# shellcheck disable=...` require a comment justifying why.**
   Enforced in code review and by a CI grep that fails on naked
   disables.
2. **Maintain a project-wide `.shellcheckrc`** with the set of rules
   we've collectively decided to disable for good reasons, with rationale.
3. **`sk-lint` wraps `shellcheck` with project-specific rules** that
   override or augment the defaults. The goal is one command operators
   run, not raw `shellcheck`.
4. **Budget one "known clean baseline" review** each quarter to sweep
   up accumulated disables and decide whether they're still justified.
