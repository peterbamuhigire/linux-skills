---
name: linux-archive-integrity
description: Create and VERIFY tar archives (tar.gz / tar.xz) that preserve full metadata on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). tar is identical on both families; the gotcha is SELinux contexts and ACL/xattr packages on RHEL. Covers metadata-preserving archives (--acls --xattrs --numeric-owner), gzip vs xz compression trade-offs, listed-incremental level-0/level-1 backups (--listed-incremental), integrity verification (tar -tvf listing, tar --compare against the live tree, sha256 sidecar files), and optional GPG signing/encryption of the archive. Always verifies an archive after creating it.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Archive Integrity (tar + verify)

## Distro support

`tar`, `gzip`, `xz`, `sha256sum`, and `gpg` are identical on both families.
The only real differences are SELinux contexts (RHEL labels files; capture them
with `--xattrs --selinux`) and that ACL/xattr support needs the `acl`/`attr`
packages present. Body uses Debian/Ubuntu; the **RHEL family** (Fedora, RHEL,
CentOS Stream, Rocky, Alma, Oracle) notes are in the matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Install tar/xz | preinstalled; `apt install xz-utils` | preinstalled; `dnf install xz` |
| ACL / xattr tooling | `apt install acl attr` | `dnf install acl attr` |
| `--acls --xattrs --numeric-owner` | identical | identical |
| `--listed-incremental` (level 0/1) | identical | identical |
| SELinux context capture | n/a (not labelled) | add `--selinux` (stored as an xattr) and/or `restorecon -R` on restore |
| GPG signing/encryption | `apt install gnupg` | `dnf install gnupg2` |

**RHEL-family gotcha:** with SELinux enforcing, an archive restored to a new
path can land with the wrong context. Either capture contexts with
`tar --xattrs --selinux` (they ride along as `security.selinux` xattrs) or run
`restorecon -R <path>` after extraction. `--numeric-owner` is essential when
restoring onto a host whose UID/GID-to-name mapping differs from the source.

In `sk-*` scripts use the `common.sh` package primitives rather than hardcoding
apt/dnf. See
[`../../10-automation-and-scripting/linux-bash-scripting/SKILL.md`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md)
and [`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Creating a sealed, portable archive of a directory tree with permissions,
  ownership, ACLs, and xattrs intact.
- Verifying that an archive is intact and restorable *before* you rely on it.
- Running level-0 / level-1 incremental tar backups with a snapshot file.
- Producing a sha256 sidecar or GPG-signed archive for tamper-evidence.

## Do not use when

- You want an efficient mirror or hard-linked snapshot tree; use
  [`../linux-rsync-sync/SKILL.md`](../linux-rsync-sync/SKILL.md).
- You need a crash-consistent image of a live database volume; use
  [`../linux-filesystem-snapshots/SKILL.md`](../linux-filesystem-snapshots/SKILL.md).
- You are restoring an existing encrypted backup in an incident; use
  [`../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md`](../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md).

## Required inputs

- The directory tree to archive and the archive destination path.
- The compression choice (gzip for universal/fast, xz for best ratio).
- Whether metadata fidelity (ACLs, xattrs, SELinux, numeric owner) is required.
- Whether a sha256 sidecar and/or GPG signature is required.

## Workflow

1. Create the archive with the metadata flags the restore target needs.
2. Verify immediately: list it (`tar -tvf`) and ideally `--compare` it against
   the source tree.
3. Write a `.sha256` sidecar; optionally sign/encrypt with GPG.
4. Record the archive path, size, and verification result.

## Quality standards

- An unverified archive is not a backup. Always list or compare after create.
- Use `--numeric-owner` for any archive that may restore to a different host.
- Prefer gzip for live/rotated backups (universal, fast); xz for cold archives.
- Keep the sha256 sidecar next to the archive and offsite alongside it.

## Anti-patterns

- Creating an archive and never test-listing it.
- Dropping ACLs/xattrs/SELinux silently on metadata-sensitive trees.
- Treating `tar` exit 0 as proof of integrity without a `--compare` or checksum.
- Storing the GPG/sha256 verifier in the same blob it is meant to verify.

## Outputs

- The exact `tar` create command and the verification command(s) run.
- Archive path, compressed size, and sha256 digest.
- Any GPG signature/encryption produced and where its key lives.

## References

- [`references/tar-reference.md`](references/tar-reference.md)
- [`references/incremental-and-verify.md`](references/incremental-and-verify.md)

**This skill is self-contained.** Every command below is stock `tar` / `gpg` /
`sha256sum` on both families (the body shows Debian/Ubuntu; see **Distro
support** above for RHEL-family notes). The `sk-tar-verify` script in the
**Optional fast path** section is a convenience wrapper — never required.

## Create A Compressed Archive

```bash
# gzip (.tar.gz) — universal, fast, good default for rotated backups
tar -czf /backups/www-$(date +%F).tar.gz -C /var www

# xz (.tar.xz) — best ratio, slow CPU; use for cold/archival copies
tar -cJf /backups/www-$(date +%F).tar.xz -C /var www

# -C changes directory first so the archive holds 'www/...' not '/var/www/...'
```

Grounded in RHCSA: `tar -cvf archive.tar /files`, `-z` for gzip, `-j` for
bzip2, `-J` for xz; `-C /targetdir` controls the path stored/extracted (Sander
van Vugt, RHCSA 8 Cert Guide).

Compression trade-offs:

| Tool | CPU | Ratio | When |
|---|---|---|---|
| `gzip` (`-z`, `.gz`) | fast | medium | Default. Every Unix reads it. |
| `xz` (`-J`, `.xz`) | slow | best | Cold archives, disk-bound hosts. |
| `bzip2` (`-j`, `.bz2`) | medium | medium | Legacy; rarely the best choice now. |
| `zstd` (`--zstd`, `.zst`) | fast | very good | Modern; needs `zstd` package. |

---

## Preserve Permissions / Ownership / ACLs / xattrs

```bash
# Full-fidelity archive: numeric UID/GID, POSIX ACLs, extended attributes.
sudo tar --acls --xattrs --numeric-owner -czf /backups/etc-$(date +%F).tar.gz \
         -C / etc

# On RHEL with SELinux, also capture the security context xattr:
sudo tar --acls --xattrs --selinux --numeric-owner \
         -czf /backups/www-$(date +%F).tar.gz -C /var www
```

- `--numeric-owner` — store UID/GID numbers, not names. Essential for restoring
  onto a host with a different `/etc/passwd` mapping.
- `--acls` — preserve POSIX ACLs (`getfacl`/`setfacl` entries).
- `--xattrs` — preserve extended attributes (capabilities, `security.*`).
- Extract with the same flags (`tar --acls --xattrs -xzf ...`) or the metadata
  is dropped on restore.

---

## Listed-Incremental (level-0 / level-1) Backups

`--listed-incremental=SNAP` records file state in a snapshot file. The first run
(snapshot file absent/empty) is a **full level-0**; subsequent runs capture only
what changed since — a **level-1 incremental**.

```bash
SNAP=/backups/www.snar

# Level 0 (full) — fresh snapshot file
sudo tar --listed-incremental="$SNAP" -czf /backups/www-L0.tar.gz -C /var www

# Level 1 (incremental) — same snapshot file, now populated
sudo tar --listed-incremental="$SNAP" -czf /backups/www-L1-$(date +%F).tar.gz -C /var www
```

Restore by extracting level-0 first, then each incremental **in order** (use
`--incremental` on extract so deletions are replayed). Keep the `.snar` snapshot
file with the backup set — without it you cannot continue the chain.

Full incremental chain and restore order:
[`references/incremental-and-verify.md`](references/incremental-and-verify.md).

---

## Verify The Archive

```bash
# 1. List contents (cheap sanity check; -v shows perms/owner/size)
tar -tvf /backups/www-$(date +%F).tar.gz | head

# 2. Compare archive against the live tree — flags any file that differs
sudo tar --acls --xattrs --compare -f /backups/www-$(date +%F).tar.gz -C /var
#                                  ^ --compare / -d : diff archive vs filesystem

# 3. sha256 sidecar — tamper-evidence and corruption detection
sha256sum /backups/www-$(date +%F).tar.gz > /backups/www-$(date +%F).tar.gz.sha256
sha256sum -c /backups/www-$(date +%F).tar.gz.sha256   # verify later
```

`tar -tvf` succeeding proves the archive is *readable and complete*; a clean
`--compare` proves it *matches the source*; the `.sha256` proves it has *not
changed on disk* since creation. A real backup uses all three.

Grounded in RHCSA: `tar -tvf` lists archive contents before extraction (Sander
van Vugt, RHCSA 8 Cert Guide).

---

## Optional GPG Signing / Encryption

```bash
# Detached signature (tamper-evidence; recipients verify with your public key)
gpg --detach-sign --armor /backups/www-$(date +%F).tar.gz
gpg --verify /backups/www-$(date +%F).tar.gz.asc /backups/www-$(date +%F).tar.gz

# Symmetric encryption for an offsite copy (AES256, passphrase from a 0600 file)
gpg --batch --symmetric --cipher-algo AES256 \
    --passphrase-file ~/.backup-encryption-key \
    -o /backups/www-$(date +%F).tar.gz.gpg /backups/www-$(date +%F).tar.gz
```

Key hygiene (store the key off the server, never in the backup it unlocks) is
covered in
[`../../09-troubleshooting-and-recovery/linux-disaster-recovery/references/backup-strategy.md`](../../09-troubleshooting-and-recovery/linux-disaster-recovery/references/backup-strategy.md).

[GROUNDING-GAP: Modern dedup/snapshot backup tools — borg and restic — supersede
hand-rolled tar incrementals for many use cases (dedup, encryption, prune
policies). Not covered here; from upstream borg/restic docs; deepen with UNIX &
Linux System Administration Handbook.]

Full tar flag reference: [`references/tar-reference.md`](references/tar-reference.md).

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-archive-integrity` installs:

| Task | Fast-path script |
|---|---|
| Create a metadata-preserving archive, then auto-verify + sha256 | `sudo sk-tar-verify --src /var/www --out /backups/www.tar.gz` |
| Verify an existing archive (list + sha256 + optional --compare) | `sudo sk-tar-verify --check /backups/www.tar.gz` |

This is an optional wrapper around the `tar` commands above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-archive-integrity
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-tar-verify | scripts/sk-tar-verify.sh | no | Create a `--acls --xattrs --numeric-owner` tar.gz/tar.xz archive then VERIFY it (`tar -tvf` listing, `sha256sum` sidecar, optional `--compare` against source); or in `--check` mode verify an existing archive. Asks before overwriting an existing archive. |
