---
name: linux-package-management
description: Use when installing, upgrading, pinning, removing, or diagnosing packages and repositories with apt, dnf, snap, Flatpak, or automatic updates. Use linux-server-provisioning for a complete new-server sequence and linux-config-management for fleet-wide desired state.
license: MIT
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Package Management

## Distro support

This skill covers **both supported families**. The `apt`/`snap`/`unattended-upgrades`
commands below are the **Debian/Ubuntu** column; the **RHEL family** (Fedora,
RHEL, CentOS Stream, Rocky, Alma, Oracle) equivalents are in the matrix and the
[dnf quick reference](#rhel-family--dnf-quick-reference) further down.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package manager | `apt` / `apt-get` | `dnf` (`yum` on EL7) |
| Low-level DB | `dpkg` | `rpm` |
| Install / remove | `apt install` / `apt remove` | `dnf install` / `dnf remove` |
| Refresh metadata | `apt update` | `dnf makecache` (auto on most ops) |
| Upgrade all | `apt upgrade` / `full-upgrade` | `dnf upgrade` |
| Remove orphans | `apt autoremove` | `dnf autoremove` |
| Search / info | `apt search` / `apt show` | `dnf search` / `dnf info` |
| Which repo / policy | `apt-cache policy` | `dnf --showduplicates list`, `dnf repolist` |
| File → package | `dpkg -S <file>` | `rpm -qf <file>` / `dnf provides <file>` |
| Package → files | `dpkg -L <pkg>` | `rpm -ql <pkg>` |
| Hold / pin | `apt-mark hold` | `dnf versionlock` (plugin) / `exclude=` |
| Pending reboot | `/var/run/reboot-required` | `dnf needs-restarting -r` |
| Auto security updates | `unattended-upgrades` | `dnf-automatic` |
| Sandboxed apps | `snap` | `flatpak` (desktop) / native dnf (server) |
| Portable desktop apps | AppImage + `fuse3`; legacy AppImages may need `libfuse2`/`libfuse2t64` | AppImage + `fuse3`; app-specific libs such as `mpv-libs` |
| Extra repos | PPA / `.sources` in `sources.list.d` | `.repo` in `/etc/yum.repos.d/`, **EPEL** |

In `sk-*` scripts, **do not hardcode either column** — call the `common.sh`
primitives (`pkg_install`, `pkg_update`, `pkg_is_installed`, `ensure_epel`,
`svc_name`) which resolve to the right command for the detected family. See
[`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

**RHEL-family gotchas:** EPEL must be enabled (`ensure_epel`) for many extra
packages on RHEL/Rocky/Alma — but **not** on Fedora, which ships them in the
main repos. Fedora 41+ uses **dnf5**; RHEL 9 and rebuilds use dnf4 (command
surface is the same for everything here).

<!-- dual-compat-start -->
## Use when

- Installing, upgrading, holding, pinning, or auditing packages.
- Managing `snap` lifecycle or unattended-upgrades behavior.
- Investigating package-source or dependency issues on Ubuntu/Debian.
- Preparing a Linux workstation to run portable desktop packages such as AppImage.

## Do not use when

- The task is application deployment rather than package lifecycle management.
- The task is security hardening beyond package hygiene; use `linux-server-hardening`.

## Required inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Distribution family/release and package manager state | `/etc/os-release` and package database | required | Limit the result to read-only discovery commands. |
| Package names, repository definition, or update symptom | Operator or host | required | Ask for the exact package/repository; do not run a broad upgrade. |
| Maintenance, reboot, and service-impact constraints | Change owner | required for upgrade/removal | Stop before mutation and return an impact checklist. |

## Workflow

1. Inspect current package state, holds, and candidate versions.
2. Apply the smallest package operation that satisfies the goal.
3. Follow the matching workflow below for maintenance, held packages, unattended-upgrades, or third-party repos.
4. Verify package state and service impact after the change.
5. Stop if transaction simulation shows unintended removals, repository trust is unverified, or the maintenance boundary is missing.
6. Recover by using the recorded package transaction and configuration backup to downgrade, reinstall, or restore the previous repository state, then recheck services.

## Quality standards

- Prefer official repositories and explicit package intent.
- Keep upgrades observable and reversible where possible.
- Verify both package state and runtime health after updates.

## Anti-patterns

- Running a broad upgrade without checking holds or service impact. Fix: inspect candidates, holds, transaction scope, and reboot needs first.
- Adding an unverified third-party repository. Fix: verify publisher, signing key fingerprint, supported release, and exact source entry.
- Treating automatic updates as active without evidence. Fix: inspect timer/service state and recent package-manager logs.
- Mixing `apt` and `dnf` instructions. Fix: detect the family and use only its package database and repository format.
- Removing a package without reviewing dependants and configuration retention. Fix: simulate the transaction and document purge/rollback consequences.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Package transaction or diagnosis | System operator | Installed/candidate versions and repository source match the stated intent. |
| Impact and recovery note | Change reviewer | Names affected services, reboot requirement, rollback/downgrade feasibility, and retained config. |
| Verification record | Operations handoff | Package database is consistent and affected services pass health checks. |

## References

- [`references/apt-reference.md`](references/apt-reference.md)
- [`references/snap-reference.md`](references/snap-reference.md)
- [`references/unattended-upgrades-reference.md`](references/unattended-upgrades-reference.md)
- [`references/dnf-reference.md`](references/dnf-reference.md)

## Evidence Produced

| Artefact | Acceptance condition |
|---|---|
| Package-operation evidence | Includes simulation/transaction output, installed and candidate versions, repository provenance, relevant update logs, and service checks. |

## Capability contract

Read access to OS and package state is required. Package mutation, repository trust changes, reboot, or service restart requires explicit authority. Never disable signature checks or accept an unknown key to make a transaction pass.

## Degraded mode

Without host execution, return family-correct inspection and transaction commands with versions unresolved and runtime checks marked `not assessed`. Without a maintenance window, stop before disruptive upgrades.

## Decision rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Distribution package available | Prefer signed distribution repository | Unmaintained or conflicting sources. |
| Vendor repository required | Pin scope and verify key/release support | Repository takeover or unintended upgrades. |
| Security update affects critical service/kernel | Schedule controlled update and health/reboot checks | Silent outage or unbooted security fix. |

## Worked example

For a held Nginx update on Ubuntu, inspect `apt-cache policy`, holds, changelog, and simulated transaction; schedule the approved update, validate Nginx configuration, apply it, confirm the installed version and HTTP health, and state whether a reboot remains required.

<!-- dual-compat-end -->

**This skill is self-contained.** Every command below is a standard tool on
its family — Debian/Ubuntu (`apt`, `apt-get`, `apt-mark`, `apt-cache`, `snap`,
`unattended-upgrade`, `dpkg`) or RHEL (`dnf`, `rpm`, `dnf-automatic`,
`flatpak`). The `sk-*` scripts in the **Optional fast path** section are
convenience wrappers — never required.

This skill owns package operations on both families: **apt + snap +
unattended-upgrades** on Debian/Ubuntu, and **dnf + flatpak + dnf-automatic**
on the RHEL family.

It does **not** own:

- **Language-specific package managers** (`npm`, `pip`, `composer`,
  `cargo`) — managed by site deployment skills.
- **The linux-skills repo itself** — `linux-site-deployment` via
  `update-all-repos`.

Informed by *Mastering Ubuntu* (modern apt/snap practice) and the
Canonical *Ubuntu Server Guide*.

---

## When to use

- Installing new packages on a server.
- Running a safe `apt update` / `apt upgrade` cycle.
- Investigating held packages or broken dependencies.
- Auditing snap revisions and refresh policies.
- Configuring or verifying `unattended-upgrades`.
- Removing unused packages cleanly.

## When NOT to use

- Installing dependencies *inside* a deployed application — use
  `linux-site-deployment`.
- Snap applications from the user's desktop perspective — this is server
  admin only.

---

## Standing rules

1. **Never run `apt upgrade` without a /etc snapshot.** Snapshot → upgrade
   → diff. So you can compare configs after.
2. **`unattended-upgrades` is mandatory on every production server.**
   Security patches go in every night. No exceptions.
3. **Review the list before `apt upgrade`.** Surprise dependencies can
   pull in hundreds of MB. Run `apt list --upgradable` first.
4. **Hold packages explicitly when needed.** `apt-mark hold <pkg>` with a
   comment in a tracking file explaining *why*.
5. **PPAs are audited, not added casually.** Every added PPA is a new
   trust relationship.
6. **Kernel upgrades require a reboot plan.** Check
   `/var/run/reboot-required` after every upgrade.
7. **Snap refresh schedules are configured, not disabled.** Disabling
   auto-refresh creates a silent security debt.

---

## Quick reference — manual commands

Load only the package-family reference needed for the task:

- [`references/apt-reference.md`](references/apt-reference.md) for apt, dpkg, Debian repositories, pinning, and dependency recovery.
- [`references/snap-reference.md`](references/snap-reference.md) for channels, holds, interfaces, services, and rollback.
- [`references/unattended-upgrades-reference.md`](references/unattended-upgrades-reference.md) for Debian-family automatic security updates and evidence.
- [`references/dnf-reference.md`](references/dnf-reference.md) for dnf/rpm, repositories, EPEL, version locks, reboot checks, and `dnf-automatic`.

---

## AppImage desktop support

AppImage is a common way to distribute Linux desktop applications outside the
native package repositories. Treat it as a **workstation compatibility layer**,
not a production server packaging standard. AppImages are often self-contained,
but many still depend on host runtime libraries.

Baseline support:

```bash
# Debian/Ubuntu workstation
sudo apt install -y fuse3 desktop-file-utils

# Legacy AppImages that require libfuse.so.2 may also need one of:
sudo apt install -y libfuse2     # Debian/older Ubuntu
sudo apt install -y libfuse2t64  # newer Ubuntu releases

# Fedora workstation
sudo dnf install -y fuse3 desktop-file-utils

# RHEL/Rocky/Alma workstation
sudo dnf install -y fuse3 desktop-file-utils
```

Media-heavy AppImages may need distro libraries for playback engines or codecs.
On Fedora, Flutter/Electron media apps commonly need:

```bash
sudo dnf install -y mpv-libs
```

Run and diagnose:

```bash
chmod +x ./SomeApp.AppImage
./SomeApp.AppImage

# If the AppImage wrapper is broken, inspect the payload.
./SomeApp.AppImage --appimage-extract
cd squashfs-root
ldd ./<real-binary> | grep 'not found'
```

If the bundled `AppRun` is malformed or assumes the wrong path, install the
extracted payload under `~/Applications/<AppName>/` and create a launcher in
`~/.local/bin/` plus a desktop entry in `~/.local/share/applications/`.

Do not add random AppImage download sites as trusted package sources. Prefer the
vendor's official release page, record the source URL and checksum when installing
for someone else, and use native packages or Flatpak when an audited distro
package exists.

---

## Typical workflows

### Workflow: Weekly maintenance cycle

```bash
# 1. Refresh the index
sudo apt update

# 2. What's waiting?
apt list --upgradable 2>/dev/null | wc -l
apt list --upgradable 2>/dev/null

# 3. Held back — investigate
apt-mark showhold

# 4. Snapshot /etc before touching anything
sudo tar czf /root/etc-snapshot-$(date +%Y%m%d).tar.gz /etc

# 5. Upgrade
sudo apt full-upgrade

# 6. Remove orphans
sudo apt autoremove
sudo apt clean

# 7. Reboot if kernel updated
if [ -f /var/run/reboot-required ]; then
    cat /var/run/reboot-required
    echo "Reboot when convenient."
fi

# 8. Snap check
snap list --all
sudo snap refresh

# 9. Verify unattended-upgrades is still healthy
sudo unattended-upgrade --dry-run
```

### Workflow: Investigating a held-back upgrade

```bash
sudo apt update
apt list --upgradable 2>/dev/null | head -20

# Phased rollout is common on Ubuntu — show phase status
apt-cache policy nginx | grep -A5 'Version table'

# Dependency issue?
apt-get install --simulate nginx
```

### Workflow: "Did unattended-upgrades actually run last night?"

```bash
# Most recent run in the log
sudo grep -A2 "Starting unattended" /var/log/unattended-upgrades/unattended-upgrades.log | tail -20

# Next scheduled run
systemctl list-timers apt-daily-upgrade.timer

# Anything pending a reboot?
ls /var/run/reboot-required 2>/dev/null && \
    cat /var/run/reboot-required.pkgs 2>/dev/null
```

### Workflow: Adding a trusted third-party repo

```bash
# Modern path: deb822 .sources format with key in /etc/apt/keyrings/
sudo install -d /etc/apt/keyrings
sudo curl -fsSLo /etc/apt/keyrings/nodesource.asc \
    https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key

sudo tee /etc/apt/sources.list.d/nodesource.sources >/dev/null <<'EOF'
Types: deb
URIs: https://deb.nodesource.com/node_20.x
Suites: nodistro
Components: main
Signed-By: /etc/apt/keyrings/nodesource.asc
EOF

sudo apt update
```

---

## Troubleshooting / gotchas

- **`apt upgrade` vs `apt full-upgrade`.** `upgrade` won't remove
  packages; `full-upgrade` will. On stable systems `upgrade` is safer
  day-to-day; `full-upgrade` is for release upgrades and full stacks.
  Never run `full-upgrade` without a snapshot.
- **Phased rollouts confuse "up to date" checks.** Ubuntu gradually
  rolls out certain updates by machine identity. You may be "phased
  back" — `apt-cache policy <pkg>` shows the phase.
- **Adding a PPA without key verification is a root-level trust.** Always
  use `/etc/apt/keyrings/` with a pinned key, never `apt-key add`
  (deprecated).
- **Snap refresh during business hours can restart services.** Set
  `refresh.timer` or use `snap refresh --hold=24h <name>` before a
  maintenance window.
- **`unattended-upgrades` silently skipped updates.** Check
  `/etc/apt/apt.conf.d/50unattended-upgrades` for Blacklist entries and
  the Allowed-Origins list — the codename must match the current
  release (e.g. `noble` not `jammy` after an upgrade).
- **Kernel upgrade without reboot.** Security advisories apply only
  after reboot. Monitor `/var/run/reboot-required`.

---

## References

- [`references/apt-reference.md`](references/apt-reference.md) — full
  apt reference, sources, keys, pinning, PPA trust model.
- [`references/snap-reference.md`](references/snap-reference.md) — snap
  channels, tracks, interfaces, refresh control.
- [`references/unattended-upgrades-reference.md`](references/unattended-upgrades-reference.md) —
  complete production config, mail notifications, auto-reboot.
- Book: *Mastering Ubuntu* (Atef, 2023) — modern apt/snap practice.
- Book: *Ubuntu Server Guide* (Canonical) — package management chapter.
- Man pages: `apt(8)`, `apt-get(8)`, `apt-cache(8)`, `apt-mark(8)`,
  `dpkg(1)`, `snap(1)`, `unattended-upgrade(8)`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-package-management` installs:

| Task | Fast-path script |
|---|---|
| `apt update` + held-back detection + security-only filter | `sudo sk-apt-update-safe` |
| Snapshot /etc, full-upgrade, warn on kernel | `sudo sk-apt-upgrade-safe` |
| Unattended-upgrades config + last run + next scheduled | `sudo sk-unattended-status` |
| Snap list with revision, refresh date, auto-update state | `sudo sk-snap-audit` |

These are optional wrappers around `apt`, `snap`, and
`unattended-upgrade`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-package-management
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-apt-update-safe | scripts/sk-apt-update-safe.sh | no | `apt update` + `apt list --upgradable` with held-back detection, security-only filter, and PPA listing. |
| sk-apt-upgrade-safe | scripts/sk-apt-upgrade-safe.sh | no | Pre-snapshot /etc, run `apt full-upgrade`, log changed packages, warn and gate on kernel updates. |
| sk-unattended-status | scripts/sk-unattended-status.sh | no | Show unattended-upgrades config, last run, next schedule, pending reboots. |
| sk-snap-audit | scripts/sk-snap-audit.sh | no | List snaps with revision, last refresh, auto-refresh state; flag stale revisions. |
