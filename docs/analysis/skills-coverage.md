# Skills coverage matrix

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Per-skill assessment of depth, self-containment, book backing, and
script-generation readiness as of 2026-04-10. This is the map a future
session uses to decide which skill needs attention next.

## Scoring axes

- **SKILL.md lines** — raw line count in the skill's main file.
- **Ref lines** — total lines across the skill's `references/*.md` files.
- **Ref files** — number of reference files in the skill.
- **Self-contained?** — does the SKILL.md have the "self-contained"
  callout and lead with manual commands? yes / no.
- **Book-sourced?** — are the references cited to specific books and
  chapters? yes / partial / no.
- **Scripts planned** — how many `sk-*` scripts the inventory assigns
  to this skill.
- **Scripts core?** — how many of those are in tier-1 (core install).
- **Depth rating** — subjective 1–5 on whether the content is deep
  enough for a script author to build from without re-reading a book.

## The matrix

| # | Skill | SKILL.md | Ref lines | Ref files | Self-contained | Book-sourced | Scripts planned | Scripts core | Depth |
|---|---|---:|---:|---:|---|---|---:|---:|---|
| 0 | **linux-bash-scripting** | 265 | 473 + `.sh` template | 3 | N/A (meta) | yes | 2 | 2 | 4/5 |
| 1 | linux-sysadmin (hub) | 143 | — | 0 | yes | n/a | 0 | 0 | 5/5 |
| 2 | linux-security-analysis | 111 | 1,040 | 2 | yes | yes | 2 | 1 | 5/5 |
| 3 | linux-server-hardening | 119 | 1,100 | 2 | yes | yes | 3 | 0 | 5/5 |
| 4 | linux-access-control | 106 | 1,088 | 2 | yes | yes | 4 | 2 | 5/5 |
| 5 | linux-firewall-ssl | 122 | 1,901 | 3 | yes | yes | 4 | 1 | 5/5 |
| 6 | linux-intrusion-detection | 118 | 1,324 | 2 | yes | yes | 3 | 1 | 5/5 |
| 7 | linux-secrets | 329 | 1,377 | 3 | yes | yes | 2 | 0 | 5/5 |
| 8 | linux-server-provisioning | 102 | 1,126 | 2 | yes | yes | 1 | 0 | 5/5 |
| 9 | linux-cloud-init | 310 | 1,695 | 3 | yes | yes | 2 | 0 | 5/5 |
| 10 | linux-site-deployment | 137 | 1,299 | 3 | yes | yes | 6 | 1 | 5/5 |
| 11 | linux-webstack | 146 | 1,695 | 3 | yes | yes | 5 | 0 | 5/5 |
| 12 | linux-service-management | 119 | 1,295 | 2 | yes | yes | 4 | 2 | 5/5 |
| 13 | linux-package-management | 342 | 1,208 | 3 | yes | yes | 4 | 0 | 5/5 |
| 14 | linux-disk-storage | 123 | 1,330 | 2 | yes | yes | 3 | 1 | 5/5 |
| 15 | linux-system-monitoring | 100 | 1,317 | 2 | yes | yes | 3 | 2 | 5/5 |
| 16 | linux-log-management | 133 | 1,811 | 3 | yes | yes | 5 | 1 | 5/5 |
| 17 | linux-network-admin | 307 | 947 | 2 | yes | yes | 5 | 0 | 4/5 |
| 18 | linux-dns-server | 278 | 994 | 2 | yes | yes | 2 | 0 | 5/5 |
| 19 | linux-mail-server | 318 | 1,329 | 3 | yes | yes | 4 | 0 | 5/5 |
| 20 | linux-virtualization | 289 | 1,000 | 2 | yes | yes | 4 | 0 | 5/5 |
| 21 | linux-config-management | 336 | 1,836 | 3 | yes | yes | 3 | 0 | 5/5 |
| 22 | linux-observability | 287 | 1,217 | 3 | yes | yes | 3 | 0 | 5/5 |
| 23 | linux-troubleshooting | 107 | 833 | 1 | yes | yes | 4 | 0 | 4/5 |
| 24 | linux-disaster-recovery | 154 | 1,176 | 2 | yes | yes | 10 | 1 | 5/5 |

**Totals:** 25 skills; `SKILL.md` 4,901 lines; references 30,411 lines;
40 reference files; 88 planned scripts (15 core + 73 non-core).

## Self-containment audit

Every skill has the `**This skill is self-contained.**` callout at the
top of `SKILL.md` and organizes `sk-*` references into an "Optional fast
path" section below the manual content. Verified by grep:

```bash
for f in linux-*/SKILL.md; do
    grep -q "self-contained" "$f" || echo "MISSING callout in $f"
done
# (no output = all pass)
```

## Depth observations

### 5/5 — book-quality, script-ready

21 of 25 skills are at 5/5. The content is detailed enough that a script
author can build the planned `sk-*` scripts from the skill's
`references/` alone without re-reading the source books.

### 4/5 — complete but trimmable

- **linux-bash-scripting** (meta-skill) — by design. It's short because
  it points at the spec and at `common-sh-contract.md`. Gap: a bash
  idioms cheat-sheet reference would be welcome. Severity: [LOW per
  gaps.md M1].
- **linux-network-admin** — the wave-1 agent trimmed its files during
  its self-correction pass. 947 lines is slightly below the 1000+ norm
  for peers. Content is still complete, just less annotated. Severity:
  [MEDIUM per gaps.md M3].
- **linux-troubleshooting** — single reference file at 833 lines. A
  second file (`common-signatures.md`) would strengthen it. Severity:
  [MEDIUM per gaps.md M2].

## Per-skill scripts planned

### Core (tier 1, 15 scripts, install everywhere)

| Skill | Scripts |
|---|---|
| linux-security-analysis | `sk-audit` |
| linux-site-deployment | `sk-update-all-repos` |
| linux-bash-scripting | `sk-new-script`, `sk-lint` |
| linux-system-monitoring | `sk-system-health`, `sk-open-ports` |
| linux-disk-storage | `sk-disk-hogs` |
| linux-service-management | `sk-service-health`, `sk-cron-audit` |
| linux-firewall-ssl | `sk-cert-status` |
| linux-access-control | `sk-user-audit`, `sk-ssh-key-audit` |
| linux-intrusion-detection | `sk-fail2ban-status` |
| linux-log-management | `sk-journal-errors` |
| linux-disaster-recovery | `sk-backup-verify` |

### Non-core (tiers 2 + 3, 73 scripts, per-skill install)

Distribution across skills:

- **linux-disaster-recovery** has the largest non-core count (9
  scripts): MySQL/Postgres backup+restore pairs, site backup/restore,
  config-snapshot, restore-wizard, emergency-mode. This makes sense —
  disaster recovery is a dense domain.
- **linux-site-deployment** has 5 non-core scripts (vhost generators,
  deployment wrappers).
- **linux-log-management**, **linux-network-admin**,
  **linux-webstack** each have 5 non-core scripts.
- Most other skills have 2–4 non-core scripts.

Thin-script skills (1–2 scripts planned):
- `linux-server-provisioning` has only 1 script (`sk-provision-fresh`) —
  correct: provisioning is mostly a wizard around the other skills.
- `linux-dns-server`, `linux-secrets`, `linux-cloud-init` have 2 each.
- `linux-security-analysis` has 2 (audit + apparmor-status).

No skill is over-loaded. No skill is empty.

## Reference depth by category

Grouping by domain to see where the library is thickest:

| Category | Skills | Total ref lines | Average |
|---|---:|---:|---:|
| Security | 6 | 7,830 | 1,305 |
| Operations | 8 | 10,072 | 1,259 |
| Networking | 3 | 3,270 | 1,090 |
| Containers + automation | 3 | 4,053 | 1,351 |
| Recovery | 2 | 2,009 | 1,005 |
| Foundation (meta + hub + bash) | 2 | 473 | 237 |

Security and operations are the thickest domains. Recovery is slightly
thinner because disaster-recovery's 1,176 lines paired with
troubleshooting's single-file 833 drags the average. That matches the
reality — there's simply less distinct reference material for recovery
than for the others (most recovery is "use the backup strategy and the
restore procedures we already documented").

## Skills ready to have their scripts built

All 24 specialist skills are ready for script generation from a
reference-material standpoint. The blocker is not "we don't know what to
build" — it's "we haven't built the foundation yet." Once `common.sh`
and `install-skills-bin` exist, any skill can be picked up and its
scripts built.

The recommended order is:

1. **Foundation first** (common.sh, installer, LXD harness) — see
   [`build-order.md`](build-order.md).
2. **Tier 1 scripts 1–5** first to validate the foundation, specifically:
   `sk-audit` (migrate existing), `sk-update-all-repos` (rename),
   `sk-new-script`, `sk-lint`, `sk-system-health`.
3. **Tier 1 scripts 6–15** after smoke test.
4. **Tier 2 scripts** theme by theme.
5. **Tier 3 scripts** only for servers that need them.
