# Experiment log — 31 October 2026

One change at a time, highest priority first. After each change the affected check and every
registered validator that can run on this host were re-run (`run_all` list in
`04-validation-record.md`). All changes are kept; none was reverted. Short hashes are on branch
`kaizen/2026-10-pass2`.

| # | Item | Hypothesis | Change | Result before | Result after | Decision |
|---|---|---|---|---|---|---|
| 1 | P2-01 `6f30e09` | The documented SSH drop-in loses to cloud-init under first-value-wins; a `00-` name wins. | Renamed the drop-in in five procedures, stated the precedence rule, replaced a non-converging remediation line; new `tests/test_ssh_dropin_precedence.py`. | 3 of 6 tests fail; `sshd -T` gives `passwordauthentication yes` with the documented block | 6 of 6 pass; negative control still shows a `99-` file losing | Keep |
| 2 | P2-02 `cae7544` | `sk-pg-backup` leaks role hashes and publishes partial dumps; private staging fixes both. | Rewrote file handling (umask 077, 0700 staging, `pg_restore --list` gate, atomic rename, validated retention, NUL-separated database list, sanitised names); new `tests/test_pg_backup.py`. | Stub run: directory 755, files 644; 10 of 11 new cases fail against the previous script | 11 of 11 pass | Keep |
| 3 | P2-03 `ec2a269` | Root-run scripts must not source a writable configuration file. | `sk_source_trusted_config` in `common.sh`; both backup scripts use it; flags-over-file order in `sk-pg-backup`; helper-missing guard (exit 5); static guard test. | Detector flags `source "$CONFIG_FILE"` at two lines | `common-sh` suite 29 to 39 passed; pg 15 and mysql 4 config tests pass; detector reports only `SK_LIB` | Keep |
| 4 | P2-04 `054c45c` | The non-root audit fallback trusts a predictable `/tmp` path. | Fallback moved under the validated temporary base, 0700, owner/mode/symlink checked, audit skipped with one warning otherwise. | Previous library: `/tmp/linux-skills-<user>` created 755 with a 644 log; 3 new cases fail | `common-sh` suite 42 passed (foreign-owner and root-branch cases skipped, not passed, on a non-root run) | Keep |
| 5 | P2-05 `9ce3518` | Evidence command prints nothing on dnf5 hosts. | Reference split by dnf generation; journal pattern `dnf*automatic*`; advisory listing and reboot ownership added. | `journalctl -u dnf-automatic` gives `-- No entries --`; `-u dnf5-automatic` shows the 06:11 run | `-u 'dnf*automatic*'` shows the run on the same host | Keep (RHEL half is documentation-sourced) |
| 6 | P2-06 `62f2e56` | PostgreSQL needs the private-dump rule and a verified restore procedure like MySQL. | Added both to `backup-and-pitr.md`, linked from `SKILL.md`; stdin form for 0600 files, `-j` exception, no `ON_ERROR_STOP` for globals (from the manuals). | One-sentence scratch-restore advice | Procedure with timing and reconciliation; never run in a lab | Keep, labelled untested |
| 7 | P2-07 `221871c` | Touched skills with no fixtures hide routing drift. | 15 fixtures (3 skills x 3 positives + 2 owned negatives). Ranker unchanged. | 80 fixtures; P@1 67/80 (0.838); coverage 11 of 48 | 95 fixtures; P@1 82/95 (0.863); P@3 95/95; coverage 14 of 48; all owned-negative checks pass | Keep |
| 8 | P2-08 `fc0c8af` | Link, anchor and heading debt can be repaid without inventing content. | Retargeted 10 anchors, replaced 5 outside-repository links with plain-text names, renamed 10 second `References` headings to `Reference files`, replaced a stale PHP path. | 5 paths, 10 anchors, 10 skills with duplicates | 0, 0, 0 on the same parser | Keep |
| 9 | P2-09 `1ef490f` | The ten expired source rows can be re-verified at their primary sources. | Opened each source; updated dates only on opened rows; narrowed two to partial; added `currency.md`; fixed PostgreSQL RHEL 9 install guidance. | 10 expired structured rows | 0 expired; 8 verified, 2 partial | Keep |
| 10 | P2-10 `d42cd1f` | The MySQL backup procedure should say what the account needs. | Added privilege table, example grant and the schema-visibility trap, sourced from the MySQL 8.4 manual. | No privilege guidance | Section added; grants not run against a server | Keep, labelled untested |

## Failed or corrected attempts (recorded, not hidden)

- The first `tests/test_ssh_dropin_precedence.py` helper cut off the text it needed to read and failed
  for its own reason; fixed before the baseline was recorded. The recorded baseline is the corrected test.
- The first pg stub ignored `--file=`, so the partial-dump case passed against the previous script and
  did not demonstrate the defect. The stub was made faithful (writes to `--file` or standard output, as
  `pg_dump` does) and the case then failed against the previous script as intended. The baseline claim
  in `00-scope-and-evidence.md` that a failed `pg_dump` left a partial file is therefore demonstrated
  by the corrected fixture, not by the first run.
- The first version of the pg tests used whichever `common.sh` was installed on the host (the host has an
  older copy), so on that machine they exercised old library code. Fixed in P2-03: the fixture points the
  script at the repository library and a test fails if that line changes.
- A run of the new audit cases against the previous library created `/tmp/linux-skills-peter` on the host.
  It was removed (one log file and the empty directory), and its existence is the evidence for D4.
- A `rm -rf` and a `grep` whose pattern text contained the same string were stopped by the host's
  destructive-command gate. Neither was needed; both were rewritten, and the gate was not bypassed.
- `kaizen_metrics.py --output` also prints the whole JSON to standard output: noted for the next cycle.

## Not tried

An installer `--list` staleness marker (see `06-next-cycle.md`), the `sk-capture` output path, and
a container run of the MySQL lab were not tried: the first would be an eleventh item; the other two
need a container or root, which this pass may not create.
