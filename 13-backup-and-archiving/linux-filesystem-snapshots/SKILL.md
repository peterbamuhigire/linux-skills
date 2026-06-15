---
name: linux-filesystem-snapshots
description: Point-in-time filesystem snapshots on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). The three technologies are LVM snapshots (block-level COW, works under any filesystem and is identical on both families), Btrfs (Fedora's default; btrfs subvolume snapshot + btrfs send|receive), and ZFS (out-of-tree on Linux; zfs snapshot + zfs send|recv + rollback). Covers when a snapshot beats a file/tar backup (crash-consistent images of live databases, instant rollback) and when it does not (snapshots share a failure domain with production — they are not offsite backups). Explains COW fill/invalidate risks for LVM snapshots.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Filesystem Snapshots (LVM / ZFS / Btrfs)

## Distro support

**LVM** snapshots are identical on both families (block-level COW under any
filesystem). **Btrfs** is the Fedora default and present on Debian/Ubuntu;
**ZFS** is out-of-tree on Linux and needs DKMS packages from different repos per
family. Body uses Debian/Ubuntu where it differs; the **RHEL family** (Fedora,
RHEL, CentOS Stream, Rocky, Alma, Oracle) column gives equivalents.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| LVM tools | `apt install lvm2` | `dnf install lvm2` |
| LVM snapshot (`lvcreate -s`) | identical | identical |
| Btrfs tools | `apt install btrfs-progs` | preinstalled on **Fedora** (default FS); `dnf install btrfs-progs` elsewhere |
| Btrfs default root | optional | **Fedora Workstation default**; RHEL ships XFS root |
| ZFS install | `apt install zfsutils-linux` | `dnf install zfs` (OpenZFS repo + DKMS; not in base RHEL) |
| ZFS in base distro | universe (Ubuntu) | **not** shipped (CDDL/GPL licence conflict) |
| Default root FS otherwise | usually `ext4` | usually `xfs` (no native snapshots → use LVM) |

**RHEL-family gotcha:** the default root is usually **XFS**, which has **no
native snapshots** — on an XFS or ext4 root you must use **LVM** snapshots
underneath. Btrfs ships natively only on Fedora; ZFS is never in base RHEL/CentOS
(licence conflict) and must come from the OpenZFS DKMS repo. LVM is therefore the
portable, always-available snapshot layer on the RHEL family.

In `sk-*` scripts use the `common.sh` package primitives rather than hardcoding
apt/dnf. See
[`../../10-automation-and-scripting/linux-bash-scripting/SKILL.md`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md)
and [`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- You need a crash-consistent point-in-time image of a busy volume (e.g. a live
  database) so you can back it up without stopping the service.
- You want instant rollback before a risky upgrade or migration.
- You want to ship an efficient block/filesystem-level delta to another host
  (`zfs send`, `btrfs send`).

## Do not use when

- You need an **offsite** backup — a snapshot lives on the same pool/VG as
  production and dies with it. Pair snapshots with
  [`../linux-rsync-sync/SKILL.md`](../linux-rsync-sync/SKILL.md) or
  [`../linux-archive-integrity/SKILL.md`](../linux-archive-integrity/SKILL.md)
  to get the data off the host.
- You are restoring an existing backup in an incident; use
  [`../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md`](../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md).
- Day-to-day LVM volume/VG/fstab management; that lives in
  [`../../06-storage-and-filesystems/linux-disk-storage/SKILL.md`](../../06-storage-and-filesystems/linux-disk-storage/SKILL.md).

## Required inputs

- The volume/subvolume/dataset to snapshot and its filesystem type.
- Whether the snapshot is for backup capture, rollback, or replication.
- For LVM: enough free space in the VG for the COW area.

## Workflow

1. Pick the snapshot technology that matches the underlying storage (LVM under
   ext4/xfs; native Btrfs/ZFS where present).
2. Quiesce the application if a fully consistent image is needed (e.g. `FLUSH
   TABLES WITH READ LOCK` for MySQL) before taking the snapshot.
3. Take the snapshot, then back up *from* it (tar/rsync) or replicate it
   (send/receive) to get the data offsite.
4. Release/delete the snapshot when done — never leave LVM snapshots around.

## Quality standards

- Treat a snapshot as a *consistency tool*, not a backup. Always copy off-host.
- Size LVM COW space generously and monitor `lvs` `Data%` — a full COW snapshot
  is silently invalidated.
- Quiesce or use `--single-transaction` dumps for databases; a raw snapshot of
  a busy DB can still be mid-transaction.

## Anti-patterns

- Calling a snapshot "the backup" — it shares the failure domain of production.
- Leaving long-lived LVM snapshots (every write doubles into the COW area;
  performance degrades and the snapshot can fill and drop).
- `zfs rollback`/`btrfs` rollback on the wrong dataset — rollback is
  destructive and discards everything after the snapshot.

## Outputs

- The snapshot created (LV/subvolume/dataset name) and how it was made.
- How the data was moved offsite (tar/rsync/send) or that rollback was used.
- Confirmation the snapshot was released and free space reclaimed.

## References

- [`references/lvm-snapshots.md`](references/lvm-snapshots.md)
- [`references/zfs-btrfs-snapshots.md`](references/zfs-btrfs-snapshots.md)

**This skill is self-contained.** Every command below is stock `lvm2` / `btrfs`
/ `zfs` (the body shows Debian/Ubuntu where it differs; see **Distro support**
above for RHEL-family install). The `sk-lvm-snapshot` script in the **Optional
fast path** section is a convenience wrapper — never required.

## Snapshots vs File Backup — When To Use Which

| Goal | Reach for |
|---|---|
| Crash-consistent image of a live volume | snapshot (this skill), then back up from it |
| Instant rollback before a risky change | snapshot + `rollback` (ZFS/Btrfs) or remount the LVM origin |
| Get data **offsite** | file backup ([rsync](../linux-rsync-sync/SKILL.md) / [tar](../linux-archive-integrity/SKILL.md)) — a snapshot alone is not offsite |
| Efficient block-level replication to another host | `zfs send` / `btrfs send` |
| Portable archive across hosts/filesystems | tar ([linux-archive-integrity](../linux-archive-integrity/SKILL.md)) |

A snapshot captures an instant on the **same storage**. If the disk, array, or
host dies, the snapshot dies with it. The correct pattern is:
**snapshot → back up from the snapshot → ship offsite → release the snapshot.**

Conceptual trade-offs (Johnson, *Fedora Linux Essentials*): LVM snapshots are
block-level COW with overhead proportional to write activity; Btrfs and ZFS
provide near-instant, low-overhead filesystem-level snapshots with checksumming;
ZFS scales furthest but uses more memory.

---

## LVM Snapshots (works under any filesystem)

A snapshot is a COW copy of an LV capturing its state at an instant — the
standard way to back up a live database volume without stopping it.

```bash
# 5 GB COW scratch is usually enough for a short-lived snapshot
sudo lvcreate -L 5G -s -n web-snap /dev/data/web

# Mount read-only and back up FROM the snapshot (stable, consistent view)
sudo mkdir -p /mnt/snap
sudo mount -o ro /dev/data/web-snap /mnt/snap
sudo tar --acls --xattrs -czf /backups/web-$(date +%F).tar.gz -C /mnt/snap .
sudo umount /mnt/snap

# Delete when done — NEVER leave LVM snapshots lying around
sudo lvremove -f /dev/data/web-snap
```

Rules of thumb:

- Size the COW area to at least 10–20% of the origin LV — more if writes are
  heavy during the backup window.
- **A full snapshot is silently invalidated.** Monitor `lvs` — the `Data%`
  column shows COW fill; at 100% LVM drops the snapshot.
- LVM snapshots are for short-lived backup windows, not long-term storage.

Full LVM snapshot detail (and a note that day-to-day LVM volume management lives
in [`linux-disk-storage`](../../06-storage-and-filesystems/linux-disk-storage/SKILL.md)):
[`references/lvm-snapshots.md`](references/lvm-snapshots.md).

---

## Btrfs Snapshots (Fedora default FS)

Snapshots and subvolumes are first-class in Btrfs — near-instant, low space
overhead, with data/metadata checksumming.

```bash
# Read-only snapshot of a subvolume (read-only is required for send)
sudo btrfs subvolume snapshot -r /data /data/.snapshots/data-$(date +%F)

# List subvolumes and snapshots
sudo btrfs subvolume list /

# Roll back: swap the live subvolume for a snapshot (delete/rename + remount).
# Destructive — discards changes since the snapshot.
sudo btrfs subvolume delete /data
sudo btrfs subvolume snapshot /data/.snapshots/data-2026-06-15 /data

# Replicate to another host/disk (efficient block-level delta)
sudo btrfs send /data/.snapshots/data-2026-06-15 | \
     ssh backup@offsite 'btrfs receive /mnt/backup/'
# Incremental: send only the delta against a parent snapshot with -p
sudo btrfs send -p /data/.snapshots/data-2026-06-14 \
     /data/.snapshots/data-2026-06-15 | ssh backup@offsite 'btrfs receive /mnt/backup/'
```

[GROUNDING-GAP: `btrfs send|receive` (incremental `-p`/`-c` parents, read-only
snapshot requirement, and rollback-by-subvolume-swap) is from upstream
btrfs-progs man pages; the Fedora Essentials source covers Btrfs only
conceptually. Deepen with UNIX & Linux System Administration Handbook.]

---

## ZFS Snapshots (out-of-tree on Linux)

ZFS integrates filesystem and volume management with transactional COW,
checksumming, and efficient snapshots/clones.

```bash
# Snapshot a dataset (instant, space-efficient)
sudo zfs snapshot tank/data@2026-06-15

# List snapshots
zfs list -t snapshot

# Roll back the dataset to the snapshot (destructive — discards later changes)
sudo zfs rollback tank/data@2026-06-15

# Replicate to another pool/host
sudo zfs send tank/data@2026-06-15 | ssh backup@offsite 'zfs recv backup/data'
# Incremental between two snapshots with -i
sudo zfs send -i tank/data@2026-06-14 tank/data@2026-06-15 | \
     ssh backup@offsite 'zfs recv backup/data'
```

[GROUNDING-GAP: `zfs send|recv` (incremental `-i`/`-I`, resumable `-s` receive,
`rollback` semantics, and the OpenZFS-on-Linux licensing/DKMS situation) is from
upstream OpenZFS docs; the Fedora Essentials source covers ZFS only
conceptually. Deepen with UNIX & Linux System Administration Handbook.]

Full ZFS/Btrfs send-receive workflows:
[`references/zfs-btrfs-snapshots.md`](references/zfs-btrfs-snapshots.md).

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-filesystem-snapshots` installs:

| Task | Fast-path script |
|---|---|
| Create an LVM snapshot, mount it read-only, back it up, then release it | `sudo sk-lvm-snapshot --lv /dev/data/web --out /backups/web.tar.gz` |

This is an optional wrapper around the `lvcreate -s` workflow above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-filesystem-snapshots
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-lvm-snapshot | scripts/sk-lvm-snapshot.sh | no | Take a sized LVM COW snapshot of a given LV, mount it read-only, tar it (`--acls --xattrs`) to a backup path, then unmount and `lvremove` the snapshot. Checks VG free space first and warns if the COW size is under 10% of the origin. Asks before creating/removing. |
