# CIFS / SMB (Samba) Client Mounts

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

How to mount Windows / Samba (SMB/CIFS) shares from a Linux client:
package install, manual `mount -t cifs`, credentials files,
persistent `/etc/fstab` entries, on-demand `autofs` maps, and
troubleshooting protocol-version and authentication failures. The deep
companion to `SKILL.md` for the network-mount half of the skill; for
block storage, LVM, and local fstab see
[`storage-reference.md`](storage-reference.md).

NFS is the other common network filesystem. It is covered in
`SKILL.md` and in the fstab/automount sections of
[`storage-reference.md`](storage-reference.md); this file is the SMB/CIFS
counterpart. Both families ship the same `cifs-utils` client; only the
install command differs.

## Distro support

The CIFS client lives in **`cifs-utils`** on both families — the
kernel `cifs` module plus the `mount.cifs` helper. The discovery tool
`smbclient` lives in a separate package. The mount syntax, credentials
files, fstab format, and autofs maps are **identical** on both families.

| Concept | Debian/Ubuntu | RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) |
|---|---|---|
| CIFS client + `mount.cifs` | `apt install cifs-utils` | `dnf install cifs-utils` |
| Share discovery (`smbclient -L`) | `apt install smbclient` | `dnf install samba-client` |
| Samba *server* (rarely on a client host) | `apt install samba` | `dnf install samba` |
| Kernel module | `cifs` (auto-loaded by `mount.cifs`) | same |
| Mount syntax / fstab / autofs | identical | identical |
| Firewall service name (server side) | `samba` (ufw app) | `samba` (firewalld service) |

In `sk-*` scripts use the `common.sh` package primitives
(`pkg_install`, `pkg_is_installed`) rather than hardcoding apt/dnf, so
the same helper installs `cifs-utils` on either family. See
[`linux-bash-scripting`](../../../10-automation-and-scripting/linux-bash-scripting/SKILL.md).

## Table of contents

1. SMB vs NFS — when to use CIFS
2. Install the client
3. Discover shares (`smbclient -L`)
4. Manual mount (`mount -t cifs`)
5. Credentials files (`/root/.smbcredentials`, 0600)
6. Persistent mounts in `/etc/fstab`
7. Ownership: `uid`, `gid`, `file_mode`, `dir_mode`
8. Protocol version: `vers=`
9. On-demand mounts with autofs
10. Troubleshooting (vers, kerberos vs ntlm, permissions)
11. The Samba *server* side (high level)
12. Sources

---

## 1. SMB vs NFS — when to use CIFS

| | CIFS / SMB | NFS |
|---|---|---|
| Native to | Windows / Samba | UNIX / Linux |
| Best for | Mounting a Windows file server or a NAS SMB share from Linux | Linux-to-Linux exports, home directories |
| Per-user identity | Carried by SMB credentials (username/password or Kerberos) | Carried by UID/GID (or `sec=krb5`) |
| Client package | `cifs-utils` | `nfs-common` (Debian) / `nfs-utils` (RHEL) |

Reach for CIFS when the **server is Windows or a NAS exposing SMB**, or
when the share lives in a mixed Windows/Linux environment. Reach for NFS
when both ends are Linux. The two coexist happily on the same client.

---

## 2. Install the client

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y cifs-utils smbclient

# RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)
sudo dnf install -y cifs-utils samba-client
```

`cifs-utils` provides `/sbin/mount.cifs` (the helper `mount -t cifs`
calls) and pulls in the kernel `cifs` module. `smbclient` /
`samba-client` provides the `smbclient` discovery tool — useful but not
required to mount.

Verify:

```bash
command -v mount.cifs        # /usr/sbin/mount.cifs or /sbin/mount.cifs
modinfo cifs | head -1       # kernel module present
```

---

## 3. Discover shares (`smbclient -L`)

Before mounting, list the shares a server offers:

```bash
smbclient -L //192.168.4.200 -U guest        # anonymous / guest listing
smbclient -L server2.example.com -U linda    # authenticated listing
```

Use the **IP address** to sidestep name-resolution problems while
testing. When prompted for a password on an anonymous listing, just
press Enter. Typical output names each `Sharename` and its `Type`
(`Disk`, `IPC`, `Printer`).

---

## 4. Manual mount (`mount -t cifs`)

Test the mount by hand before committing it to fstab.

```bash
sudo mkdir -p /mnt/share

# Guest (read-only on most shares):
sudo mount -t cifs -o guest //192.168.4.200/data /mnt/share

# Authenticated — mount prompts for the password:
sudo mount -t cifs -o username=linda //server2/sambashare /mnt/share

# Verify and unmount:
findmnt /mnt/share
sudo umount /mnt/share
```

The leading `//server/share` uses **forward slashes** (UNC path with
`/` not `\`). `mount` can usually auto-detect a CIFS target even without
`-t cifs`, but stating it is clearer and avoids surprises.

---

## 5. Credentials files (`/root/.smbcredentials`, 0600)

**Never** put `username=`/`password=` in plaintext in `/etc/fstab` — it
is world-readable. Put them in a root-owned credentials file instead and
reference it with `credentials=`.

```bash
sudo tee /root/.smbcredentials >/dev/null <<'EOF'
username=linda
password=SuperSecret
domain=WORKGROUP
EOF

sudo chown root:root /root/.smbcredentials
sudo chmod 600 /root/.smbcredentials        # MUST be 0600 — readable only by root
```

The `domain=` line is optional (set it for a Windows AD/workgroup;
omit it for a standalone Samba server). Mount with:

```bash
sudo mount -t cifs -o credentials=/root/.smbcredentials //server2/sambashare /mnt/share
```

> **Note on the 0600 requirement:** the credentials file holds a
> cleartext password. If it is group- or world-readable, any local user
> can read the share's password. `mount.cifs` does not enforce 0600, so
> the discipline is on you — `sk-cifs-mount` checks and refuses to
> proceed if the mode is looser than 0600.

---

## 6. Persistent mounts in `/etc/fstab`

The fstab field order is identical to local mounts:
`<device> <mountpoint> <fstype> <options> <dump> <pass>`. For CIFS the
device is the UNC path, the fstype is `cifs`, and `<dump>`/`<pass>` are
both `0` (no dump, no boot-time fsck on a network share).

The naive (insecure) form the RHCSA guide shows — credentials inline:

```
//server2/sambashare  /sambamount  cifs  username=linda,password=password  0  0
```

The recommended form — credentials in a 0600 file, with sane options:

```
//server2/sambashare  /sambamount  cifs  credentials=/root/.smbcredentials,uid=1000,gid=1000,vers=3.0,_netdev,nofail,x-systemd.automount  0  0
```

Key options for a network mount:

| Option | Effect |
|---|---|
| `credentials=<file>` | Read username/password/domain from a 0600 file (section 5). |
| `_netdev` | Mark as network-dependent; systemd waits for the network before mounting. **Always set on CIFS.** |
| `nofail` | Do not drop to emergency shell if the server is unreachable at boot. |
| `x-systemd.automount` | Lazy-mount on first access instead of at boot — survives a server that is briefly down. |
| `x-systemd.device-timeout=10s` | Give up waiting after 10s. |
| `uid=`, `gid=` | Map all files to a local user/group (section 7). |
| `vers=` | Pin the SMB protocol version (section 8). |
| `iocharset=utf8` | Correct handling of non-ASCII filenames. |

Test before rebooting:

```bash
sudo mount -a              # applies fstab now; fails loudly on a typo
findmnt /sambamount
```

Always `mount -a` (or trigger the automount) after editing fstab —
**before** you reboot — so a mistake surfaces at the prompt, not at boot.

---

## 7. Ownership: `uid`, `gid`, `file_mode`, `dir_mode`

SMB carries Windows-style ACLs, not POSIX UID/GID. By default every file
on a CIFS mount appears owned by the user who ran `mount` (usually
`root`). To make the share usable by a normal local user, map ownership
at mount time:

```
//nas/media  /mnt/media  cifs  credentials=/root/.smbcredentials,uid=1000,gid=1000,file_mode=0664,dir_mode=0775,_netdev,nofail  0  0
```

- `uid=1000,gid=1000` — present every file as owned by that local
  user/group. Use the numeric ID (`id -u peter`) or the name.
- `file_mode=`, `dir_mode=` — the permission bits Linux *reports* for
  files and directories. They do not change permissions on the server;
  they control what the local kernel shows.

This only affects how the mount is *presented* locally — actual write
access is still governed by the SMB credentials and the server's ACLs.

---

## 8. Protocol version: `vers=`

`vers=` selects the SMB dialect. Mismatches are the single most common
cause of "mount error(112): Host is down" or "mount error(95):
Operation not supported", even when the server is up.

| `vers=` | Use with |
|---|---|
| `3.1.1` | Windows 10/11, Windows Server 2016+, recent Samba. Most secure; try first. |
| `3.0` | Windows 8 / Server 2012, older Samba 4. |
| `2.1` | Windows 7 / Server 2008 R2. |
| `1.0` | Ancient SMB1 / NT4 / very old NAS. **Disabled by default** on modern kernels and Windows — insecure; avoid unless forced. |

Modern `mount.cifs` negotiates automatically, but pinning `vers=` makes
the mount deterministic. If a mount fails, explicitly try `vers=3.0`
then `vers=2.1`. Do **not** reach for `vers=1.0` to "make it work" —
SMB1 is a known security liability; upgrade the server instead.

---

## 9. On-demand mounts with autofs

autofs mounts a share on first access and unmounts it after an idle
period — ideal for shares that are not always needed or for servers that
are occasionally offline. It works for CIFS exactly as it does for NFS.

```bash
# Install
sudo apt install -y autofs          # Debian/Ubuntu
sudo dnf install -y autofs          # RHEL family
```

Two-file configuration: a master map points at a secondary map.

```bash
# /etc/auto.master  — mount point + secondary map
/cifs   /etc/auto.cifs   --timeout=60
```

```bash
# /etc/auto.cifs  — <key> <options> <location>
sambashare  -fstype=cifs,credentials=/root/.smbcredentials,uid=1000,gid=1000,vers=3.0  ://server2/sambashare
```

Note the autofs quirk for CIFS: the location uses a **single leading
colon** before the UNC path (`://server/share`), and options go on the
`-fstype=cifs,...` token. Then:

```bash
sudo systemctl enable --now autofs
cd /cifs/sambashare        # triggers the mount on first access
findmnt /cifs/sambashare
```

A **wildcard** map mounts a per-key subdirectory on demand (handy for
home directories or per-host shares):

```bash
# /etc/auto.cifs
*  -fstype=cifs,credentials=/root/.smbcredentials,vers=3.0  ://nas/users/&
```

The `*` matches the accessed subdirectory and `&` substitutes it into
the server path, so `cd /cifs/peter` mounts `//nas/users/peter`.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `mount error(112): Host is down` | SMB version mismatch (not actually down) | Add `vers=3.0` (then `2.1`). |
| `mount error(95): Operation not supported` | Server requires a dialect the client refused | Set an explicit `vers=`. |
| `mount error(13): Permission denied` | Bad username/password, or wrong `domain=` | Check the credentials file; try `smbclient -L` with the same creds. |
| `mount error(13)` *after* an upgrade | Server enforces NTLMv2 / SMB signing, client offered weaker | Add `sec=ntlmssp` (modern) — see below. |
| `mount.cifs: bad UNC` | Backslashes instead of forward slashes | Use `//server/share`, not `\\server\share`. |
| Files owned by `root`, user can't write | No `uid`/`gid` mapping | Add `uid=`, `gid=` (section 7). |
| `mount: command not found` for cifs | `cifs-utils` not installed | `apt/dnf install cifs-utils`. |
| Boot hangs / drops to emergency shell | Network share in fstab without `_netdev`/`nofail` | Add `_netdev,nofail` (and ideally `x-systemd.automount`). |

### Kerberos vs NTLM authentication (`sec=`)

CIFS supports several authentication mechanisms, selected with `sec=`:

| `sec=` | Meaning |
|---|---|
| `ntlmssp` | NTLMv2 over NTLMSSP — the modern default for username/password against Windows or Samba. |
| `ntlmv2` | NTLMv2 (older negotiation). |
| `krb5` | Kerberos (single sign-on in an Active Directory / FreeIPA realm — no password in the credentials file; the host uses its keytab / the user's ticket). |
| `krb5i` | Kerberos with packet integrity checking. |

- **Workgroup / standalone Samba / simple Windows share** → username +
  password, `sec=ntlmssp` (usually auto-selected; set it explicitly if a
  mount that used to work starts returning `error(13)` after the server
  tightens its policy).
- **Active Directory / FreeIPA domain** → `sec=krb5`. The client must be
  joined to the realm and have a valid ticket (`kinit`) or a machine
  keytab; **no** `password=`/`credentials=` is used. This is the right
  path when the user complains "it works with my AD login on Windows but
  not on Linux" — they need a Kerberos ticket, not a credentials file.

`error(112)`/`error(95)` are almost always `vers=`; `error(13)` is
almost always credentials or `sec=`. Triage in that order.

---

## 11. The Samba *server* side (high level)

This skill is about **mounting** SMB shares from a Linux client. You
will rarely run a Samba *server* on the same host. If you do need to
export a directory over SMB, the high-level shape is:

```bash
sudo dnf install -y samba           # or: sudo apt install -y samba
# Add a share stanza to /etc/samba/smb.conf, e.g.:
#   [sambashare]
#   comment  = sambashare
#   path     = /sambashare
#   read only = No
sudo smbpasswd -a linda             # give an existing Linux user a Samba password
sudo systemctl enable --now smb     # 'smb' on RHEL; 'smbd' on Debian/Ubuntu
sudo firewall-cmd --add-service samba --permanent && sudo firewall-cmd --reload   # RHEL
# Debian/Ubuntu: sudo ufw allow samba
```

On RHEL with SELinux enforcing, label the shared directory so Samba may
serve it:

```bash
sudo semanage fcontext -a -t samba_share_t "/sambashare(/.*)?"
sudo restorecon -Rv /sambashare
```

Full Samba server hardening, per-user/per-group ACLs, and integration
with a web/file-sharing stack are out of scope here — treat this section
as a pointer. For the broader web/services stack on these hosts see
[`linux-webstack`](../../../04-web-and-mail-services/linux-webstack/SKILL.md).

---

## 12. Sources

- **Red Hat RHCSA 8 Cert Guide (EX200), 2nd ed.**, Sander van Vugt,
  Chapter 24 "Configuring Network Services" — Using CIFS Services
  (`cifs-utils`, `samba-client`, `smbclient -L`, `mount -t cifs -o
  username=`), mounting Samba through `/etc/fstab`, and automount maps.
- **Red Hat RHCSA 9/10 Cert Guide**, Sander van Vugt — same network-mount
  chapter, updated for current SMB dialects.
- `mount.cifs(8)` man page — the authoritative list of `-o` options:
  `credentials`, `uid`, `gid`, `file_mode`, `dir_mode`, `vers`, `sec`,
  `_netdev`, `iocharset`.
- `fstab(5)`, `autofs(5)`, `auto.master(5)`, `smbclient(1)` man pages.
- Real-world experience mounting Windows / NAS SMB shares on production
  Ubuntu and Rocky/Alma servers (the `vers=`, `uid=/gid=`,
  `credentials=` 0600, and `sec=ntlmssp`/`krb5` guidance is operational
  practice, not from the RHCSA text, which stops at inline credentials).
