---
name: linux-disk-storage
description: Manage disk space and storage on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Core tools (df, du, lsblk) are identical on both; package-cache cleanup (apt vs dnf) and the default root filesystem (ext4 vs xfs) differ. Check usage, find space hogs, safe cleanup (package cache, journal, old logs, old backups, node_modules), inode exhaustion, and emergency disk-full recovery. Covers local storage (partitioning, LVM, fstab) and network mounts (NFS, and CIFS/SMB Samba client mounts via mount -t cifs, cifs-utils, credentials files, fstab and autofs). Includes swapfile creation for servers running without swap.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Disk & Storage

## Distro support

Core tools (`df`, `du`, `lsblk`, `ncdu`, `findmnt`, `fdisk`) are **identical**
on both families. The differences are package-cache cleanup, sandboxed-package
storage, and the default root filesystem. Body uses Debian/Ubuntu; the **RHEL
family** (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) equivalents are in
the matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package cache cleanup | `apt clean` / `apt autoclean` | `dnf clean all` |
| Remove orphan pkgs | `apt autoremove` | `dnf autoremove` |
| Journal disk usage | `journalctl --disk-usage` / `--vacuum-size` | same |
| Sandboxed apps storage | `/var/lib/snapd`, `snap` revisions | `flatpak` / none on servers |
| Default root FS | usually `ext4` | usually `xfs` |
| df / du / lsblk / ncdu | identical | identical |
| CIFS/SMB client + `mount.cifs` | `apt install cifs-utils` | `dnf install cifs-utils` |
| SMB share discovery (`smbclient -L`) | `apt install smbclient` | `dnf install samba-client` |
| `mount -t cifs` / NFS / fstab / autofs | identical | identical |

**RHEL-family gotcha:** the default root filesystem is usually **XFS**, which
**cannot be shrunk** (only grown with `xfs_growfs`). On Debian/Ubuntu it is
usually ext4 (shrinkable). Plan partition resizes accordingly. LVM operations
are identical on both.

In `sk-*` scripts use the `common.sh` package primitives (`pkg_update`, etc.)
rather than hardcoding apt/dnf. See [`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md)
and [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Investigating disk pressure, inode exhaustion, or storage-related outages.
- Cleaning up safe space hogs on a server.
- Adding swap on a host that is currently running without one.
- Mounting a network share (NFS, or a Windows/NAS SMB share via CIFS) on a Linux client.

## Do not use when

- The issue is mainly application slowness or CPU pressure; use `linux-system-monitoring` or `linux-troubleshooting`.
- The task is filesystem permissions or user access; use `linux-access-control`.
- The task is **point-in-time snapshots** — LVM snapshots, or ZFS/Btrfs
  (`zfs snapshot`/`zfs send`, `btrfs subvolume snapshot`/`btrfs send`). That now
  lives in **`13-backup-and-archiving/linux-filesystem-snapshots`**. This skill
  keeps LVM volume management, fstab, NFS, and CIFS/SMB.

## Required inputs

- The filesystem or path under pressure.
- Whether the task is emergency cleanup, root-cause analysis, or swap provisioning.
- Any retention rules for logs, backups, or build artifacts before deletion.

## Workflow

1. Measure filesystem and inode usage before changing anything.
2. Identify the largest consumers and follow the safest cleanup steps first.
3. Escalate to emergency recovery or swap creation only when the evidence supports it.
4. Re-check free space and service health after the change.

## Quality standards

- Prefer reversible cleanup before destructive deletion.
- Quantify the largest consumers instead of guessing.
- Verify reclaimed space and confirm the root cause so the problem does not recur immediately.

## Anti-patterns

- Deleting broad directory trees without measuring them first.
- Treating `apt clean` or journal cleanup as a substitute for root-cause analysis.
- Creating swap without checking disk capacity and intended permanence.

## Outputs

- The storage diagnosis and the paths consuming space.
- The cleanup or swap actions taken.
- A verification snapshot of post-change disk and inode usage.

## References

- [`references/storage-reference.md`](references/storage-reference.md)
- [`references/cleanup-patterns.md`](references/cleanup-patterns.md)
- [`references/cifs-and-network-mounts.md`](references/cifs-and-network-mounts.md)

**This skill is self-contained.** Every command below is a standard tool on
both families (the body shows Debian/Ubuntu; see **Distro support** above for
RHEL-family equivalents). The `sk-*` scripts in the **Optional fast path**
section are convenience wrappers — never required.

## Check Usage

```bash
df -h                           # filesystem overview (concern: > 85% used)
df -i                           # inode usage (can be full independently)
du -sh /var/www/* | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh ~/backups/* 2>/dev/null | sort -rh | head -5
sudo find / -type f -size +100M 2>/dev/null | head -10
```

---

## Safe Cleanup (In Order Of Safety)

```bash
# 1. APT cache (always safe)
sudo apt clean && sudo apt autoremove

# 2. Journal logs (safe, keeps recent 14 days)
sudo journalctl --vacuum-time=14d
sudo journalctl --vacuum-size=500M

# 3. Old backup files (verify retention script is running first)
find ~/backups/mysql/ -name "*.gpg" -mtime +7 -delete

# 4. Temp files
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# 5. node_modules after successful Astro build
# cd /var/www[/html]/<site> && rm -rf node_modules
# (update-all-repos will reinstall on next pull)
```

---

## Emergency Disk Full

```bash
# Fast identification
df -h && du -sh /var/www/* /var/log/* ~/backups/* 2>/dev/null | sort -rh | head -10

# Immediate wins (safe):
sudo apt clean
sudo journalctl --vacuum-size=200M
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# Truncate an oversize log (safer than deleting):
sudo truncate -s 0 /var/log/<oversize-log-file>
```

---

## Inode Exhaustion (df -i shows 100%)

```bash
# Find dir with most files:
sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2 | sort | uniq -c | sort -rn | head

# Common causes: PHP sessions, mail spool, tiny cache files
sudo find /var/lib/php/sessions/ -type f | wc -l
sudo find /tmp -type f | wc -l
```

---

## Swapfile (Safety Net For No-Swap Servers)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-swappiness.conf
sudo sysctl vm.swappiness=10
free -h                   # verify Swap shows 2G
```

Full cleanup targets and LVM reference: `references/storage-reference.md`

---

## Network Mounts: NFS And CIFS/SMB

Two network filesystems show up on Linux clients. **NFS** is the
UNIX-native choice (Linux-to-Linux exports, home directories). **CIFS/SMB**
is the Windows/Samba/NAS choice — reach for it when the server is Windows
or a NAS exposing SMB. Both are mounted via `mount`, persist through
`/etc/fstab` or `autofs`, and use `0` `0` for the dump/pass fields.

### NFS (Linux-to-Linux)

```bash
# Install client: apt install nfs-common   |   dnf install nfs-utils
showmount -e server2                       # list exports
sudo mount -t nfs server2:/share /mnt/nfs  # manual mount

# Persistent (fstab): server:share is colon-separated
# server2:/share  /mnt/nfs  nfs  _netdev,nofail  0  0
```

### CIFS/SMB (Windows / Samba / NAS)

```bash
# Install client: apt install cifs-utils smbclient | dnf install cifs-utils samba-client
smbclient -L //192.168.4.200 -U guest      # discover shares (IP avoids DNS issues)

# Manual test mount (prompts for password):
sudo mount -t cifs -o username=linda //server2/sambashare /mnt/share
```

**Never put a password in plaintext in fstab.** Use a 0600 credentials
file:

```bash
sudo tee /root/.smbcredentials >/dev/null <<'EOF'
username=linda
password=SuperSecret
domain=WORKGROUP
EOF
sudo chmod 600 /root/.smbcredentials       # MUST be 0600 — root-only
```

Persistent CIFS mount in `/etc/fstab` (note `_netdev,nofail` so a
missing server never blocks boot):

```
//server2/sambashare  /sambamount  cifs  credentials=/root/.smbcredentials,uid=1000,gid=1000,vers=3.0,_netdev,nofail,x-systemd.automount  0  0
```

```bash
sudo mount -a            # test before rebooting; fails loudly on a typo
```

On-demand via **autofs** (mounts on first access, unmounts when idle —
works for both NFS and CIFS):

```bash
# /etc/auto.master :  /cifs  /etc/auto.cifs  --timeout=60
# /etc/auto.cifs   :  sambashare  -fstype=cifs,credentials=/root/.smbcredentials,vers=3.0  ://server2/sambashare
sudo systemctl enable --now autofs
```

**Quick troubleshooting:** `error(112)`/`error(95)` → SMB version, try
`vers=3.0` then `vers=2.1` (never `1.0` — insecure). `error(13)` →
credentials or `sec=` (`sec=ntlmssp` for username/password,
`sec=krb5` in an AD/FreeIPA domain). Full detail, ownership mapping,
wildcard autofs maps, and the Samba *server* side:
`references/cifs-and-network-mounts.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-disk-storage` installs:

| Task | Fast-path script |
|---|---|
| Top 20 consumers by dir/file | `sudo sk-disk-hogs [/path]` |
| Interactive cleanup with preview | `sudo sk-disk-cleanup` |
| Inode exhaustion detector | `sudo sk-inode-check` |
| Mount a CIFS/SMB share (creds + test + fstab) | `sudo sk-cifs-mount //server/share /mnt/share` |

These are optional wrappers around the commands above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-disk-storage
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-disk-hogs | scripts/sk-disk-hogs.sh | yes | Top 20 directories/files by size under a path; warns on `/var/log` and `/tmp` bloat. |
| sk-disk-cleanup | scripts/sk-disk-cleanup.sh | no | Interactive cleanup: apt cache, journal, old logs, kernel images, tmp. Shows bytes reclaimed. |
| sk-inode-check | scripts/sk-inode-check.sh | no | Find filesystems nearing inode exhaustion; top directories by inode count. |
| sk-cifs-mount | scripts/sk-cifs-mount.sh | no | Mount a CIFS/SMB (Samba/Windows) share: install `cifs-utils`, build/verify a 0600 credentials file, test-mount, optionally add a persistent `_netdev,nofail` fstab entry. |
