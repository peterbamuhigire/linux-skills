# Rootkit scanning: rkhunter and chkrootkit

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

> `[GROUNDING-GAP: rootkit scanners — grounded on upstream man pages
> (rkhunter(8), chkrootkit(8)) and project docs; deepen with UNIX & Linux
> System Administration Handbook]`
>
> rkhunter and chkrootkit are **absent from the book corpus** this engine is
> grounded on. The content below is authored from standard upstream usage
> (the rkhunter and chkrootkit man pages and project documentation) and is
> kept deliberately conservative. Verify against your distro's packaged
> version before relying on exact flag behaviour, and deepen with the
> *UNIX & Linux System Administration Handbook* (Nemeth et al.) compromise
> chapter when promoting this to fully-grounded.

This file is the deep reference for **host-based rootkit detection** on both
families. It complements the AIDE/auditd reference: AIDE answers *which files
changed*, auditd answers *who did what*, and the rootkit scanners answer
*does this host show the known fingerprints of a rootkit or a compromised
binary?* All three are signals, not verdicts.

- **rkhunter** (Rootkit Hunter) — compares system binaries against a stored
  property baseline (hashes, perms, inode), checks for known rootkit files
  and strings, hidden files/ports, and common backdoor signatures. Runs on a
  schedule; benefits from a `--propupd` baseline taken on a clean host.
- **chkrootkit** — a set of shell/C checks that look for known rootkit
  signatures, trojaned system commands, and suspicious states (e.g. an
  interface in promiscuous mode, deleted-but-running login records).

Use **both**: they overlap but catch different things, and agreement between
them on the same finding raises confidence.

## Table of contents

- [Where this fits in the IDS workflow](#where-this-fits-in-the-ids-workflow)
- [Distro support](#distro-support)
- [Install](#install)
- [rkhunter: first run and the property baseline](#rkhunter-first-run-and-the-property-baseline)
- [rkhunter: configuration and reducing false positives](#rkhunter-configuration-and-reducing-false-positives)
- [rkhunter: running a scan and reading the report](#rkhunter-running-a-scan-and-reading-the-report)
- [chkrootkit: running a scan and reading the output](#chkrootkit-running-a-scan-and-reading-the-output)
- [Common false positives on both families](#common-false-positives-on-both-families)
- [Scheduling: systemd timer and cron](#scheduling-systemd-timer-and-cron)
- [Interpreting warnings: a triage flow](#interpreting-warnings-a-triage-flow)
- [Integrating with the existing IDS layers](#integrating-with-the-existing-ids-layers)
- [Sources](#sources)

---

## Where this fits in the IDS workflow

The existing skill already runs AIDE (drift), auditd (attribution), and
fail2ban (perimeter). Rootkit scanners add a fourth, **signature/heuristic**
layer:

| Question | Tool |
|---|---|
| "Has `/usr/bin/ssh` changed since baseline?" | AIDE *or* rkhunter (property check) |
| "Does this host match a known rootkit fingerprint?" | rkhunter / chkrootkit |
| "Is any interface in promiscuous mode (sniffer)?" | chkrootkit |
| "Are there hidden processes or hidden listening ports?" | rkhunter |
| "Who replaced the binary, and when?" | auditd |

Rule of thumb: **scanners narrow the search; AIDE and auditd give the
forensic detail.** A scanner warning is a prompt to investigate, never a
conclusion on its own.

---

## Distro support

Both scanners are packaged for both families and use the same command-line
interface across distros. On the RHEL family the package usually comes from
**EPEL** (same repository fail2ban needs).

| Concept | Debian/Ubuntu | RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) |
|---|---|---|
| Install rkhunter | `apt install rkhunter` | `dnf install rkhunter` (**EPEL** on RHEL/Rocky/Alma/Oracle; main on Fedora) |
| Install chkrootkit | `apt install chkrootkit` | `dnf install chkrootkit` (**EPEL**) |
| rkhunter config | `/etc/rkhunter.conf` (+ `/etc/rkhunter.conf.local`) | same paths |
| rkhunter data/baseline | `/var/lib/rkhunter/db/` | same |
| rkhunter log | `/var/log/rkhunter.log` | same |
| chkrootkit binary | `/usr/sbin/chkrootkit` | `/usr/sbin/chkrootkit` |
| Debian auto-scan | `/etc/cron.daily/rkhunter`, `/etc/default/rkhunter` | (no Debian helper; use systemd timer or cron below) |

**RHEL-family note:** enable EPEL first (`dnf install epel-release` on
RHEL/Rocky/Alma/Oracle; not needed on Fedora). Debian/Ubuntu ship a
`/etc/cron.daily/rkhunter` wrapper and an `/etc/default/rkhunter` toggle
(`CRON_DAILY_RUN`, `APT_AUTOGEN`); the RHEL packages do not, so on the RHEL
family use the systemd timer or cron entry shown below.

---

## Install

Debian/Ubuntu:

```bash
sudo apt update
sudo apt install rkhunter chkrootkit
```

RHEL family (enable EPEL first on RHEL/Rocky/Alma/Oracle; skip on Fedora):

```bash
sudo dnf install epel-release        # RHEL/Rocky/Alma/Oracle only
sudo dnf install rkhunter chkrootkit
```

After install, update rkhunter's data files (known-rootkit definitions and,
optionally, hashes of packaged binaries) before the first scan:

```bash
sudo rkhunter --update                 # pull current definition files
sudo rkhunter --versioncheck           # is rkhunter itself current?
```

`--update` may report "Update failed" if the mirror list is stale on an older
package; that is non-fatal — the local checks still run.

---

## rkhunter: first run and the property baseline

rkhunter stores a **file-property database** (`/var/lib/rkhunter/db/`) and
compares the live system against it on each scan. You must establish this
baseline on a host you trust:

```bash
# CRITICAL: run on a KNOWN-CLEAN host — ideally right after provisioning,
# before the box is exposed, or immediately after patching from trusted repos.
sudo rkhunter --propupd
```

`--propupd` records the current hash, permissions, inode, and other
properties of every monitored binary as "good". If you run it on a
compromised host, you baseline the compromise as normal — exactly the AIDE
`aideinit` hazard.

**When to re-run `--propupd`:** after any *legitimate* change to system
binaries — a package upgrade, a kernel update, a deliberate replacement.
After patching, expect rkhunter to warn about the changed binaries on the
next scan; once you have confirmed the change was your package manager's
doing, re-baseline:

```bash
sudo rkhunter --propupd
sudo rkhunter --check --sk --rwo        # confirm the property warnings clear
```

---

## rkhunter: configuration and reducing false positives

Edit **`/etc/rkhunter.conf.local`** (preferred over editing
`/etc/rkhunter.conf` so package upgrades do not clobber your changes; if your
package does not ship a `.local`, create it):

```bash
sudo nano /etc/rkhunter.conf.local
```

Useful directives:

```conf
# Mail destination for the cron/timer wrapper
MAIL-ON-WARNING=root@localhost

# Allow specific hidden files/dirs that legitimately exist (false positives).
# One per line; these are exact paths.
ALLOWHIDDENDIR=/etc/.git
ALLOWHIDDENFILE=/usr/share/man/man5/.k5login.5.gz

# Some daemons legitimately use scripts where a binary is expected.
# Permit specific known-good ones instead of disabling the whole test.
SCRIPTWHITELIST=/usr/bin/egrep
SCRIPTWHITELIST=/usr/bin/fgrep
SCRIPTWHITELIST=/usr/bin/ldd
SCRIPTWHITELIST=/usr/bin/which

# Packages can change binaries legitimately. Let rkhunter ask the package
# manager whether a changed file belongs to a package before warning:
PKGMGR=DPKG            # Debian/Ubuntu
# PKGMGR=RPM           # RHEL family

# Permit specific processes/ports if a known service trips the hidden-port or
# deleted-binary tests (document WHY in a comment every time you add one):
# ALLOWPROCDELFILE=/usr/sbin/mysqld
# PORT_WHITELIST=TCP:8080
```

Set `PKGMGR` correctly for the family — it is the single biggest reducer of
false positives, because it tells rkhunter that a hash change matching the
installed package version is expected, not suspicious.

Validate the config after editing:

```bash
sudo rkhunter -C        # --config-check; reports syntax errors
```

**Discipline:** whitelist the *specific* path/port/process that is a proven
false positive. Never disable an entire test group to silence one warning —
that creates a blind spot an attacker can hide behind. Record every
whitelist addition (date + reason) so a reviewer can audit your suppressions.

---

## rkhunter: running a scan and reading the report

```bash
# Full check. --sk skips the "press ENTER" pause between test groups
# (essential for cron/timer). --rwo = report warnings only.
sudo rkhunter --check --sk --rwo
```

Output groups warnings like:

```
[ Rootkit Hunter version 1.4.6 ]

Checking system commands...
  /usr/bin/ssh                       [ Warning ]
Checking for rootkits...
  Suckit Rootkit                     [ Not found ]
Checking the network...
  Checking for promiscuous interfaces[ None found ]

Warning: The file properties have changed:
         File: /usr/bin/ssh
         Current hash: 0fb...   Stored hash: a31...
```

The full log (every test, not just warnings) is at **`/var/log/rkhunter.log`**:

```bash
sudo grep -A2 '\[ Warning \]' /var/log/rkhunter.log
sudo grep -c '\[ Warning \]'  /var/log/rkhunter.log     # quick warning count
```

### Exit status

rkhunter exits **non-zero when warnings were found** (commonly `1`). A
scheduled wrapper should treat non-zero as "human, look at the log", not as a
script failure to be hidden. The `sk-rootkit-scan` wrapper follows this:
exit 0 = clean, exit 1 = warnings to triage.

---

## chkrootkit: running a scan and reading the output

```bash
# -q = quiet: print only INFECTED / suspicious lines, suppress the long
# "not infected" / "not found" list.
sudo chkrootkit -q
```

A clean run with `-q` prints little or nothing. Without `-q` you get one line
per check:

```
Checking `ls'...               not infected
Checking `ifconfig'...         not infected
Checking `bindshell'...        not infected
eth0: PACKET SNIFFER(/sbin/dhclient[812])
Searching for suspicious files and dirs ... nothing found
```

Lines to act on contain `INFECTED`, `Vulnerable`, or `suspicious`. The
`PACKET SNIFFER` line above is the classic false positive (see below).

chkrootkit has **no baseline** — it is purely signature/heuristic, so it
needs no `--propupd` equivalent and nothing to keep clean. It is also the
slower of the two; the `sk-rootkit-scan --quick` flag skips it when you only
want the fast rkhunter pass.

---

## Common false positives on both families

Both tools are conservative-by-design and will flag legitimate states. The
recurring ones:

| Warning | Usual benign cause | What to do |
|---|---|---|
| rkhunter: "file properties have changed" on `/usr/bin/*`, `/bin/*` | A package upgrade replaced the binary | Confirm via `dpkg -V` / `rpm -V`, then `rkhunter --propupd` |
| chkrootkit: `eth0: PACKET SNIFFER(...dhclient...)` | DHCP client puts the NIC in promiscuous mode | Expected on DHCP hosts; verify the PID is `dhclient` |
| rkhunter: "hidden file/dir found" | `.git`, `.k5login`, snap/AppArmor dotfiles | `ALLOWHIDDENFILE` / `ALLOWHIDDENDIR` the exact path |
| rkhunter: "script replaced a command" | Distro ships `egrep`/`which` as scripts | `SCRIPTWHITELIST` the exact path |
| chkrootkit: `Checking 'bindshell'... INFECTED (PORTS: 465)` | A real service (e.g. SMTPS) on a port chkrootkit associates with a backdoor | Confirm the listener with `ss -tlnp`; it is the false positive if it is your service |
| Either tool inside a container/VM | Virtualisation artefacts, missing /dev nodes | Note the environment; many checks assume bare metal |

The pattern: **identify the responsible package/process, prove it is
legitimate, then whitelist the specific item** — do not blanket-disable.

---

## Scheduling: systemd timer and cron

Run rkhunter daily and chkrootkit (optional) weekly, mailing only on
findings. Two equivalent approaches:

### systemd timer (works on both families)

```bash
# 1. The scan unit
sudo tee /etc/systemd/system/rootkit-scan.service > /dev/null <<'EOF'
[Unit]
Description=Daily rkhunter rootkit scan
Documentation=man:rkhunter(8)

[Service]
Type=oneshot
# --rwo: report warnings only; --sk: no interactive pause; non-zero = warnings
ExecStart=/usr/bin/rkhunter --check --sk --rwo --nocolors
# Mail the log if rkhunter exited non-zero (warnings present)
ExecStopPost=/bin/sh -c 'test "$EXIT_STATUS" = 0 || mail -s "rkhunter WARNINGS $(hostname)" root < /var/log/rkhunter.log'
Nice=10
IOSchedulingClass=idle
EOF

# 2. The timer
sudo tee /etc/systemd/system/rootkit-scan.timer > /dev/null <<'EOF'
[Unit]
Description=Run rkhunter daily

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=900
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now rootkit-scan.timer
systemctl list-timers rootkit-scan.timer --no-pager
```

### cron (classic)

```bash
sudo tee /etc/cron.d/rootkit-scan > /dev/null <<'EOF'
# m h dom mon dow user  command
30 3 * * *   root  /usr/bin/rkhunter --check --sk --rwo --nocolors 2>&1 | grep -q Warning && mail -s "rkhunter WARNINGS $(hostname)" root < /var/log/rkhunter.log
15 4 * * 0   root  /usr/sbin/chkrootkit -q 2>&1 | grep -E 'INFECTED|suspicious' && mail -s "chkrootkit FINDINGS $(hostname)" root
EOF
```

On **Debian/Ubuntu** you can instead just enable the packaged wrapper:

```bash
sudo nano /etc/default/rkhunter
# CRON_DAILY_RUN="true"
# APT_AUTOGEN="true"          # auto-refresh the property DB after apt upgrades
```

The RHEL packages have no such wrapper — use the systemd timer or cron above.

Ensure an MTA (e.g. `msmtp`, see `linux-mail-server`) is configured so root
mail reaches a human, exactly as for the AIDE nightly check.

---

## Interpreting warnings: a triage flow

1. **rkhunter "file properties have changed" on a system binary** → first ask
   *did a package update run recently?*
   ```bash
   # Debian/Ubuntu
   grep -i ' install \| upgrade ' /var/log/dpkg.log | tail
   dpkg -V coreutils openssh-client          # verify against package metadata
   # RHEL family
   rpm -V coreutils openssh-clients          # blank output = matches package
   ```
   If the change matches the installed package and you trust the repo,
   `rkhunter --propupd` and move on. If `dpkg -V`/`rpm -V` shows a mismatch
   the package manager did **not** cause → treat as the AIDE binary-drift
   CRITICAL path: assume compromise, preserve evidence, go to IR.

2. **chkrootkit `INFECTED` / rkhunter "known rootkit found"** → do not reboot,
   do not "clean". Snapshot the host (memory + disk if you can), pull the
   audit and AIDE logs off-box, and treat as an incident. Confirm with the
   other scanner — agreement raises confidence; disagreement often means a
   false positive in one tool.

3. **Promiscuous-mode / packet-sniffer warning** → confirm the owning PID:
   ```bash
   sudo ss -0 -p 2>/dev/null; ip -d link show
   ```
   If it is `dhclient` or a known monitoring agent, whitelist it. If it is an
   unexpected process, investigate.

4. **Hidden file/port/process** → identify the owner before whitelisting.
   ```bash
   sudo ss -tlnp           # who owns the "hidden" port?
   ls -la <hidden path>    # what is the hidden file?
   ```

5. **Both tools clean** → reassuring but not proof. Heuristic scanners miss
   novel or in-memory-only rootkits. Keep AIDE and auditd running.

---

## Integrating with the existing IDS layers

Rootkit scanning is one signal among four. Wire it into the same workflow as
fail2ban/AIDE/auditd:

- **Pair scanner property-warnings with AIDE.** Both flag binary drift; if
  rkhunter warns on `/usr/sbin/sshd` and AIDE *also* shows a hash change on
  the same file, that correlation is strong. Run `sk-file-integrity-check`
  (this skill) on the same paths the scanner flagged.
- **Attribute with auditd.** When a binary changed, `ausearch -f <path>` (see
  `references/aide-and-auditd.md`) tells you which process and `auid` touched
  it and when — the *who/when* the scanners cannot give you.
- **Baseline discipline mirrors AIDE.** `rkhunter --propupd` is to rkhunter
  what `aideinit` is to AIDE: only re-baseline after confirmed-legitimate
  change, and log every re-baseline:
  ```bash
  echo "$(date -Iseconds) rkhunter --propupd after openssh upgrade" \
      | sudo tee -a /var/log/linux-skills/rootkit-baseline-updates.log
  ```
- **Ship the logs off-box.** As with auditd, an attacker with root can edit
  `/var/log/rkhunter.log`. Forward it to a central collector (see
  `linux-observability` `log-forwarding.md`).
- **Fast path.** `sudo sk-rootkit-scan` runs both tools, summarises the
  warning counts, and points triage at AIDE/auditd. `--quick` runs rkhunter
  only; `--update-baseline` runs a gated `--propupd`.

---

## Sources

> `[GROUNDING-GAP: rootkit scanners — grounded on upstream man pages
> (rkhunter(8), chkrootkit(8)) and project docs; deepen with UNIX & Linux
> System Administration Handbook]`

- Man pages: `rkhunter(8)`, `rkhunter.conf(5)`, `chkrootkit(8)`.
- rkhunter project: https://rkhunter.sourceforge.net/ (README, `rkhunter.conf`
  inline documentation, FAQ on false positives).
- chkrootkit project: https://www.chkrootkit.org/ (README, check list).
- Debian/Ubuntu packaging: `/etc/default/rkhunter`,
  `/etc/cron.daily/rkhunter` wrapper behaviour.
- EPEL packaging notes for the RHEL family (rkhunter, chkrootkit).
- To deepen (not yet in the book corpus): *UNIX & Linux System Administration
  Handbook* (Nemeth, Snyder, Hein, Whaley, Mackin) — compromise detection and
  rootkit chapters.
