# Portfolio refresh — 29 October 2026

## Frozen scope and baseline

The completed October cycle ends at `fd0a5ea468b4c21792ab27277e74bd387a3860da`.
The portfolio pull found that revision current and the checkout clean. This
supplement preserves the seven original evidence files and their frozen scores.
It does not claim a second full operational Kaizen or repeat previously retained
restore and rollback proof.

Before this supplement changes code, the three registered validators pass:
`python -X utf8 scripts/validate_skills.py --baseline quality-baseline.json`,
`python -X utf8 scripts/routing_smoke_test.py`, and
`bash scripts/tests/check-distro-matrix.sh` each exit 0. The Python suite reports
73 passed, one skipped and eight subtests passed. `python scripts/check_marketplace.py`
passes with 367 package files and 704 full-checkout entries. The existing raw
final score remains 74; the Standard published cap remains 65 and the original
user-requested baseline cap remains 45. The target is 95, not an achieved score.

## Selected bounded experiment R1

Gap: the marketplace check's Python API accepts a caller-supplied file limit
above 5,000, although its command-line entry point uses the hard default.
Five Whys: tests need small limits; the API exposes that threshold; it only
rejects negative values; the product ceiling was treated as a default; no
negative fixture guarded an inflated caller-supplied ceiling.

Change: reject configured limits outside zero through 5,000, retaining smaller
fixture limits. Hypothesis: a caller cannot relax the hard portfolio ceiling.
Owner: Peter Bamuhigire; date: 2026-10-29. Acceptance: an inflated-limit negative
fixture, existing cap/path/manifest fixtures, the full Python suite and all three
registered validators pass. Risk is limited to callers that previously raised
the limit; rollback is the isolated R1 commit, without deleting user files.
No numerical score contribution is claimed for this small gate correction.

## R1 result

Kept commit: `57bd07d fix(linux): R1 reject file limits above hard ceiling`.
No changes were reverted. All three registered validators pass after R1. The Python suite reports
74 passed, one skipped and ten subtests passed; the new regression tests reject
both negative and inflated caps. The unchanged operational task artefacts and
previous MySQL/web recovery evidence remain the applicable practitioner proof;
this packaging change does not alter their procedures or claim a new lab run.
The final hygiene regression check passes: no new machine-specific links,
dangling paths/anchors, duplicate contracts or expired source records. Routing
remains 67/80 at rank one and 80/80 at rank three; all 41 distro matrices pass.
The final pre-report inventory is 369 package files and 712 checkout entries;
Git object entries can grow when this report is committed, so the release gate
recounts the actual checkout.
The native installation observations are retained in
[native-plugin-evidence.json](native-plugin-evidence.json).

## Native runtime observation

Offline disposable Debian containers mounted the repository read-only and the
native CLI binary; host credentials and configuration were not mounted. Codex
0.165.0 successfully added the local marketplace, installed `linux@chwezi-linux`
and listed it enabled. Its offline `debug prompt-input` exposed all 45 declared
skill paths. Claude 2.1.312 installed the same entry and reported 47 skill-like
components: 45 declared skills and the two legacy rclone/redis commands. The
Claude inventory reported one unset user configuration option. These checks
made no model call and did not execute operational hooks.

This closes local installation/discovery evidence only. Public directory
acceptance, paid behavioural routing and hook execution remain NOT_ASSESSED.
The earlier next-cycle request for a live local installation test is superseded
by this observation; its public-listing and hook limitations remain open.

## Resolved catalogue observation

The earlier cross-engine note could not find the development source register.
Resolving the current catalogue alias now locates
`chwezi-dev-engine/docs/source-registers/skills-engine-currentness-2026-09.json`.
The Linux reference in
`16-network-equipment/network-config-validation/SKILL.md` therefore has a
counterpart. This corrects a lookup limitation, not the register's currency or
claim accuracy; the development cycle owns those checks.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

## Hosted Fedora image repair

Hosted [Bash suites run40839578412](https://github.com/peterbamuhigire/linux-skills/actions/runs/40839578412)
failed before tests when the registry returned manifest-unknown for the original
pinned Fedora digest. Skill quality and source-ingestion checks passed at
`041c738`; this was not a Bash assertion failure.

The official `quay.io/fedora/fedora:44` tag was resolved and pulled again on
2026-10-29. Its current amd64 manifest is
`sha256:351d714a39c16fda7f3d266c0e41b4f34b51e8dfc62f12ae83b8169d7a3c5c64`.
The workflow remains digest-pinned. In a disposable container at that exact
revision, all29 common-library and21 installer assertions pass. This verifies
the replacement image for these fixtures, not enterprise RHEL or production
services. Historical lab digests above remain unchanged as provenance.
