# Ubuntu autoinstall reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Ubuntu 20.04 LTS introduced a new server installer (subiquity) and with
it a new automation format called **autoinstall**. It replaces the
Debian preseed flow used by previous releases. Unlike preseed, the
autoinstall file is written in YAML, validated against a JSON schema,
and delivered through cloud-init's NoCloud datasource. This reference
documents the schema, how to deliver it, how to build a net-boot or ISO
install, and how to debug a failing autoinstall run. Every example is
copy-pasteable and starts with the mandatory `#cloud-config` /
`autoinstall:` framing.

## Table of contents

- [Autoinstall vs preseed](#autoinstall-vs-preseed)
- [The top-level wrapper](#the-top-level-wrapper)
- [`version` and `interactive-sections`](#version-and-interactive-sections)
- [`identity`](#identity)
- [`ssh`](#ssh)
- [`storage`](#storage)
  - [Layout modes](#layout-modes)
  - [Action-based custom partitioning](#action-based-custom-partitioning)
  - [Disk match specs](#disk-match-specs)
- [`network` (embedded netplan)](#network-embedded-netplan)
- [`apt` — mirrors, PPAs, geoip](#apt--mirrors-ppas-geoip)
- [`packages` and `snaps`](#packages-and-snaps)
- [`user-data` — chaining runtime cloud-init](#user-data--chaining-runtime-cloud-init)
- [`early-commands`, `late-commands`, `error-commands`](#early-commands-late-commands-error-commands)
- [`shutdown` and `reporting`](#shutdown-and-reporting)
- [Delivering the autoinstall config](#delivering-the-autoinstall-config)
- [Debugging a failing autoinstall](#debugging-a-failing-autoinstall)
- [Three worked examples](#three-worked-examples)
- [Sources](#sources)

## Autoinstall vs preseed

Preseed (`debconf-set-selections` format) worked question-by-question:
if the preseed didn't answer a screen, the installer stopped and asked
the user. Autoinstall inverts this. Quoting the Ubuntu Server Guide:

> autoinstalls are not like this: by default, if there is any
> autoinstall config at all, the installer takes the default for any
> unanswered question (and fails if there is no default).

You can opt screens back **in** with `interactive-sections`. The
practical effect is that autoinstall defaults to unattended; you only
add interactivity on purpose.

The file is validated against a JSON schema. Some sections (reporting,
error-commands, early-commands) are loaded and applied first so that
errors in the rest of the config can be reported through them.

## The top-level wrapper

autoinstall is delivered as **cloud-init user-data**. The autoinstall
config lives under an `autoinstall:` key so the same file can carry
both the installer config and runtime cloud-init user-data:

```yaml
#cloud-config
# Delivered via the NoCloud datasource; the installer's cloud-init reads this.
autoinstall:
  version: 1
  identity:
    hostname: web01
    username: peter
    password: "$6$rounds=4096$abc...$xyz..."
```

Rules:

- Line 1 must be `#cloud-config` — same magic header as runtime
  user-data.
- Everything under `autoinstall:` is the subiquity config. Everything
  else is interpreted as regular runtime cloud-init (rarely useful in
  the installer context — put runtime stuff under `autoinstall.user-data`).
- The file is named `user-data` and is served alongside a (possibly
  empty) `meta-data` file so NoCloud recognises it.

## `version` and `interactive-sections`

```yaml
autoinstall:
  version: 1                 # required; currently must be 1
  interactive-sections:
    - network                # stop and ask about network only
```

Use `interactive-sections: ["*"]` to force the installer to ask every
question but pre-populate the defaults from your file — useful for a
"guided" install where your team reviews every screen.

## `identity`

The initial user, hostname, and password. Required unless `user-data`
is present.

```yaml
autoinstall:
  identity:
    realname: Peter Bamuhigire
    username: peter
    hostname: web01
    # SHA-512 crypt. Generate with: mkpasswd --method=SHA-512
    password: "$6$rounds=4096$sGR0jNvN$ZHbu1w3YcnH/uOyhuH3fbshB9oQslEknQv1JiWq6ZAl2eDqvBZhz3PGTwlwOyLhMLh9nJTF.M9u1Y6xFk1yhh/"
```

The password is required even if you only intend to log in via SSH key,
because it is used by `sudo`.

## `ssh`

```yaml
autoinstall:
  ssh:
    install-server: true
    allow-pw: false          # false when authorized-keys is set
    authorized-keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop
      - ssh-rsa AAAAB3NzaC1yc2E... peter@backup
```

Fields:

- `install-server: true` — installs `openssh-server` during install.
  Without this, the machine boots with no SSH.
- `authorized-keys` — public keys written to the initial user's
  `~/.ssh/authorized_keys`.
- `allow-pw` — defaults to `false` if `authorized-keys` is non-empty,
  otherwise `true`. Set it explicitly so the behaviour is obvious.

## `storage`

Storage is the biggest and most error-prone section. Two modes exist:
**layout** (simple, high-level) and **action-based** (flexible, curtin
syntax). Use layout unless you need custom partitioning.

### Layout modes

Supported layouts: `lvm` (default), `direct`, `zfs`.

```yaml
autoinstall:
  storage:
    layout:
      name: lvm              # lvm | direct | zfs
      sizing-policy: scaled  # scaled | all (lvm only)
      match:                 # optional: pick which disk
        size: largest
```

- `lvm` — root FS on an LVM volume on a single PV. `sizing-policy:
  scaled` sizes the root LV to ~half the disk so snapshots and extra
  LVs have room. `all` uses the whole PV.
- `direct` — root filesystem directly on a partition, no LVM.
- `zfs` — ZFS root pool. Supported since 20.04; see example 3.

### Action-based custom partitioning

For RAID, encrypted root, or precise layouts, drop layout and supply
an action list. This is a superset of curtin syntax:

```yaml
autoinstall:
  storage:
    swap:
      size: 0                # no swapfile; we'll add one later
    config:
      - { type: disk, id: disk0, ptable: gpt, match: { ssd: true, size: largest }, grub_device: true }
      - { type: partition, id: boot-efi, device: disk0, size: 512M, flag: boot, grub_device: true }
      - { type: format, id: format-efi, volume: boot-efi, fstype: fat32 }
      - { type: mount, id: mount-efi, device: format-efi, path: /boot/efi }
      - { type: partition, id: boot, device: disk0, size: 1G }
      - { type: format, id: format-boot, volume: boot, fstype: ext4 }
      - { type: mount, id: mount-boot, device: format-boot, path: /boot }
      - { type: partition, id: root-part, device: disk0, size: -1 }   # rest of disk
      - { type: format, id: format-root, volume: root-part, fstype: ext4 }
      - { type: mount, id: mount-root, device: format-root, path: / }
```

Size extensions over curtin:

- Human sizes: `512M`, `20G`, `2T`.
- Percentages: `50%` of the containing disk.
- `-1` on the last partition — fill remaining space.

### Disk match specs

Instead of specifying a disk by its serial number, use `match`:

```yaml
- type: disk
  id: disk0
  match:
    model: Samsung                 # ID_VENDOR glob match
    path: /dev/nvme*n1             # DEVPATH glob match
    serial: CT*                    # ID_SERIAL glob match
    ssd: true                      # SSD vs rotating
    size: largest                  # largest | smallest
```

## `network` (embedded netplan)

The `network` key takes a literal netplan document. Default is DHCP on
any interface named `eth*` or `en*`.

```yaml
autoinstall:
  network:
    version: 2
    renderer: networkd
    ethernets:
      enp1s0:
        dhcp4: false
        addresses: [192.168.1.50/24]
        routes:
          - to: default
            via: 192.168.1.1
        nameservers:
          addresses: [1.1.1.1, 8.8.8.8]
```

A known quirk in the 20.04 GA release of subiquity required an extra
wrapping `network:` key (`network: { network: { version: 2, ... } }`).
Later versions accept both. If your installer rejects the config,
wrap it.

## `apt` — mirrors, PPAs, geoip

```yaml
autoinstall:
  apt:
    preserve_sources_list: false
    geoip: true
    primary:
      - arches: [default]
        uri: http://archive.ubuntu.com/ubuntu
    sources:
      certbot-ppa:
        source: "ppa:certbot/certbot"
```

- `geoip: true` — the installer queries `geoip.ubuntu.com` and swaps
  the mirror for the nearest country mirror (`CC.archive.ubuntu.com`).
- `preserve_sources_list: false` — let the installer write a fresh
  `sources.list`.
- `primary` — override the mirror entirely (for air-gapped or internal
  mirrors).

## `packages` and `snaps`

```yaml
autoinstall:
  packages:
    - nginx
    - ufw
    - fail2ban
    - postgresql-15
    - dns-server^            # task selection (trailing caret)
    - 'build-essential=12.9*' # version pin
  snaps:
    - name: lxd
      channel: latest/stable
      classic: false
    - name: microk8s
      channel: 1.28/stable
      classic: true
```

These install during the installer stage, before first boot. Anything
beyond the base server belongs here — do not push everything into a
post-install runcmd.

## `user-data` — chaining runtime cloud-init

The `user-data` key inside `autoinstall` is **runtime** cloud-init
merged with what the installer produces, and it runs on first boot of
the newly installed system. This is where you chain a second-stage
provisioning:

```yaml
autoinstall:
  version: 1
  identity: { ... }
  user-data:
    # This is the runtime cloud-init user-data, not the installer's.
    # On first boot after install, cloud-init runs this.
    timezone: Africa/Kampala
    package_update: true
    packages: [git, curl]
    runcmd:
      - [git, clone, 'https://github.com/petebwire/linux-skills.git', /root/.claude/skills]
      - /root/.claude/skills/scripts/install-skills-bin core
```

If you supply `user-data`, the Ubuntu guide notes you can omit
`identity` — but then you are responsible for making sure the runtime
user-data creates a way to log in (SSH keys, usually). Don't omit it
unless you know what you're doing.

## `early-commands`, `late-commands`, `error-commands`

These are shell command lists. Each item is either a string
(`sh -c "..."`) or an exec-style list.

```yaml
autoinstall:
  early-commands:
    # Runs at installer start, before disk/network probes.
    - [wipefs, -a, /dev/sda]
  late-commands:
    # Runs after install finishes, before reboot.
    # Installer env; target is mounted at /target.
    - curtin in-target -- systemctl enable nginx
    - echo 'peter ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/90-peter
    - chmod 440 /target/etc/sudoers.d/90-peter
  error-commands:
    # Runs only if the install fails. Copies logs somewhere useful.
    - tar czf /tmp/installer-logs.tgz /var/log/installer
    - curl -T /tmp/installer-logs.tgz http://logs.internal/install-failures/
```

When to use which:

- **early-commands** — to reshape the environment before the installer
  starts probing. Wipe signatures, rewrite the config file, poke
  drivers. The config file is re-read after early-commands finish.
- **late-commands** — for anything that must happen with the target FS
  mounted but the installed system not yet booted. Prefer
  `curtin in-target -- <cmd>` to chroot into the new system. Most of
  the time `user-data.runcmd` (which runs on first boot) is a cleaner
  choice.
- **error-commands** — runs only on failure. Non-zero exits are
  ignored. Use this to ship logs off-box before the installer halts.

A non-zero exit from any early/late command aborts the install.

## `shutdown` and `reporting`

```yaml
autoinstall:
  shutdown: reboot           # reboot (default) | poweroff
  reporting:
    builtin:
      type: print            # print | rsyslog | webhook | none
    hook:
      type: webhook
      endpoint: https://hooks.internal/ubuntu-install
      consumer_secret: xyz
```

`reporting.print` dumps progress to `tty1` and any configured serial
console. `webhook` POSTs JSON progress reports to a URL (same format
as curtin's webhook reporter). If any `interactive-sections` is set,
`reporting` is ignored.

## Delivering the autoinstall config

Four common delivery methods:

### 1. NoCloud over HTTP (PXE / netboot)

Serve `user-data` and `meta-data` on an HTTP server and pass the URL
to the kernel via `autoinstall ds=nocloud-net;s=http://my-server/`:

```text
# PXELINUX append line
append initrd=initrd vga=788 --- quiet autoinstall \
  ds=nocloud-net;s=http://10.0.0.5/install/web01/
```

The trailing slash is mandatory. The server serves:

```text
http://10.0.0.5/install/web01/user-data
http://10.0.0.5/install/web01/meta-data   # can be empty
```

### 2. NoCloud on a second volume (USB stick, attached ISO)

Create a tiny ISO labelled `cidata` containing the two files, then
attach it as a second drive:

```bash
# On a build host (not on the target):
mkdir cidata
cp user-data meta-data cidata/
xorriso -as mkisofs -o seed.iso -V cidata -J -r cidata/
# Attach seed.iso to the VM as a second CD-ROM.
```

The Ubuntu Server Guide shows this workflow under "Using another
volume to provide the autoinstall config".

### 3. Baked into a custom ISO

Remaster the live-server ISO to embed `user-data` in
`/nocloud/user-data` and append `autoinstall ds=nocloud;s=/cdrom/nocloud/`
to the grub entry. Tools: `livefs-editor`, `cloud-localds`,
`xorriso`.

### 4. Kernel command line

The `autoinstall` keyword on the kernel command line is what tells
subiquity to proceed without the "are you sure" confirmation. Without
it, even a valid autoinstall config pauses for human confirmation
before touching disks — a deliberate safety so a stray USB stick can't
wipe a machine it was plugged into.

## Debugging a failing autoinstall

- **Schema validation first.** Run `cloud-init schema --config-file
  user-data` on a machine with cloud-init installed. The installer
  validates the same schema at boot; catch errors offline.
- **Console output.** With `reporting.builtin.type: print`, every
  stage logs to tty1 and to the serial console if one is configured
  (add `console=ttyS0,115200` to the kernel command line for VMs).
- **`/var/log/installer/`** in the live session holds the gold. Key
  files:
  - `autoinstall-user-data` — the effective config after early-commands.
  - `subiquity-server.log` — the installer's own log.
  - `curtin-install.log` — curtin, which does the actual disk work.
  - `syslog` — full systemd/cloud-init journal of the installer.
- **error-commands** are your safety net. At minimum, tar
  `/var/log/installer/` and upload it somewhere you can read it after
  the box halts.
- **Drop to a shell.** On failure the installer displays a menu with
  a "Help → Enter shell" option. From there you can inspect
  `/target/` (the mounted installed system) and `/var/log/installer/`.
- **Rerun the install.** The installer writes a reusable copy of the
  effective config to `/var/log/installer/autoinstall-user-data` on
  the installed system. Copy it out, tweak, and feed it back into the
  next attempt.

## Three worked examples

### Example 1 — Minimal web server

```yaml
#cloud-config
# Minimal, unattended web server install.
# Delivered via NoCloud (HTTP or cidata ISO).
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us

  identity:
    realname: Peter Bamuhigire
    username: peter
    hostname: web01
    password: "$6$rounds=4096$sGR0jNvN$ZHbu1w3YcnH/uOyhuH3fbshB9oQslEknQv1JiWq6ZAl2eDqvBZhz3PGTwlwOyLhMLh9nJTF.M9u1Y6xFk1yhh/"

  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

  network:
    version: 2
    ethernets:
      enp1s0:
        dhcp4: true

  storage:
    layout:
      name: lvm

  apt:
    geoip: true
    preserve_sources_list: false

  packages:
    - nginx
    - ufw
    - fail2ban

  # Second-stage cloud-init that runs on first boot of the installed system
  user-data:
    timezone: Africa/Kampala
    runcmd:
      - [systemctl, enable, --now, nginx]
      - [ufw, allow, OpenSSH]
      - [ufw, allow, 'Nginx Full']
      - [ufw, --force, enable]

  shutdown: reboot
```

### Example 2 — LVM with encrypted root

```yaml
#cloud-config
# Single-disk install with an encrypted LUKS root on top of LVM.
# Root partition is 50 GiB; the rest of the disk is left for future LVs.
autoinstall:
  version: 1
  locale: en_US.UTF-8

  identity:
    realname: Peter Bamuhigire
    username: peter
    hostname: secure01
    password: "$6$rounds=4096$sGR0jNvN$ZHbu1w3YcnH/uOyhuH3fbshB9oQslEknQv1JiWq6ZAl2eDqvBZhz3PGTwlwOyLhMLh9nJTF.M9u1Y6xFk1yhh/"

  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

  storage:
    swap: { size: 0 }
    config:
      # Single disk, GPT, bootable
      - { type: disk, id: disk0, ptable: gpt, match: { size: largest }, wipe: superblock, grub_device: true }
      # 512 MiB EFI system partition
      - { type: partition, id: p-efi, device: disk0, size: 512M, flag: boot, grub_device: true }
      - { type: format, id: f-efi, volume: p-efi, fstype: fat32 }
      - { type: mount, id: m-efi, device: f-efi, path: /boot/efi }
      # Unencrypted /boot so GRUB can read the kernel
      - { type: partition, id: p-boot, device: disk0, size: 1G }
      - { type: format, id: f-boot, volume: p-boot, fstype: ext4 }
      - { type: mount, id: m-boot, device: f-boot, path: /boot }
      # The rest of the disk becomes a LUKS container
      - { type: partition, id: p-crypt, device: disk0, size: -1 }
      - { type: dm_crypt, id: dm-root, volume: p-crypt, key: "CHANGE-ME-ON-FIRST-BOOT" }
      # LVM on top of the opened LUKS device
      - { type: lvm_volgroup, id: vg0, name: vg0, devices: [dm-root] }
      - { type: lvm_partition, id: lv-root, volgroup: vg0, name: root, size: 50G }
      - { type: format, id: f-root, volume: lv-root, fstype: ext4 }
      - { type: mount, id: m-root, device: f-root, path: / }

  packages:
    - cryptsetup
    - lvm2

  late-commands:
    # Nag the operator to rotate the LUKS passphrase set in this file.
    - |
      echo "WARNING: change the LUKS passphrase with cryptsetup luksChangeKey" \
        > /target/root/ROTATE_LUKS_PASSPHRASE.txt

  shutdown: reboot
```

### Example 3 — ZFS root with two disks

```yaml
#cloud-config
# Two-disk ZFS root. Uses the built-in zfs layout, which creates an rpool
# across both disks with mirroring.
autoinstall:
  version: 1
  locale: en_US.UTF-8

  identity:
    realname: Peter Bamuhigire
    username: peter
    hostname: zfs01
    password: "$6$rounds=4096$sGR0jNvN$ZHbu1w3YcnH/uOyhuH3fbshB9oQslEknQv1JiWq6ZAl2eDqvBZhz3PGTwlwOyLhMLh9nJTF.M9u1Y6xFk1yhh/"

  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

  network:
    version: 2
    ethernets:
      enp1s0: { dhcp4: true }

  storage:
    layout:
      name: zfs
      # zfs layout creates bpool (ext4-style boot) and rpool (zfs root)
      # across every eligible disk; no per-disk match needed for a pair.

  apt:
    geoip: true

  packages:
    - zfsutils-linux
    - zfs-zed

  user-data:
    runcmd:
      # Prove the pool came up
      - [zpool, status]
      - [zfs, list]
      - [systemctl, enable, --now, zfs-zed]

  late-commands:
    - curtin in-target -- update-initramfs -u -k all

  shutdown: reboot
```

## Sources

- Canonical, *Ubuntu Server Guide Documentation — Linux 20.04 LTS
  (Focal)*, 2020. The "Automated Server Installs", "Autoinstall Quick
  Start", "JSON Schema for autoinstall config", and "Automated Server
  Installs Config File Reference" chapters are the primary source for
  every schema field and delivery method in this document, including
  the `version`, `interactive-sections`, `identity`, `ssh`, `storage`,
  `network`, `apt`, `packages`, `late-commands`, `error-commands`,
  `reporting`, and `user-data` keys.
- Canonical, *Ubuntu Server Guide* — "Netbooting the server installer
  on amd64" chapter, for the PXE/dnsmasq delivery workflow.
- `linux-cloud-init/SKILL.md` — standing rules (validate before
  deploy; never put secrets in plaintext user-data; autoinstall uses
  a different schema than runtime user-data).
