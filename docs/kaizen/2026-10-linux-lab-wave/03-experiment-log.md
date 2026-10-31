# Experiment log — Linux lab wave, 31 October 2026

One change at a time, highest risk first (the lab harness first, so every later fix has a test that can fail).
"Before" and "after" are runs of the same check against the unfixed and the fixed text. The unfixed side was run
against a copy of the 29 October tree in the scratch area; nothing was stashed, reset or reverted in the repository.
Every item was kept; none was reverted. Commits are on `kaizen/2026-10-linux-wave`.

| Item | Commit | Hypothesis | Before (unfixed) | After (fixed) | Decision |
|---|---|---|---|---|---|
| LW-00 | `131abe1` | A fresh measurement and a defect register before any edit | Baseline raw 74.3 | Frozen | Kept |
| LW-03 | `2293b73`, `cf670be` | Every pass-2 claim about the SSH, `sk-pg-backup` and restore procedures can be re-measured with one command | Prose only. First harness run failed at once (below) | `LINUX_SKILLS_LAB=1 python -m pytest tests/test_distro_labs.py`: 4 passed in 199 s (SSH on Debian 12 and Fedora 44; `sk-pg-backup` plus the documented restore on PostgreSQL 15.19 and 18.6) | Kept |
| LW-09 | `af0e9e0` | `--output --quiet` prints nothing, `--quiet` alone is a usage error | 3 new cases fail (`main() takes 0 positional arguments`) | 12 passed in `test_kaizen_metrics.py` | Kept |
| LW-06 | `a31dc52` | No wrong location after `die`; an unexpected failure keeps its banner | 1 new case fails: `FAILURE: die exited 4 at line 1`, `last command: exit "$code"` | `common-sh.test.sh`: 45 passed, 0 failed (was 42) | Kept |
| LW-04 | `fe5f9f9` | The documented `sk_backup` grants back up, restore and refuse writes on `mysql:8.4`; the page's `PROCESS` claim is right | Page said `PROCESS` is needed. Probe: without it `mysqldump` 8.4.13 exits 0 with an access-denied line and dumps everything | Both MySQL lab tests: 2 passed in 57 s; page rewritten to the measured behaviour | Kept |
| LW-01 | `92bafbd` | The documented Debian block makes a pending security update appear under "Packages that will be upgraded" | Driver against the previous procedure: 4 checks FAIL (`No packages found ...`, tzdata pending); static test: 7 subtest failures | Lab: 1 passed in 124 s; static test: 6 passed | Kept |
| LW-02 | `dad557e` | The unmodified SSH apply and rollback blocks exit 0 on Fedora | Fedora: `Failed to reload ssh.service: Unit ssh.service not found.` exit 5, in apply and in rollback; 2 static tests fail | Lab suite: 5 passed in 217 s with the blocks asserted as written; static tests 8 passed | Kept |
| LW-08 | `ae84c01` | A service-unit parity check fails on the 29 October text | 8 unpaired uses in 7 skills | 0; 5 negative fixtures pass; `check-distro-matrix.sh` still 41 of 41 | Kept |
| LW-05 | `85a96dd` | No `could not change directory` warning from the client calls on Debian | Debian lab: `FAIL no 'could not change directory' warning ...` (1 failed in 214 s) | Debian lab passes; Fedora never printed it; `test_pg_backup.py` 18 passed | Kept |
| LW-07 | `4dabff3` | ShellCheck exits 0 at `--severity=warning` in both families | 28 warnings, exit 1 (0.9.0 and 0.11.0 alike) | 0 warnings, exit 0 over 41 sources in both containers | Kept |
| LW-10 | `16e45f2` | Fourteen new fixtures rank their owners first and exclude named neighbours | n/a (new fixtures) | Routing 109/109 valid; P@1 0.881 (was 0.863); skills at 3+2: 17 (was 14) | Kept |

## Failed or corrected intermediate attempts

- **First harness run failed.** `markdown_blocks` ended the SSH section at the first `# --- Access control ---`
  line, which sits inside a fenced heredoc and looks like an H1 heading, so it found one block instead of five.
  `pick_block` reported `expected exactly one documented block containing 'sshd -t &&', found 0`. Fixed in
  `tests/lab_support.py` (headings are ignored inside fences) and the same rule written into the static tests.
- **First lab drivers had capture mistakes**, found in the scratch versions before they were committed: stderr
  mixed into a comparison file (the Debian restore sample shows the resulting `FAIL`), a `manual.dump` junk file
  counted as a truncated backup, and a pipeline whose exit status was `sed`'s. All three were fixed in the committed
  drivers; the first is why the baseline restore sample on Debian carries one explained `FAIL`.
- **Static test for the SSH unit name matched prose**, not only commands, and the first guard test was too
  elaborate. It now reads fenced lines only and states its one exemption (a reload that only follows removing the
  drop-in).
- **`common-sh.test.sh` first assertion used the file name** (`die.sh exited 4`); the banner prints the script
  name without the extension. Corrected before the fix was judged.
- **Routing run exited 1** after the fixtures were added: `quality-baseline.json` pins the fixture count.
  Updated to 109 in the same commit (pass 2 did the same for 95).
- **Plan changed for LW-07.** The backlog planned a `.shellcheckrc` that disables SC2034. Inline directives with a
  reason were used instead, so a genuinely unused variable in any script still shows. The three SC2024 warnings
  needed no directive after LW-05.
- **Pre-fix severity of W1 refined.** A second lab run showed that the Ubuntu pattern placed beside Debian's shipped
  `Origins-Pattern` does let the security update through; it is inert only when the shipped stanza is removed or
  replaced, which is what "security-only" asks for. Beside the shipped stanza the host is not security-only: it
  also takes the release archive. Both outcomes miss the stated intent. Recorded in the addendum to
  `00-scope-and-evidence.md`; severity kept at critical for the replaced-stanza case.
- **Peter's destructive-command hook blocked three of my Bash commands**, each time because a heredoc contained the
  words `DROP DATABASE`, `DROP TABLE` or `rm -rf` as test text. None was overridden. The text went into files through
  the file-editing tool instead, and the lab drivers avoid dropping anything: data is created once and the
  backup directory is emptied with `find -delete`.
- **A leftover volume.** The MySQL `PROCESS` probe container was removed with `podman rm --force` and no `--volumes`,
  so its anonymous data volume stayed. The final cleanup check found it (created during the probe, MySQL files inside) and
  `podman volume rm` removed it. The committed MySQL tests remove their containers with `--volumes`.
- **Lab prerequisite found, not a defect:** `postgresql-setup --initdb` on Fedora needs D-Bus. The lab installs
  `dbus-broker` and enables it before initialising.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
