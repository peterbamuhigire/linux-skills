# ZFS and Btrfs snapshots & send/receive

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Filesystem-native snapshots and replication for Btrfs (Fedora's default FS) and
ZFS (out-of-tree on Linux). These are near-instant, low-overhead, and
checksummed — unlike LVM's block-level COW (see
[`lvm-snapshots.md`](lvm-snapshots.md)). Block-level command detail below is
flagged as a grounding gap: the *Fedora Essentials* source covers Btrfs/ZFS
conceptually only.

## Table of contents

1. Conceptual comparison (LVM vs Btrfs vs ZFS)
2. Btrfs: subvolumes and snapshots
3. Btrfs: send / receive
4. Btrfs: rollback
5. ZFS: datasets and snapshots
6. ZFS: send / recv
7. ZFS: rollback and clones
8. Availability per family
9. Sources

---

## 1. Conceptual comparison

From Johnson, *Fedora Linux Essentials*:

| | LVM | Btrfs | ZFS |
|---|---|---|---|
| Layer | block (under any FS) | filesystem | filesystem + volume manager |
| Snapshots | COW, overhead ∝ I/O | first-class, near-instant | first-class, near-instant |
| Checksums | none | data + metadata | data + metadata, self-healing |
| Replication | none (use tar/rsync) | `btrfs send`/`receive` | `zfs send`/`recv` |
| Cost | minimal CPU/RAM | low RAM, higher CPU | high RAM (ARC), most scalable |
| Best for | snapshot under ext4/xfs | desktops, small servers, rollback | NAS, backup servers, virt hosts |

`zpool status` (ZFS), `btrfs filesystem df` (Btrfs), and `lvs` (LVM) are the
day-to-day monitoring commands.

---

## 2. Btrfs: subvolumes and snapshots

```bash
sudo btrfs subvolume list /                     # list subvolumes/snapshots
sudo btrfs subvolume create /data               # a subvolume

# Read-write snapshot
sudo btrfs subvolume snapshot /data /data/.snapshots/data-$(date +%F)

# Read-ONLY snapshot — REQUIRED as the source of `btrfs send`
sudo btrfs subvolume snapshot -r /data /data/.snapshots/data-$(date +%F)
```

Snapshots are near-instant and share unchanged extents with the origin (COW), so
they cost almost no space at creation.

---

## 3. Btrfs: send / receive

```bash
# Full send of a read-only snapshot to another host
sudo btrfs send /data/.snapshots/data-2026-06-15 | \
     ssh backup@offsite 'btrfs receive /mnt/backup/'

# Incremental: send only the delta vs a parent snapshot (-p)
sudo btrfs send -p /data/.snapshots/data-2026-06-14 \
                   /data/.snapshots/data-2026-06-15 | \
     ssh backup@offsite 'btrfs receive /mnt/backup/'
```

The parent snapshot must already exist on the receiving side for an incremental.
Both endpoints must be Btrfs.

[GROUNDING-GAP: `btrfs send|receive` (the read-only-snapshot requirement, `-p`
single parent vs `-c` clone sources, and incremental chains) is from upstream
btrfs-progs man pages, not the conceptual Fedora Essentials source. Deepen with
UNIX & Linux System Administration Handbook.]

---

## 4. Btrfs: rollback

Btrfs has no single "rollback" verb; you swap the live subvolume for a snapshot:

```bash
sudo btrfs subvolume delete /data
sudo btrfs subvolume snapshot /data/.snapshots/data-2026-06-15 /data
# remount / update fstab subvol= if the subvolume is mounted by id
```

Destructive — discards everything written since the snapshot. On Fedora,
`snapper` automates snapshot/rollback policy on top of this.

---

## 5. ZFS: datasets and snapshots

```bash
sudo zfs snapshot tank/data@2026-06-15      # dataset@snapname
zfs list -t snapshot                         # list snapshots
zfs list -t snapshot -o name,used,creation tank/data
sudo zfs destroy tank/data@2026-06-15        # delete a snapshot
```

Snapshots are atomic, instant, and read-only. `tank/data@name` is the canonical
`dataset@snapshot` form.

---

## 6. ZFS: send / recv

```bash
# Full replication
sudo zfs send tank/data@2026-06-15 | ssh backup@offsite 'zfs recv backup/data'

# Incremental between two snapshots (-i)
sudo zfs send -i tank/data@2026-06-14 tank/data@2026-06-15 | \
     ssh backup@offsite 'zfs recv backup/data'

# Resumable receive (-s on recv yields a token to resume an interrupted stream)
sudo zfs recv -s backup/data
```

[GROUNDING-GAP: `zfs send|recv` (`-i` incremental vs `-I` intermediary,
resumable `-s` receive tokens, raw `-w` encrypted sends) is from upstream
OpenZFS docs, not the conceptual Fedora Essentials source. Deepen with UNIX &
Linux System Administration Handbook.]

---

## 7. ZFS: rollback and clones

```bash
sudo zfs rollback tank/data@2026-06-15        # revert dataset (destructive)
sudo zfs rollback -r tank/data@2026-06-15     # also destroy intermediate snaps
sudo zfs clone tank/data@2026-06-15 tank/data-clone   # writable clone of a snap
```

`zfs rollback` discards all changes (and snapshots) made after the named
snapshot. A `clone` gives a writable branch without destroying anything.

---

## 8. Availability per family

| | Debian/Ubuntu | RHEL family |
|---|---|---|
| Btrfs | `apt install btrfs-progs` | preinstalled on **Fedora** (default FS); `dnf install btrfs-progs` elsewhere |
| ZFS | `apt install zfsutils-linux` (universe) | OpenZFS DKMS repo + `dnf install zfs`; **not** in base RHEL (CDDL/GPL licence conflict) |

[GROUNDING-GAP: the OpenZFS-on-Linux DKMS install and the CDDL/GPL licensing
constraint are from upstream OpenZFS docs; deepen with UNIX & Linux System
Administration Handbook.]

On an XFS or ext4 root (the RHEL-family default), neither Btrfs nor ZFS applies
to the root — use **LVM** snapshots ([`lvm-snapshots.md`](lvm-snapshots.md)).

---

## Sources

- Richard Johnson, *Fedora Linux Essentials* — conceptual comparison of LVM,
  Btrfs, and ZFS (COW, checksums, snapshot cost, use cases); `zpool status` /
  `btrfs filesystem df` monitoring.
- `btrfs-subvolume(8)`, `btrfs-send(8)`, `btrfs-receive(8)` man pages.
- OpenZFS `zfs(8)` / `zfs-send(8)` / `zfs-receive(8)` documentation.
- Real-world experience with Btrfs snapshots on Fedora and ZFS on storage hosts.
