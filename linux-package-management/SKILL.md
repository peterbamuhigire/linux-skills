---
name: linux-package-management
description: Manage packages on Ubuntu/Debian — apt with safe update/upgrade patterns, held packages, PPAs, snap lifecycle, unattended-upgrades configuration. Use for any package installation, upgrade, or pinning operation.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Package Management

This skill owns package operations on Ubuntu/Debian: `apt` (Debian native),
`snap` (Canonical's sandboxed packages), and `unattended-upgrades` (the
background security-patch daemon).

It does **not** own:

- **Language-specific package managers** (`npm`, `pip`, `composer`, `cargo`)
  — those are managed by the site deployment skills.
- **The linux-skills repo itself** — that's `linux-site-deployment` via
  `update-all-repos`.

Informed by *Mastering Ubuntu* (modern apt/snap practice) and the Canonical
*Ubuntu Server Guide* (unattended-upgrades, autoinstall).

---

## When to use

- Installing new packages on a server.
- Running a safe `apt update` / `apt upgrade` cycle.
- Investigating held packages or broken dependencies.
- Auditing snap revisions and refresh policies.
- Configuring or verifying `unattended-upgrades`.
- Removing unused packages (`apt autoremove`) cleanly.

## When NOT to use

- Installing application dependencies inside a deployed site — use
  `linux-site-deployment`.
- Managing snap *applications* from the user's perspective — this skill is
  for server admin tasks only.

---

## Standing rules

1. **Never run `apt upgrade` without a snapshot.** `sk-apt-upgrade-safe`
   calls `sk-config-snapshot` before running so you can diff `/etc` after.
2. **`unattended-upgrades` is mandatory on every production server.**
   Security patches go in every night. `sk-unattended-status` verifies it
   is running and reporting successful.
3. **Never use `apt-get install -y` in scripts without reviewing the
   package list first.** Surprise dependencies can pull in hundreds of MB.
4. **Hold packages explicitly when needed.** `apt-mark hold <pkg>` with a
   comment explaining *why*. Tracked in `/etc/apt/linux-skills-holds.txt`
   by convention.
5. **PPAs are audited, not added casually.** Every added PPA is a new
   trust relationship. List current PPAs with `sk-apt-update-safe --list-ppas`.
6. **Kernel upgrades require a reboot plan.** `sk-apt-upgrade-safe` warns
   when a kernel package is in the upgrade list and refuses to proceed
   under `--yes` unless `--allow-kernel` was passed.
7. **Snap refresh schedules are configured, not disabled.** Disabling
   auto-refresh creates a silent security debt. Use refresh windows via
   `snap set system refresh.timer=`.

---

## Typical workflows

### Weekly maintenance cycle

```bash
sudo sk-apt-update-safe          # update + list upgradable, no changes
sudo sk-apt-upgrade-safe --log   # snapshot /etc, full-upgrade, log changes
sudo sk-unattended-status        # verify nightly security patches are healthy
sudo sk-snap-audit               # check snap revision state
```

### Investigating a held-back upgrade

```bash
sudo sk-apt-update-safe
```

Shows upgradable + held-back in two sections, with the reason each package
is held (phasing, dependency conflict, explicit hold).

### "Did unattended-upgrades actually run last night?"

```bash
sudo sk-unattended-status
```

Reports: daemon state, last successful run, last package installed, next
scheduled, any pending reboots from a linux-image update.

---

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

---

## See also

- `linux-server-hardening` — for the initial `unattended-upgrades` setup.
- `linux-disaster-recovery` — `sk-config-snapshot` used before upgrades.
- `linux-system-monitoring` — for watching upgrade-induced service
  restarts.
