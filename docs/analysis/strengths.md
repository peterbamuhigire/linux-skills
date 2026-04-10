# Strengths

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

What is genuinely world-class about `linux-skills` as of 2026-04-10. Every
claim on this page is backed by concrete evidence — file paths, line
counts, or specific design decisions. No marketing adjectives.

## Table of contents

- [1. The engine specification is production-grade](#1-the-engine-specification-is-production-grade)
- [2. The `--yes` contract is the killer AI feature](#2-the---yes-contract-is-the-killer-ai-feature)
- [3. Skills are self-sufficient by rule, not by accident](#3-skills-are-self-sufficient-by-rule-not-by-accident)
- [4. Reference depth is book-quality](#4-reference-depth-is-book-quality)
- [5. The 24-skill catalogue matches real operational needs](#5-the-24-skill-catalogue-matches-real-operational-needs)
- [6. The curated 88-script inventory is realistic, not aspirational](#6-the-curated-88-script-inventory-is-realistic-not-aspirational)
- [7. Safety rules are non-negotiable and specific](#7-safety-rules-are-non-negotiable-and-specific)
- [8. Hybrid install model solves a real problem](#8-hybrid-install-model-solves-a-real-problem)
- [9. Author attribution and book-readiness](#9-author-attribution-and-book-readiness)
- [10. Standing rules hold the line across sessions](#10-standing-rules-hold-the-line-across-sessions)

---

## 1. The engine specification is production-grade

**Evidence:** [`docs/engine-design/spec.md`](../engine-design/spec.md),
491 lines.

The spec covers, in order: goals, audiences (human + Claude), installation
model (Hybrid C with both core and lazy-install), naming convention
(`sk-` prefix), 8 standard flags each with precise semantics, the `--yes`
contract (see §2), the full `common.sh` library contract with every
function named and described, the mandatory six-section script template,
per-skill manifest parser rules, directory layout, 15 safety rules
including a new idempotency rule, a mandatory LXD integration test
harness, and an explicit staged build order (§12).

It ends with an "open questions" section that names three unresolved
details rather than pretending they don't exist. That's how a working
spec looks.

Compared to Ansible, Chef, or Salt docs, this spec is narrower (one
target: Ubuntu/Debian), more opinionated (fewer knobs), and more
explicit about AI agent invocation. Those are features, not
limitations.

## 2. The `--yes` contract is the killer AI feature

**Evidence:** [`spec.md §5.1`](../engine-design/spec.md) and every skill's
"Optional fast path" section.

Every mainstream configuration tool treats `--yes` / `-y` / `--force` as
"accept all defaults." We invert this:

> `--yes` means **"the caller has pre-committed to every decision"**. It
> does **not** mean "accept safe defaults." If a script would normally
> prompt for a required input and the caller did not supply a flag for it,
> the script must abort.

This is a small rule with outsized consequences:

- **For Claude Code:** it forces the agent to pre-commit all decision
  flags in the call. Claude can't get a different result than it asked
  for.
- **For human operators:** it enforces a documentation discipline —
  every decision flag must appear in `--help`.
- **For CI/automation pipelines:** non-interactive runs are deterministic
  by construction.

No other shell-based management toolkit I've seen codifies this.

## 3. Skills are self-sufficient by rule, not by accident

**Evidence:** every `linux-*/SKILL.md` file contains this block near the
top:

> **This skill is self-contained.** Every command below is a standard
> Ubuntu/Debian tool. The `sk-*` scripts in the **Optional fast path**
> section are convenience wrappers — never required.

And every `sk-*` reference appears only in a dedicated `## Optional fast
path` section below the main content. Manual commands (`systemctl`,
`nginx -t`, `certbot`, `dig`, `lxc`, `ansible-playbook`, etc.) are the
primary teaching material.

**Why this matters:** the skills work on day-one on any Ubuntu/Debian
server, even before any `sk-*` scripts are built. They work during
debugging when the scripts are broken. They work for a human admin who
refuses to use the scripts. They work for copy-pasting into a book
chapter.

This was not the initial approach — the first draft of several skills
pushed `sk-*` scripts as primary content. You called it out twice in
Session #1 ("the skills do not depend whatsoever on the scripts being
written first"). The correction was applied systematically across all 24
skills. Evidence of the discipline holding: every SKILL.md now has the
callout, and a grep for `sudo sk-` outside of "Optional fast path"
sections returns zero hits.

## 4. Reference depth is book-quality

**Evidence:** `find linux-*/references -name '*.md' | xargs wc -l` →
**30,411 lines** across **40 reference files** covering **24 skills**.

Sample depths (lines in `references/` per skill):

| Skill | Reference lines |
|---|---|
| linux-firewall-ssl | 1,901 |
| linux-config-management | 1,836 |
| linux-log-management | 1,811 |
| linux-webstack | 1,695 |
| linux-cloud-init | 1,695 |
| linux-secrets | 1,377 |
| linux-mail-server | 1,329 |
| linux-disk-storage | 1,330 |
| linux-intrusion-detection | 1,324 |
| linux-system-monitoring | 1,317 |
| linux-site-deployment | 1,299 |
| linux-service-management | 1,295 |
| linux-observability | 1,217 |
| linux-package-management | 1,208 |
| linux-disaster-recovery | 1,176 |
| linux-server-provisioning | 1,126 |
| linux-server-hardening | 1,100 |
| linux-access-control | 1,088 |
| linux-security-analysis | 1,040 |
| linux-virtualization | 1,000 |
| linux-dns-server | 994 |
| linux-network-admin | 947 |
| linux-troubleshooting | 833 |
| linux-bash-scripting | 473 + a script template |

Each file follows the same format: `H1 title`, author byline, intro,
table of contents, content organized by H2/H3, source citations naming
specific books and chapters. Imperative voice. Copy-pasteable annotated
examples. Zero filler.

Every reference file cites at least one of the 9 source books by chapter:
*Pro Bash*, *Linux Command Line and Shell Scripting Bible*, *Wicked Cool
Shell Scripts*, *Linux Command Lines and Shell Scripting* (Vickler),
*Beginner's Guide to the Unix Terminal*, *Ubuntu Server Guide*
(Canonical), *Linux Network Administrator's Guide*, *Linux System
Administration for the 2020s*, and *Mastering Ubuntu* (Atef).

This is enough material that, as a by-product, the forthcoming `sk-*`
scripts book already has its reference chapters drafted.

## 5. The 24-skill catalogue matches real operational needs

**Evidence:** [`linux-sysadmin/SKILL.md`](../../linux-sysadmin/SKILL.md)
routing table.

The 24 specialist skills plus the hub cover every domain a production
Ubuntu web server actually needs:

- **Foundation:** `linux-bash-scripting` (meta-skill), `linux-sysadmin`
  (hub).
- **Security (6):** analysis, hardening, access-control, firewall-ssl,
  intrusion-detection, secrets.
- **Operations (8):** provisioning, cloud-init, site-deployment,
  service-management, webstack, package-management, disk-storage,
  system-monitoring, log-management.
- **Networking (3):** network-admin, dns-server, mail-server.
- **Containers & automation (3):** virtualization, config-management,
  observability.
- **Recovery (2):** troubleshooting, disaster-recovery.

Every skill has a clear scope boundary ("this skill owns X, does NOT own
Y, pointer to the skill that owns Y"). Overlap is deliberate and
pointer-based, not duplicated content.

This was designed bottom-up from the 9-book research pass, not top-down
from a taxonomy. Several initially-proposed skills were dropped because
they overlapped with existing ones (`linux-scheduling` folded into
service-management, `linux-file-integrity` folded into
intrusion-detection).

## 6. The curated 88-script inventory is realistic, not aspirational

**Evidence:** [`docs/engine-design/script-inventory.md`](../engine-design/script-inventory.md),
245 lines, 88 scripts ranked into 3 tiers.

**Tier 1 (15 scripts, core install)** is a genuine minimum viable toolkit:
`sk-audit`, `sk-update-all-repos`, `sk-new-script`, `sk-lint`,
`sk-system-health`, `sk-disk-hogs`, `sk-open-ports`, `sk-service-health`,
`sk-cert-status`, `sk-cron-audit`, `sk-user-audit`, `sk-ssh-key-audit`,
`sk-fail2ban-status`, `sk-journal-errors`, `sk-backup-verify`. Each
answers a day-one question a new operator asks.

**Tier 2 (46 scripts)** is the workhorse layer for daily/weekly ops.

**Tier 3 (27 scripts)** is the specialized layer for servers that
actually need it (mail, DNS, virtualization, cloud-init, observability,
secrets, config management).

The inventory is *curated from the 170+ scripts the book-research agents
surfaced*, not a firehose. Duplicates were merged, low-value ideas were
dropped. Every row has a skill owner, a priority, a source citation, and
a one-line purpose.

This level of upfront curation is rare. Most projects either ship
everything the first draft suggested (bloat) or ship too little (then
accrete feature creep later). 88 is the right scale.

## 7. Safety rules are non-negotiable and specific

**Evidence:** `spec.md` §9, rules 1–15.

The 15 rules include:

1. Source `common.sh` — never reimplement colors, prompts, traps.
2. `set -uo pipefail` always, `set -e` never.
3. Quote every variable.
4. `IFS= read -r` on every `read`.
5. Parameter expansion over sed/awk.
6. Atomic file edits (write-temp + mv).
7. Safe temp files with cleanup trap.
8. `case` validation, not sprawling regex.
9. `printf` over `echo`.
10. `"$@"` (quoted) when forwarding args.
11. Precise exit codes.
12. **No `eval` on untrusted input, ever.**
13. Validate config before reload (`nginx -t`, `sshd -t`, etc.).
14. Destructive ops always audit-log.
15. **Idempotency by default** (the one added after your spec critique).

These are not guidelines. They are enforced by `sk-lint` (to be built in
the next session) and checked in code review. Rule 15 in particular is
something most toolkits forget — a non-idempotent script is a script you
can't re-run, which means it can't be retried after partial failure,
which means it can't be safely wrapped in automation.

## 8. Hybrid install model solves a real problem

**Evidence:** `spec.md` §3.

Most configuration management systems either:
- Ship everything to every server (bloat: hundreds of unused scripts on
  a server that runs one workload), or
- Require the operator to cherry-pick (friction: "I forgot to install
  the one I need right now").

Hybrid C:
- **Core install** — `install-skills-bin core` during provisioning,
  lays down the 15 tier-1 scripts every server needs (audit, health,
  ports, certs, cron, users, SSH keys, fail2ban, journal, backup).
- **Lazy install** — when a skill is first used on a server, its
  `SKILL.md` instructs Claude to run
  `install-skills-bin <skill-name>`, which installs just that skill's
  scripts.

Claude Code can self-bootstrap: `command -v sk-nginx-new-site || sudo
install-skills-bin linux-webstack`. A server running only a static site
never installs the mail-server or DNS-server scripts. A new script added
upstream appears automatically after `install-skills-bin --update`.

## 9. Author attribution and book-readiness

**Evidence:** every `SKILL.md` frontmatter has `metadata.author: Peter
Bamuhigire`, `author_url: techguypeter.com`, `author_contact: +256784464178`.
Every reference file has an `**Author:**` header byline in the same
format. Every engine-design document has the same. The memory file
`feedback_author_attribution.md` makes this a standing rule across
sessions.

This isn't vanity. It's book-preparation: when these 30k+ lines of
reference material become chapters in the forthcoming `sk-*` scripts
book, the attribution is already in place.

The memory file `project_book_goal.md` captures the goal explicitly and
tells future sessions to write every new file with a reader in mind —
rationale and "why," not just "what." This shifted the writing style
mid-session (compare the terse original `hardening-checklist.md` with
the book-quality expanded version).

## 10. Standing rules hold the line across sessions

**Evidence:** `~/.claude/projects/C--wamp64-www-linux-skills/memory/`
contains:

- `user_identity.md` — Peter Bamuhigire, techguypeter.com, +256784464178.
- `feedback_author_attribution.md` — every file credits him.
- `feedback_scripts_follow_skills.md` — when a skill changes,
  proactively update affected scripts in the same session.
- `project_book_goal.md` — scripts will be published as a book; write
  with a reader in mind.

These rules survive across sessions. A future session will not have to
re-discover the author convention, the "skills don't depend on scripts"
rule, or the "scripts follow skills automatically" rule. Each becomes a
background constraint rather than a negotiation.

This is the infrastructure that keeps a multi-session project coherent.
Without it, session N+1 inevitably drifts from session N. With it, the
rules compound.
