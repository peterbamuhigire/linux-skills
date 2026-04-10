# Storage Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Complete block-storage and filesystem reference for Ubuntu/Debian
servers: partitioning, filesystems, mount options, `/etc/fstab`, LVM,
software RAID, swapfiles, and SMART health. Every command in this file
works on a stock Ubuntu/Debian install without extra tooling beyond a
few apt packages that are called out inline. This is the deep-dive
companion to `SKILL.md`; for safe cleanup patterns see
`cleanup-patterns.md`.

## Table of contents

1. Identifying devices
2. Partitioning tools: `fdisk`, `parted`, `gdisk`
3. Choosing a filesystem
4. Making filesystems
5. Mount options that matter
6. `/etc/fstab`: format, UUID vs LABEL, safety
7. Automounting on boot
8. LVM: PV → VG → LV
9. LVM online resize
10. LVM snapshots
11. Software RAID with `mdadm`
12. Swapfile creation
13. Swappiness tuning
14. Disk health with SMART (`smartctl`)
15. Bad block detection (`badblocks`)
16. When to replace a disk
17. Sources

---

## 1. Identifying devices

```bash
lsblk                           # tree of block devices
lsblk -f                        # with fs type, UUID, mountpoint
lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINT,UUID,FSTYPE,MODEL
sudo blkid                      # UUIDs and labels of every block device
sudo fdisk -l                   # partition table of every disk
ls -l /dev/disk/by-id/          # stable aliases by hardware ID
ls -l /dev/disk/by-uuid/        # stable aliases by filesystem UUID
ls -l /dev/disk/by-label/       # stable aliases by filesystem label
findmnt                         # mount tree
```

`lsblk -f` is usually the first command you run. It answers, in one
screen, "what devices exist, what's on them, and where they're mounted."

Device naming conventions on Ubuntu/Debian:

- `/dev/sdX` — SCSI/SATA/USB mass storage, letter per disk.
- `/dev/nvme0n1` — NVMe; `0` is the controller, `n1` is namespace 1.
  Partitions are `nvme0n1p1`, `nvme0n1p2`.
- `/dev/vdX` — virtio disks in KVM/QEMU VMs.
- `/dev/xvdX` — Xen VMs (older EC2).
- `/dev/mapper/<vg>-<lv>` or `/dev/<vg>/<lv>` — LVM logical volumes.
- `/dev/md0`, `/dev/md1` — Linux software RAID arrays.

---

## 2. Partitioning tools

Three tools cover every case on Ubuntu/Debian:

- **`fdisk`** — interactive, MBR and GPT, best for one-off edits.
- **`parted`** — scriptable, GPT-native, good for automation.
- **`gdisk`** — GPT-only, for when you want the extra GPT-specific safety
  and partition-type picker.

### fdisk

```bash
sudo fdisk -l                   # list every partition table
sudo fdisk /dev/sdb             # interactive session
```

Inside `fdisk`:

| Key | Action                                    |
|-----|-------------------------------------------|
| `m` | Help menu.                                |
| `p` | Print current partition table.            |
| `n` | New partition.                            |
| `d` | Delete partition.                         |
| `t` | Change partition type.                    |
| `g` | Convert to GPT.                           |
| `o` | Convert to MBR.                           |
| `w` | Write changes and exit.                   |
| `q` | Quit without saving.                      |

### parted (scriptable)

```bash
sudo parted /dev/sdb print                         # read
sudo parted /dev/sdb mklabel gpt                   # new GPT label
sudo parted /dev/sdb mkpart primary ext4 0% 100%   # one big partition
sudo parted /dev/sdb mkpart primary ext4 0% 50%
sudo parted /dev/sdb mkpart primary ext4 50% 100%
sudo parted /dev/sdb name 1 data                    # assign label
sudo parted -l                                      # list every disk
```

Use `0%` and `100%` (percentages) in `parted` commands — it does the
alignment math so every partition starts at a well-aligned offset.

### gdisk

```bash
sudo gdisk /dev/sdb             # interactive; same keybindings as fdisk
```

After **any** partitioning change, tell the kernel to re-read the table:

```bash
sudo partprobe /dev/sdb
lsblk
```

---

## 3. Choosing a filesystem

On Ubuntu/Debian, the practical candidates are ext4, xfs, btrfs, and
(rarely) f2fs:

| FS    | Default on                | Strengths                                  | Weaknesses                                 |
|-------|---------------------------|--------------------------------------------|--------------------------------------------|
| ext4  | Ubuntu server default     | Mature, stable, well-understood, `resize2fs` works online, good fsck. | No snapshots, no checksumming.    |
| xfs   | RHEL default, optional Ubuntu | Excellent for large files and high parallel I/O; can grow online (`xfs_growfs`). | **Cannot shrink**. Must backup+recreate to shrink. |
| btrfs | Fedora default            | Snapshots, checksums, subvolumes, compression. | Write performance quirks under heavy DB load; RAID 5/6 not production-ready. |
| f2fs  | Flash-native              | Optimised for SSDs/flash; good for embedded. | Uncommon on servers; limited tooling.      |

Rule of thumb for production web servers:

- **Root and most data**: ext4 by default. Safe, boring, fast enough.
- **Large media stores or database partitions with heavy sequential I/O**: xfs.
- **Snapshots built-in without LVM complexity**: btrfs (but profile it
  under your real workload first).

---

## 4. Making filesystems

```bash
# ext4
sudo mkfs.ext4 -L data /dev/sdb1

# ext4 with reserved blocks lowered from 5% → 1% (useful on large data disks)
sudo mkfs.ext4 -L data -m 1 /dev/sdb1

# xfs
sudo mkfs.xfs -L data /dev/sdb1

# xfs, overwriting an existing signature
sudo mkfs.xfs -f -L data /dev/sdb1

# btrfs
sudo mkfs.btrfs -L data /dev/sdb1

# f2fs (requires `apt install f2fs-tools`)
sudo mkfs.f2fs -l data /dev/sdb1
```

After creating the filesystem, grab its UUID for `fstab`:

```bash
sudo blkid /dev/sdb1
# /dev/sdb1: LABEL="data" UUID="e4a5..." TYPE="ext4"
```

Useful `mkfs.ext4` flags:

- `-L <label>` — filesystem label (mount by label later).
- `-m <percent>` — reserve percentage (default 5%; drop to 1% or 0% on
  a data disk where root does not need emergency reserve).
- `-T news|largefile|largefile4` — tune inode density. Default is fine.
- `-b 4096` — block size. Leave at default.

---

## 5. Mount options that matter

Set these in `/etc/fstab` (see section 6). The important ones:

| Option       | Effect                                                                 |
|--------------|------------------------------------------------------------------------|
| `defaults`   | `rw, suid, dev, exec, auto, nouser, async`. The usual.                 |
| `noatime`    | Don't update access time on read. **Big** speedup for busy reads.      |
| `nodiratime` | Same, for directories only. `noatime` implies this.                    |
| `relatime`   | Updates atime only if older than mtime/ctime or > 24h. Default on modern Ubuntu. |
| `nosuid`     | Ignore `setuid`/`setgid` bits. Set on `/tmp`, `/home`, `/var` if paranoid. |
| `nodev`      | Ignore device nodes. Set on `/tmp`, `/home`.                           |
| `noexec`     | Do not allow binary execution. Set on `/tmp` for hardening.            |
| `ro`         | Read-only mount.                                                       |
| `user`       | Allow non-root users to mount.                                         |
| `auto`       | Mount automatically at boot.                                           |
| `noauto`     | Do not mount at boot (but listed in fstab).                            |
| `nofail`     | Do not fail boot if this mount fails (essential for external disks).   |
| `x-systemd.device-timeout=5s` | Give up waiting for the device after 5s.              |
| `x-systemd.automount` | Lazy-mount on first access. Pair with `noauto`.               |

Recommended hardening combo for `/tmp`:

```
tmpfs  /tmp  tmpfs  defaults,nosuid,nodev,noexec,size=1G  0  0
```

Recommended for a busy data disk:

```
UUID=e4a5...  /var/www  ext4  defaults,noatime,nofail  0  2
```

---

## 6. `/etc/fstab`: format, UUID vs LABEL, safety

`/etc/fstab` is read at boot (and by `mount -a`) to decide what to
mount. Each row has six fields:

```
<device>  <mountpoint>  <fstype>  <options>  <dump>  <pass>
```

| Field         | Meaning                                                              |
|---------------|----------------------------------------------------------------------|
| `<device>`    | `UUID=...`, `LABEL=...`, or `/dev/...`. **Always prefer UUID.**      |
| `<mountpoint>`| Directory to mount at. Must exist.                                   |
| `<fstype>`    | `ext4`, `xfs`, `btrfs`, `vfat`, `tmpfs`, `swap`, `nfs`, etc.         |
| `<options>`   | Comma-separated mount options (section 5).                           |
| `<dump>`      | Legacy `dump` backup flag. Always `0` on modern systems.             |
| `<pass>`      | `fsck` order at boot. `0` = skip, `1` = root, `2` = everything else. |

Example:

```
# <device>                                  <mp>       <fs>   <opts>                    <d> <p>
UUID=3f7c0abe-2c39-4b42-9e64-4d9e2a7d1f0a   /          ext4   errors=remount-ro         0   1
UUID=e4a5c53a-01d6-4c92-91c1-4a29f73fb3e5   /var/www   ext4   defaults,noatime,nofail   0   2
UUID=12345678-1234-1234-1234-123456789abc   none       swap   sw                        0   0
tmpfs                                       /tmp       tmpfs  defaults,nosuid,nodev,noexec,size=1G  0  0
```

### Why UUID, not `/dev/sdX`

Device names are **not stable**. If you add a disk, `sdb` may become
`sdc`, and a root filesystem referenced as `/dev/sdb1` will fail to
mount, dropping you into emergency shell. UUIDs are cryptographic and
move with the partition.

Get the UUID:

```bash
sudo blkid /dev/sdb1
lsblk -o NAME,UUID,MOUNTPOINT
```

### `nofail` saves you from emergency shell

If a mount in fstab fails at boot, systemd drops to emergency shell by
default. For any non-critical mount (external backup disk, secondary
data volume), add `nofail`:

```
UUID=...  /backups  ext4  defaults,nofail,x-systemd.device-timeout=5s  0  2
```

Without `nofail`, unplugging an external disk will prevent the server
from booting unattended.

### Test an fstab edit before rebooting

```bash
sudo mount -a                       # apply fstab now
```

If there's a typo, this fails loudly at the command line — where you
can fix it. **Always** `mount -a` after editing fstab, before rebooting.

---

## 7. Automounting on boot

Plain fstab mounts happen at boot. Three other patterns:

### systemd lazy automount

```
UUID=...  /mnt/data  ext4  defaults,noauto,x-systemd.automount,x-systemd.idle-timeout=60  0  0
```

The filesystem is not mounted until something actually accesses
`/mnt/data`, and unmounts after 60 seconds of idle. Useful for rarely
used volumes.

### systemd `.mount` unit

For full control, create a unit file: `/etc/systemd/system/mnt-data.mount`
(unit filename must mirror the mountpoint with slashes replaced by
dashes — `systemd-escape -p --suffix=mount /mnt/data`).

```ini
[Unit]
Description=Data volume

[Mount]
What=/dev/disk/by-uuid/e4a5c53a-01d6-4c92-91c1-4a29f73fb3e5
Where=/mnt/data
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-data.mount
```

### autofs

Legacy but still shipping. `apt install autofs`. Useful for NFS user
homes on a workstation.

---

## 8. LVM: PV → VG → LV

Logical Volume Manager is an abstraction layer between block devices
and filesystems. Three concepts:

- **Physical volume (PV)**: a disk or partition initialised for LVM.
- **Volume group (VG)**: a pool of PVs, treated as a single free-space
  pool.
- **Logical volume (LV)**: a carved-out slice of a VG, which you
  format and mount.

You gain: online resize, snapshots, move data between physical disks
without downtime, span a filesystem across multiple disks.

### Check current state

```bash
sudo pvs                 # physical volumes summary
sudo pvdisplay           # detailed
sudo vgs                 # volume groups summary
sudo vgdisplay
sudo lvs                 # logical volumes summary
sudo lvdisplay
```

### Create a PV from scratch

```bash
sudo pvcreate /dev/sdb
```

If the disk was previously formatted, `pvcreate` will refuse. Wipe the
signature first with `sudo wipefs -a /dev/sdb` — but be absolutely sure
it's the right disk.

### Create a VG

```bash
sudo vgcreate data /dev/sdb
```

Creates VG `data` holding PV `/dev/sdb`.

### Create an LV

```bash
# Fixed size
sudo lvcreate -L 50G -n web data
# Percentage of free
sudo lvcreate -l 100%FREE -n web data
```

Creates LV `/dev/data/web` (also accessible as `/dev/mapper/data-web`).

### Format and mount the LV

```bash
sudo mkfs.ext4 -L web /dev/data/web
sudo mkdir -p /var/www
echo 'UUID=<uuid> /var/www ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
sudo mount -a
```

### Extend the VG with another disk

```bash
sudo pvcreate /dev/sdc
sudo vgextend data /dev/sdc
sudo vgs                       # confirm the free space grew
```

### Remove an LV

```bash
sudo umount /var/www
sudo lvremove /dev/data/web
```

`lvremove` asks for confirmation; pass `-f` only when scripting.

---

## 9. LVM online resize

**Grow** a logical volume that is currently mounted, and grow the
filesystem on top of it in one command:

```bash
sudo lvextend -r -L +10G /dev/data/web
# -r = resize the filesystem afterward (calls resize2fs or xfs_growfs)
```

Explicit form (if you want to check between steps):

```bash
sudo lvextend -L +10G /dev/data/web
sudo resize2fs /dev/data/web        # ext4
# or:
sudo xfs_growfs /var/www            # xfs takes the mountpoint
```

**Shrink** an ext4 volume (xfs cannot shrink):

```bash
sudo umount /var/www
sudo e2fsck -f /dev/data/web        # must be clean
sudo resize2fs /dev/data/web 20G    # shrink fs first
sudo lvreduce -L 20G /dev/data/web  # then shrink LV
sudo mount /var/www
```

Always shrink the filesystem **before** the LV, or you will truncate
data. The `-r` flag on `lvreduce` will do it in the correct order, but
shrinking should be treated as a rare, supervised operation — always
back up first.

---

## 10. LVM snapshots

A snapshot is a COW copy of an LV that captures its state at an
instant. Used for consistent backups of live databases.

```bash
# 5 GB COW scratch space is usually enough for a short-lived snapshot
sudo lvcreate -L 5G -s -n web-snap /dev/data/web

# Mount the snapshot read-only to back it up
sudo mkdir -p /mnt/snap
sudo mount -o ro /dev/data/web-snap /mnt/snap
tar czf /backups/web-$(date +%F).tar.gz -C /mnt/snap .
sudo umount /mnt/snap

# Delete when done
sudo lvremove -f /dev/data/web-snap
```

Rules of thumb:

- Size the snapshot COW area to at least 10–20% of the LV you are
  snapshotting, more if writes are heavy during the backup window.
- **A full snapshot becomes invalid**. Monitor with `lvs` — the
  `Data%` column tells you how full the COW space is. If it hits 100%,
  LVM drops the snapshot.
- Snapshots are for short-lived backup windows, not long-term storage.

---

## 11. Software RAID with `mdadm`

Linux software RAID is provided by the `mdadm` package. Common RAID
levels:

| Level  | Redundancy     | Usable capacity  | Use case                          |
|--------|----------------|------------------|-----------------------------------|
| RAID 0 | **None**       | 100%             | Scratch; do not use for data.     |
| RAID 1 | Survives 1 disk| 50%              | Root/boot mirrors.                |
| RAID 5 | Survives 1 disk| (N-1)/N          | General data with redundancy.     |
| RAID 6 | Survives 2 disk| (N-2)/N          | Large data arrays.                |
| RAID 10| Survives 1 disk per mirror| 50%    | DB data, high-performance.        |

### Create an array

```bash
sudo apt install -y mdadm
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc
sudo mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/sd[bcd]
```

Check progress:

```bash
cat /proc/mdstat
# md0 : active raid1 sdc[1] sdb[0]
#       1953513472 blocks super 1.2 [2/2] [UU]
#       [======>..............]  resync = 34.2% (...)
```

### Persist the config

```bash
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u
```

### Inspect

```bash
sudo mdadm --detail /dev/md0
cat /proc/mdstat
```

### Fail, remove, and replace a drive

```bash
# Mark failed
sudo mdadm /dev/md0 --fail /dev/sdb

# Remove from array
sudo mdadm /dev/md0 --remove /dev/sdb

# Physically swap the disk, then:
sudo mdadm /dev/md0 --add /dev/sdb
cat /proc/mdstat                   # watch the rebuild
```

### Stop an array

```bash
sudo umount /mnt/data
sudo mdadm --stop /dev/md0
```

Software RAID can live underneath LVM (mdadm → LVM → filesystem) — a
common, flexible stack.

---

## 12. Swapfile creation

For any server without swap (common on cloud VMs), a swapfile is a
cheap safety net.

```bash
# 2 GB swapfile
sudo fallocate -l 2G /swapfile

# If fallocate isn't available or the FS doesn't support it:
sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress

sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Verify:

```bash
swapon --show
free -h
```

Disable a swapfile:

```bash
sudo swapoff /swapfile
sudo sed -i '/\/swapfile/d' /etc/fstab
sudo rm /swapfile
```

Note: swapfiles on btrfs have historically been tricky — follow the
btrfs-specific procedure (the file must be on a non-COW directory).

---

## 13. Swappiness tuning

`vm.swappiness` (0–200 on newer kernels) controls how aggressively the
kernel reclaims to swap vs evicting file cache.

```bash
cat /proc/sys/vm/swappiness        # usually 60 by default
sudo sysctl vm.swappiness=10       # runtime
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system
```

Recommended values:

- **10** — database servers (MySQL, PostgreSQL). Keeps the buffer pool
  in RAM.
- **10–20** — web servers. Prefer cache over swap.
- **60** (default) — desktops and laptops.
- **1** — almost never swap (aggressive). Not zero — zero disables swap
  entirely under pressure and invites OOM kills.

---

## 14. Disk health with SMART (`smartctl`)

```bash
sudo apt install -y smartmontools
```

### Quick health

```bash
sudo smartctl -H /dev/sda
# SMART overall-health self-assessment test result: PASSED
```

`PASSED` does not mean the disk is perfect. Check the attributes.

### Full report

```bash
sudo smartctl -a /dev/sda
sudo smartctl -a /dev/nvme0
```

Key attributes to watch (numbers in the `RAW_VALUE` column unless noted):

| Attribute                    | Concern if                                               |
|------------------------------|----------------------------------------------------------|
| `Reallocated_Sector_Ct`      | > 0 and rising. Any re-allocation means bad sectors.    |
| `Current_Pending_Sector`     | > 0. Uncorrectable reads — disk is failing.              |
| `Offline_Uncorrectable`      | > 0. Similar.                                            |
| `UDMA_CRC_Error_Count`       | Rising. Cable or connector problem, not necessarily the disk. |
| `Temperature_Celsius`        | > 55°C sustained. Cooling problem.                      |
| `Power_On_Hours`             | Shows age. Compare against manufacturer spec.            |
| `Wear_Leveling_Count` (SSD)  | Low value = most of the write endurance is gone.        |

### Self-tests

```bash
sudo smartctl -t short /dev/sda       # ~2 minutes, runs in background
sudo smartctl -t long /dev/sda        # hours; full surface scan
sudo smartctl -l selftest /dev/sda    # read the results
```

### Enable background monitoring

```bash
sudo systemctl enable --now smartd
```

`smartd` checks SMART attributes periodically and emails alerts on
change (configure `/etc/smartd.conf`).

### NVMe specifics

```bash
sudo apt install -y nvme-cli
sudo nvme smart-log /dev/nvme0
sudo nvme list
```

`percentage_used` on an NVMe SMART log is the endurance-used estimate.
Over 80% = plan replacement.

---

## 15. Bad block detection (`badblocks`)

For spinning disks suspected of having bad sectors:

```bash
# Non-destructive read-only scan (safe on mounted FS)
sudo badblocks -sv /dev/sdb > badblocks.txt

# Non-destructive read-write scan (backs up and restores each block)
sudo badblocks -nsv /dev/sdb > badblocks.txt

# Destructive write-read scan (ERASES the disk)
sudo badblocks -wsv /dev/sdb
```

Pair with `e2fsck` to have ext4 mark the blocks unused:

```bash
sudo umount /dev/sdb1
sudo e2fsck -cfv /dev/sdb1
```

On modern SSDs, `badblocks` is not useful — the firmware remaps bad
cells transparently. Use SMART instead.

---

## 16. When to replace a disk

Decision table for spinning rust:

| Signal                                                  | Action                                   |
|---------------------------------------------------------|------------------------------------------|
| SMART overall health FAIL                               | Replace immediately. Drive is dying.     |
| `Reallocated_Sector_Ct` > 0 and growing                 | Replace within days.                     |
| `Current_Pending_Sector` > 0 stable                     | Replace within days.                     |
| `UDMA_CRC_Error_Count` rising                           | Replace SATA cable first; then disk.     |
| Repeated kernel messages `ata errors`, `end_request: I/O error` | Replace; drive is failing.       |
| Filesystem remounted read-only due to I/O errors        | Replace; restore from backup.            |
| `badblocks` scan finds any bad sectors                  | Replace when convenient.                 |

For SSDs and NVMe:

| Signal                                                  | Action                                   |
|---------------------------------------------------------|------------------------------------------|
| `Wear_Leveling_Count` low (low remaining endurance)     | Plan replacement in next maintenance.    |
| NVMe `percentage_used` > 80%                            | Plan replacement in next maintenance.    |
| `Media_and_Data_Integrity_Errors` > 0                   | Replace; data corruption risk.           |
| Firmware read errors in dmesg                           | Check firmware update; if persists, replace. |

Always **restore from backup** onto a new disk — do not trust a disk
that has started failing, even if it seems to come back.

---

## Sources

- **Ubuntu Server Guide (Focal 20.04)**, Canonical (2020) — partitioning,
  filesystems, LVM, and fstab defaults.
- **Mastering Ubuntu**, Ghada Atef (2023) — storage chapter: LVM, mdadm,
  mount options.
- **Linux System Administration for the 2020s** — practical guidance on
  modern filesystems (ext4 vs xfs vs btrfs) and SMART monitoring.
- **Wicked Cool Shell Scripts**, Dave Taylor & Brandon Perry — disk
  monitoring and space-alert scripts.
- `mkfs.ext4(8)`, `mkfs.xfs(8)`, `lvm(8)`, `lvcreate(8)`, `lvextend(8)`,
  `resize2fs(8)`, `mdadm(8)`, `smartctl(8)`, `fstab(5)`, `mount(8)` man
  pages.
- Real-world experience running ext4 + LVM + mdadm stacks on production
  Ubuntu 20.04 / 22.04 servers.
