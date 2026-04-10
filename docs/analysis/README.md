# linux-skills readiness analysis

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This directory contains the living readiness analysis for `linux-skills` as
a world-class Linux server management engine. The documents are updated
after every iteration — we never throw one away, we append and correct in
place.

## Purpose

Answer one question: **"Is linux-skills ready to manage real production
Ubuntu/Debian servers?"** — and, where the answer is "not yet," name the
exact gap and the work required to close it.

## Files in this directory

| File | What it answers |
|---|---|
| [`README.md`](README.md) | This file. Executive summary + revision history + index. |
| [`strengths.md`](strengths.md) | What's genuinely world-class. Concrete evidence per claim. |
| [`gaps.md`](gaps.md) | What's missing or weak. Severity-tagged (CRITICAL/HIGH/MEDIUM/LOW). |
| [`skills-coverage.md`](skills-coverage.md) | Per-skill matrix: SKILL.md depth, reference depth, book-sourced, self-contained, scripts planned. |
| [`risks.md`](risks.md) | Risks to address before and during script generation. |
| [`build-order.md`](build-order.md) | Recommended next-session work plan, phase by phase. |

## Executive summary (2026-04-10)

`linux-skills` is a curated knowledge base and engine specification for
managing Ubuntu/Debian production servers. After this session the skill
layer is effectively complete; the script layer has not started.

**Bottom line:** the engine is **95% ready as a knowledge base** and **0%
ready as an executable engine**. Every design decision is made, every
command a reader needs is documented, every book in the source stack has
been distilled — but the `sk-*` scripts that turn the knowledge into a
tool Claude Code can invoke do not yet exist.

### By the numbers

| Metric | Value |
|---|---|
| Specialist skills | 24 (+ 1 hub) |
| `SKILL.md` files | 25, total **4,901 lines** |
| Reference files | 40, total **30,411 lines** |
| Engine design documents | 3, total **777 lines** |
| Books distilled into reference material | 9 |
| Total skill + design content | **~36,089 lines** |
| Shell scripts (existing/legacy) | 4 |
| Shell scripts (planned in inventory) | 88 |
| Shell scripts (written to spec) | 0 |
| Skills with a `scripts/` subdirectory | 0 |

### Readiness scorecard (0–10)

| Category | Score | Reasoning |
|---|---|---|
| **Vision & scope** | 10 | Clear, focused, non-aspirational. |
| **Engine specification** | 9 | Complete with idempotency, upgrade path, LXD testing, build order. One open question on dev-mode library sourcing. |
| **Skill catalogue coverage** | 10 | 24 specialist skills cover every production domain we need. |
| **Skill self-sufficiency** | 9 | Every skill has a self-contained callout, manual commands primary, sk-* in optional fast-path. Uniform enforcement. |
| **Reference depth** | 9 | ~30k lines book-sourced reference material. Thinner on bash-scripting (meta-skill only needs so much) and troubleshooting (1 file, but 833 lines). |
| **Author attribution & book-quality writing** | 10 | Every file has author header; every reference file has TOC, sources, annotated examples. |
| **`common.sh` library (implemented)** | 0 | Specified, not written. |
| **`install-skills-bin` installer (implemented)** | 0 | Specified, not written. |
| **Test harness (LXD container)** | 0 | Specified, not written. |
| **`sk-*` scripts (written)** | 0 | 88 planned, 0 written. |
| **Runtime usability on a server** | 1 | Only 4 legacy scripts work today; the 88-script toolkit doesn't exist yet. |
| **Documentation quality** | 10 | Book-ready, structured, cross-referenced, author-attributed. |

**Weighted overall readiness (knowledge layer + runtime layer combined): 6.5/10.**

### Top 3 strengths

1. **The engine specification is genuinely production-grade.** The `--yes`
   contract alone distinguishes this from Ansible/Chef/Salt — it's
   designed for AI agent invocation from day one. Idempotency, LXD
   integration testing, and the hybrid installation model are all
   specified, not hand-waved.
2. **Reference depth is book-quality.** 30,411 lines of reference
   material is sourced from 9 authoritative books, rewritten in
   consistent voice, and structured for both human readers and script
   authors. This alone is enough material for the forthcoming `sk-*`
   scripts book.
3. **Skills stand alone.** Every skill is usable on a stock Ubuntu/Debian
   server with zero `sk-*` scripts installed. The "optional fast path"
   pattern means the future scripts add convenience without creating
   dependency.

### Top 3 gaps

1. **The entire script layer is unwritten.** 0 of 88 planned scripts
   exist. This is the single blocker to declaring the engine ready for
   real server management.
2. **No runtime foundation.** `scripts/lib/common.sh`, `install-skills-bin`,
   and the LXD test harness are all specified but not implemented — they
   must be built before any `sk-*` script can be built.
3. **No end-to-end verification path.** Because the scripts don't exist,
   there's no CI, no integration test, no proof that the conventions in
   `spec.md` are actually implementable as written. The first five
   scripts will expose design issues we haven't seen yet.

### Go / no-go on script generation

**GO**, with the proviso that the next session starts with the foundation
— not with tier-1 feature scripts.

**Specifically, the next session must build, in this exact order:**

1. `scripts/lib/common.sh` — the shared library.
2. `scripts/install-skills-bin` — the installer.
3. `scripts/tests/` — the LXD test harness.
4. **Smoke test:** run `install-skills-bin core` on a fresh LXD container.
5. Tier-1 scripts 1–5 (`sk-audit`, `sk-update-all-repos`, `sk-new-script`,
   `sk-lint`, `sk-system-health`).
6. **Foundation smoke test:** all 5 scripts pass integration tests.
7. Only after this foundation is green: tier-1 scripts 6–15, then tier-2,
   then tier-3.

This matches §12 of [`../engine-design/spec.md`](../engine-design/spec.md)
and is the recommendation from the critique you ran on the spec earlier.
Do not deviate.

See [`build-order.md`](build-order.md) for the detailed plan.

## Revision history

| Date | Session | Author | Summary |
|---|---|---|---|
| 2026-04-10 | #1 — initial analysis | Peter Bamuhigire + Claude | First analysis after skill-layer completion. 24 skills written, 30k+ lines of references, engine spec complete. Scripts unwritten. Readiness 6.5/10. Cleared to begin script generation with the foundation-first build order. |

*Append a new row after each session that meaningfully changes the
readiness picture. Never delete rows — the trend matters as much as the
current state.*
