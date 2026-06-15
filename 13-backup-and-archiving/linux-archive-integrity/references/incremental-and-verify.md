# tar incremental backups and verification

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

`--listed-incremental` level-0/level-1 backups, the three layers of archive
verification, and sha256/GPG tamper-evidence. Companion to
[`tar-reference.md`](tar-reference.md).

## Table of contents

1. Incremental backups with a snapshot file
2. Restoring an incremental chain
3. Verification layer 1: list (`-tvf`)
4. Verification layer 2: compare (`--compare`)
5. Verification layer 3: sha256 sidecar
6. GPG signing and encryption
7. Sources

---

## 1. Incremental backups with a snapshot file

`--listed-incremental=SNAP` (a.k.a. `-g SNAP`) records each file's state in the
snapshot file `SNAP`. tar uses it to decide what changed since last time.

- **Level 0 (full):** snapshot file does not exist (or is empty) → everything is
  archived and the snapshot is populated.
- **Level 1 (incremental):** snapshot file already populated → only files
  changed since the last run are archived; the snapshot is updated in place.

```bash
SNAP=/backups/www.snar

# Level 0 — full. Fresh snapshot file is created.
sudo tar --listed-incremental="$SNAP" -czf /backups/www-L0.tar.gz -C /var www

# Level 1 — daily incremental. Reuses (and updates) the same snapshot file.
sudo tar --listed-incremental="$SNAP" -czf /backups/www-L1-$(date +%F).tar.gz -C /var www
```

For a weekly full + daily incrementals pattern, copy the level-0 `.snar` to a
read-only seed and pass a **copy** of it to each daily run if you want each
daily to be a delta-since-the-weekly-full (level 1) rather than a chained delta.

---

## 2. Restoring an incremental chain

Extract the level-0 first, then each incremental **in creation order**, with
`--incremental` (`-G`) so that files deleted between increments are removed on
restore:

```bash
sudo tar --incremental -xzf /backups/www-L0.tar.gz       -C /restore
sudo tar --incremental -xzf /backups/www-L1-2026-06-14.tar.gz -C /restore
sudo tar --incremental -xzf /backups/www-L1-2026-06-15.tar.gz -C /restore
```

Keep the `.snar` snapshot file **with** the backup set. Without it you cannot
take the next incremental in the chain (though you can still extract existing
archives).

---

## 3. Verification layer 1: list (`-tvf`)

Proves the archive is readable and complete end-to-end (decompression + member
table parse succeed).

```bash
tar -tvf /backups/www-L0.tar.gz | head
tar -tzvf /backups/www-L0.tar.gz | wc -l    # member count
```

---

## 4. Verification layer 2: compare (`--compare`)

Proves the archive's contents and metadata match the live filesystem.

```bash
sudo tar --acls --xattrs --compare -f /backups/www-L0.tar.gz -C /var
```

Output lists any member whose size, mtime, mode, or content differs from the
on-disk file. Empty output = archive faithfully represents the source. (Expect
benign diffs if the source changed after the archive was made.)

---

## 5. Verification layer 3: sha256 sidecar

Proves the archive bytes have not changed on disk since creation (corruption,
tampering, partial upload).

```bash
sha256sum /backups/www-L0.tar.gz > /backups/www-L0.tar.gz.sha256
sha256sum -c /backups/www-L0.tar.gz.sha256     # later / after transfer
# /backups/www-L0.tar.gz: OK
```

Store the `.sha256` next to the archive **and** offsite alongside it. Verify
after every copy/upload — this catches the silent "the upload truncated" failure.

---

## 6. GPG signing and encryption

```bash
# Detached signature — tamper-evidence; recipients verify with your public key
gpg --detach-sign --armor /backups/www-L0.tar.gz
gpg --verify /backups/www-L0.tar.gz.asc /backups/www-L0.tar.gz

# Symmetric encryption for an offsite copy (AES256)
gpg --batch --symmetric --cipher-algo AES256 \
    --passphrase-file ~/.backup-encryption-key \
    -o /backups/www-L0.tar.gz.gpg /backups/www-L0.tar.gz
```

Key hygiene — store the passphrase/key off the server and never inside the
backup it unlocks — is in the disaster-recovery
[`backup-strategy.md`](../../../09-troubleshooting-and-recovery/linux-disaster-recovery/references/backup-strategy.md).

[GROUNDING-GAP: borg and restic (deduplicating, encrypted, prune-aware backup
tools) replace hand-rolled tar incrementals for many production cases. From
upstream borg/restic docs; deepen with UNIX & Linux System Administration
Handbook.]

---

## Sources

- Sander van Vugt, *Red Hat RHCSA 8 Cert Guide (EX200)*, 2nd ed. — `tar -tvf`
  listing before extraction; tar archive operations.
- `tar(1)` man page — `--listed-incremental`, `--incremental`, `--compare`.
- `gpg(1)`, `sha256sum(1)` man pages.
- Real-world experience verifying archive backups on production Linux servers.
