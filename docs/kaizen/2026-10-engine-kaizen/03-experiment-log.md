# Experiments — 29 October 2026

The first instruction preceded the Portfolio supplement. K01–K07 therefore include carried-in experiments; this log does not claim each was first implemented after the baseline document. The original Git tree remains the comparison. Work was bounded by file ownership; commits group retained hypotheses. Registered validators ran repeatedly on the integrated working tree, not on a clean checkout of each intermediate commit.

| Item | Hypothesis, experiment and outcome | Disposition |
|---|---|---|
| K01 | Private temporary registry and trusted parent checks prevent forged cleanup and fixed-sidecar attacks. Common suite grew to 29 cases; Debian and Fedora pass. Initial solution missed writable ancestor trust; independent review found it, implementation repaired and suites repeated. Atomic write rejects symlinks and preserves mode/owner with checked operations. | Kept; `c1a3385` |
| K02 | Effective `sshd -T` data and explicit unknown states avoid false passes. Eight fixture cases exercise missing/failed/empty SSH data, UFW inactive and update-query failures. Cached DNF data is labelled. | Kept |
| K03 | Missing `cmp` must stop installation before writes. Minimal Fedora initially failed idempotence; dependency preflight and a no-write regression fixed it. Installer 21 cases pass in both family containers with declared dependencies. | Kept |
| K04 | Section-aware distro checks reject shallow boilerplate and empty catalogues. Ten adversarial distro cases plus count-mismatch regression pass. Bounded metrics expose links, heading duplication, overdue sources and fixture ownership. | Kept |
| K05 | Run tests in CI, pin action revisions and add a Fedora fixture job. Workflow assertions pass; local equivalents pass. Hosted CI is separate evidence. | Kept |
| K06 | Official advisory/source records distinguish candidate exposure from installed-host vulnerability. Verified CISA feed and vendor records, package/support matrix and certificate profile changes. Missing target versions remain NOT_ASSESSED. | Kept; not a fleet patch claim |
| K07 | Shared Claude/Codex manifest paths avoid duplicated skills. Package, checkout file caps, traversal/path parity and manifest tests pass. Claude native validator passes with documented warnings. Legacy command examples get explicit safety boundaries. | Kept; public listing not established |
| K08 | Evidence-first upstream diagnosis is safer than a hard-coded PHP restart. Synthetic 502, repair, repeat, invalid configuration rejection and actual upstream rollback pass on Debian and Fedora. Paired hardened baseline remains a produced plan; no real firewall/ACME deployment. | Kept |
| K09 | Private backup staging and failure propagation prevent readable plaintext after failed encryption. Baseline lab reproduced mode0644 plaintext leak. Final lab used mode0600, repeated backup, clean second-instance restore and injected encryption/retention failures. | Kept |
| K10 | Owned positive/negative fixtures reveal route precision. Expanded 30→80 cases; top1 25/30→67/80, top3 remains100%; 11 skills meet3+2 coverage. | Kept |

No whole experiment was reverted. Failed intermediate implementations and environment failures were retained as findings, repaired and rechecked; they are not counted as successful experiments. Worker interruption during the session was inspected and resumed with bounded ownership; missing outputs were not inferred.

See [validation](04-validation-record.md) for commands and [final report](05-final-report.md) for the commit ledger and limitations. No source claim's verification date was refreshed without retrieval.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.

## Portfolio refresh supplement — 29 October 2026

See [the bounded R1 refresh](portfolio-refresh.md) for the stricter file-cap
regression, native local marketplace proof and the resolved development source
register lookup. Original operational evidence and raw scores are preserved.
