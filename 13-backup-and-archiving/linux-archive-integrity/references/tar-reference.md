# tar reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Complete `tar` reference for creating, inspecting, and extracting archives with
full metadata fidelity. Works on a stock Debian/Ubuntu or RHEL-family install.
Companion to the skill body; incremental backups and verification live in
[`incremental-and-verify.md`](incremental-and-verify.md).

## Table of contents

1. The four core operations
2. Option ordering and the dash
3. Compression
4. The `-C` directory trick
5. Metadata flags
6. Adding to and updating an archive
7. Extracting selectively
8. Sources

---

## 1. The four core operations

The RHCSA exam frames `tar` around four tasks; they map to four mode letters:

| Mode | Letter | Command |
|---|---|---|
| Create | `c` | `tar -cvf archive.tar files...` |
| List (table of contents) | `t` | `tar -tvf archive.tar` |
| Extract | `x` | `tar -xvf archive.tar` |
| Compare (diff vs filesystem) | `d` / `--compare` | `tar -df archive.tar` |

`-f` always names the archive file; `-v` is verbose. Grounded in Sander van
Vugt, *RHCSA 8 Cert Guide*.

---

## 2. Option ordering and the dash

Modern tar accepts the leading dash (`tar -cvf`) and, for backward
compatibility, the old dashless form (`tar cvf`). The **order of clustered
options matters**: `-f` must be immediately followed by the archive name.

```bash
tar -cvf /root/homes.tar /home       # f → /root/homes.tar, then /home is content
tar cvf /root/homes.tar /home        # equivalent (old style)
```

---

## 3. Compression

Add a compression letter to create; extraction auto-detects, so no letter is
needed on extract.

| Letter | Tool | Extension |
|---|---|---|
| `-z` | gzip | `.tar.gz` / `.tgz` |
| `-j` | bzip2 | `.tar.bz2` |
| `-J` | xz | `.tar.xz` |
| `--zstd` | zstd | `.tar.zst` |

```bash
tar -czf etc.tar.gz /etc       # gzip
tar -cJf etc.tar.xz /etc       # xz (best ratio, slow)
tar -tvf etc.tar.gz            # list — tar auto-detects the compression
```

Grounded in RHCSA: `-z`/`-j` create compressed archives; `tar tvf etc.tar.gz`
lists a gzip archive without a decompress step.

| Tool | CPU | Ratio | When |
|---|---|---|---|
| gzip | fast | medium | Default; universal. |
| xz | slow | best | Cold archives, disk-bound hosts. |
| bzip2 | medium | medium | Legacy. |
| zstd | fast | very good | Modern; needs `zstd`. |

---

## 4. The `-C` directory trick

`-C DIR` changes directory before archiving/extracting, controlling the paths
stored in (and restored from) the archive.

```bash
# Store 'www/...' rather than '/var/www/...'
tar -czf www.tar.gz -C /var www

# Extract into /tmp regardless of cwd
tar -xzf www.tar.gz -C /tmp
```

Grounded in RHCSA: `tar -xvf homes.tar -C /tmp` extracts into `/tmp`.

By default tar **strips the leading `/`** from stored paths (so archives are
relocatable and never overwrite `/` on extract). Keep it that way.

---

## 5. Metadata flags

| Flag | Preserves |
|---|---|
| `-p` / `--preserve-permissions` | permissions (implicit for root on extract) |
| `--numeric-owner` | UID/GID as numbers, not names — **essential cross-host** |
| `--acls` | POSIX ACLs (`getfacl`/`setfacl`) |
| `--xattrs` | extended attributes (capabilities, `security.*`) |
| `--selinux` | SELinux contexts (stored as a `security.selinux` xattr; RHEL) |
| `--same-owner` | restore original owner (default for root) |

```bash
# Full-fidelity create (RHEL-aware)
sudo tar --acls --xattrs --selinux --numeric-owner -czf /backups/etc.tar.gz -C / etc

# Extract with the SAME flags or the metadata is dropped
sudo tar --acls --xattrs --selinux --numeric-owner -xzf /backups/etc.tar.gz -C /
```

Historically `star` was needed for ACLs/SELinux; modern `tar` covers this, so
`star` is no longer required (RHCSA note, Sander van Vugt). On restore to a new
host, `--numeric-owner` avoids mapping UIDs to the wrong names.

---

## 6. Adding to and updating an archive

```bash
tar -rvf homes.tar /etc/hosts     # -r : append a file to an existing .tar
tar -uvf homes.tar /home          # -u : add only files newer than the archived copy
```

`-r` and `-u` work on **uncompressed** `.tar` only (you cannot append to a
`.gz`/`.xz` stream). Grounded in RHCSA.

---

## 7. Extracting selectively

```bash
tar -tvf etc.tar                       # list to find the member path
tar -xvf etc.tar etc/hosts             # extract one member
tar -xzf www.tar.gz --wildcards '*.conf'   # extract by glob
tar -xzf www.tar.gz --strip-components=1   # drop the leading path component
```

Grounded in RHCSA: `tar -xvf /root/etc.tar etc/hosts` extracts a single file.

---

## Sources

- Sander van Vugt, *Red Hat RHCSA 8 Cert Guide (EX200)*, 2nd ed. — the four
  tar operations, compression letters, `-C`, `-r`/`-u`, selective extract, and
  the `star`-vs-modern-`tar` note for ACLs/SELinux.
- `tar(1)` man page — `--acls`, `--xattrs`, `--numeric-owner`, `--selinux`.
- Real-world experience archiving `/etc`, `/var/www`, and config trees on
  production Linux servers.
