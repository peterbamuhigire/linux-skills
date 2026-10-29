# Portfolio Kaizen final report — 29 October 2026

Linux Skills has verified safety, recovery, routing and packaging improvements. **The 95/100 raw target is not achieved.** The two reproduced critical defects—temporary-file trust and plaintext backup leakage—are fixed within the tested boundaries. No production host has been certified or patched by this repository review.

## Scores

Scores are ten equally weighted Standard dimensions, supported by the named evidence. They are reviewer judgements, not a percentage of vulnerabilities eliminated. The earlier 20-criterion interim score is not comparable and is superseded.

| Dimension | Before | After | Evidence / remaining deficiency |
|---|---:|---:|---|
| Doctrine |80|85| Safety contract now has adversarial fixtures; broad runtime conformance incomplete |
| Taxonomy and routing |60|75|80 cases, P@1 67/80;37 skills still lack3+2 coverage |
| Skill depth |65|75|Paired baseline, full502 tree and restore procedure; worked-example depth unchanged elsewhere |
| Applied proof |35|65|Real restore and dual-family upstream rollback; full hardening and enterprise RHEL host proof absent |
| Standards currency |35|65|Official currentness matrix and advisory register;10 historical source rows still overdue |
| Output readiness |45|80|Backup/audit/installer defects fixed; not every output type executed |
| Accessibility and inclusion |65|65|Plain text and explicit unknown states; practitioner accessibility testing absent |
| Production and handoff |35|75|Timed clean restore and release boundaries; production scale/RPO/RTO not verified |
| Hygiene |55|75|New regression and packaging gates; historical links/heading debt remains |
| Safety and integrity |30|80|Critical failures reproduced then repaired; target-specific filesystem and fleet coverage remain |

Raw mean: **50.5→74.0**. Standard capped score `min(raw,65)`: **50.5→65.0**. Peter's stricter publication ceiling `min(raw,45)`: **45→45**. The ceiling is retained explicitly, not used to conceal the raw improvement or inflate the target.

## Measured changes

- Contracts48/48 and distro matrices41/41 retained under stronger checks.
- Routing expected P@1 **25/30(83.33%)→67/80(83.75%)**; expected top3 **100%→100%**. All owned-negative forbidden-neighbour checks pass. Complete3positive/2owned-negative coverage **0→11 of48**.
- Worked examples remain48/48;153 paragraphs and331 nonblank lines, medians2 and4.5. These proxies do not establish practitioner quality.
- Marketplace paths align across Claude and Codex for 45 operational skills. Both package and full checkout are below 5,000 files, with CI-enforced ceilings. Claude validation passes; live client loading and OpenAI public listing are NOT_ASSESSED, with concrete limitations in [packaging](../../marketplace.md).
- Bounded source scan still reports 10 expired historical records. The final JSON reports all missing paths/anchors and duplicate headings rather than hiding debt. No same-scope measure is intentionally weakened.

## Kept changes and evidence

[Experiment log](03-experiment-log.md), [validation record](04-validation-record.md), [currentness](currency.md), [source register](../../security/source-register-2026-10-29.md) and [model review](../../continuous-improvement/model-review-2026-10-29.md) contain the evidence and limitations. The ledger below identifies the retained changes from actual Git history. No experiment was discarded wholesale; failed intermediate attempts were repaired and rerun.

## Residual risk and release scope

This is a repository release of bounded improvements. It is not an approval to apply every runbook blindly to production. Root-owned trusted configuration directories remain a precondition for atomic replacement; ACL/xattr/SELinux metadata preservation is unassessed. MySQL lab used synthetic data and local rclone storage. Fedora does not prove every RHEL derivative. Security applicability requires installed versions and vendor backport evidence.

The [next cycle](06-next-cycle.md) owns the remaining proof gaps and cross-engine mismatches. No other engine was edited. Existing model pins retained; vendor catalogue/current availability reviewed, comparative quality/latency/cost benchmark NOT_ASSESSED. No paid Tier3 calls were made.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

Independent acceptance review by the assigned Luna/high reviewer found no material blocker in backup handling, trusted temporary-file/atomic-write safeguards, marketplace parity or CI gates. It caught the baseline arithmetic error and missing interim log attachments; both were corrected with the original evidence preserved.

## Retained commit ledger

| Commit | Retained change |
|---|---|
| `98ba407` | docs(linux): K00 freeze portfolio baseline and bounded backlog |
| `c1a3385` | fix(linux): K01 protect temporary cleanup and atomic writes |
| `4dcaba2` | fix(linux): K02 report effective audit state and query failures |
| `a4e6f7f` | fix(linux): K03 fail installer preflight when cmp is missing |
| `c47b4ae` | fix(linux): K09 protect backups and verify clean-instance restore |
| `4e28dae` | fix(linux): K08 prove PHP upstream recovery and rollback |
| `bdda0a2` | docs(linux): K06 record current security and support evidence |
| `6e75a2f` | test(linux): K10 measure routing precision and owned negatives |
| `93122fb` | build(linux): K07 align Claude and Codex marketplace packages |
| `923342b` | ci(linux): K05 pin actions and enforce runtime quality gates |
| `4518733` | test(linux): K04 reject weak distro and hygiene evidence |

Final documentation/evidence is committed separately after this ledger; its commit is discoverable with `git log --oneline -- docs/kaizen/2026-10-engine-kaizen/05-final-report.md`.

Same-parser hygiene comparison: missing local paths7→5; missing anchors10→10; absolute machine-specific inline links0→0; duplicate canonical heading occurrences20→20 (ten affected skills); expired structured source rows10→10. No new finding identities. Baseline parser classification is documented in the refined JSON, with the original frozen JSON retained separately.

Release `751d10b` was fast-forwarded and pushed to `main`; all three [hosted workflows](04-validation-record.md#hosted-release-checks) passed. Final inventory at release:367package files and695checkout entries including Git/cache files, both below5,000. The file ceiling is enforced in CI and locally.

## Portfolio refresh supplement — 29 October 2026

See [the bounded R1 refresh](portfolio-refresh.md) for the stricter file-cap
regression, native local marketplace proof and the resolved development source
register lookup. Original operational evidence and raw scores are preserved.
