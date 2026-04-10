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

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool (`apt`, `apt-get`, `apt-mark`, `apt-cache`, `snap`,
`unattended-upgrade`, `dpkg`). The `sk-*` scripts in the **Optional fast
path** section are convenience wrappers — never required.

This skill owns package operations on Ubuntu/Debian: **apt** (Debian
native), **snap** (Canonical's sandboxed packages), and
**unattended-upgrades** (the background security-patch daemon).

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

### apt

```bash
# Update the package index
sudo apt update

# What's upgradable? (safe — no changes)
apt list --upgradable 2>/dev/null

# Security-only list (approximation)
apt list --upgradable 2>/dev/null | grep -i security

# Held-back packages (phasing, conflicts)
apt-mark showhold

# Show info on a specific package
apt show nginx
apt-cache policy nginx           # which repo would apt install from?
apt-cache depends nginx          # what does it need?
apt-cache rdepends nginx         # what depends on it?

# Who owns this file?
dpkg -S /etc/nginx/nginx.conf

# What files does a package own?
dpkg -L nginx

# Install / upgrade / remove
sudo apt install <pkg>
sudo apt upgrade                  # only upgrades, no removes
sudo apt full-upgrade             # upgrades AND removes (formerly dist-upgrade)
sudo apt remove <pkg>             # keeps config
sudo apt purge <pkg>              # removes config too
sudo apt autoremove               # removes unneeded dependencies
sudo apt clean                    # clears /var/cache/apt/archives

# Pin a package version
sudo apt-mark hold nginx
sudo apt-mark unhold nginx

# Reinstall cleanly
sudo apt install --reinstall nginx
```

Full apt reference (sources.list and sources.list.d formats,
`/etc/apt/keyrings/` key management, preferences-pinning, deb822 `.sources`
format, PPA verification, dependency-resolution recovery) — see
[`references/apt-reference.md`](references/apt-reference.md).

### snap

```bash
# List all snaps
snap list

# Show all revisions (including disabled)
snap list --all

# Install
sudo snap install <name>
sudo snap install <name> --channel=latest/stable
sudo snap install <name> --classic

# Refresh (update)
sudo snap refresh                 # all
sudo snap refresh <name>          # one

# Hold a snap from refreshing (time-bounded)
sudo snap refresh --hold=24h <name>

# Rollback to the previous revision
sudo snap revert <name>

# Remove
sudo snap remove <name>

# Show next refresh time
snap refresh --time
```

Full snap reference (channels, tracks, interfaces, snap services,
refresh.timer / refresh.hold) — see
[`references/snap-reference.md`](references/snap-reference.md).

### unattended-upgrades

```bash
# Config
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
sudo nano /etc/apt/apt.conf.d/20auto-upgrades

# Dry run — see what it WOULD install, change nothing
sudo unattended-upgrade --dry-run -v

# Force a real run now
sudo unattended-upgrade -v

# Logs
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log
sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log

# Systemd timers that trigger it
systemctl list-timers apt-daily apt-daily-upgrade
systemctl status apt-daily.timer apt-daily-upgrade.timer

# Pending reboot after kernel update
ls /var/run/reboot-required 2>/dev/null && echo "Reboot required" || echo "No reboot needed"
```

Full unattended-upgrades reference (Allowed-Origins syntax, mail
notifications, automatic-reboot config, package blacklist, complete
production example) — see
[`references/unattended-upgrades-reference.md`](references/unattended-upgrades-reference.md).

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
