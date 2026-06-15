# Kickstart reference (RHEL-family automated install)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

**Ubuntu autoinstall is Ubuntu-specific.** The RHEL family (Fedora, RHEL,
CentOS Stream, Rocky, Alma, Oracle) automates bare-metal / ISO installs with
**Kickstart**, processed by the **Anaconda** installer. This is the RHEL-family
counterpart to [`autoinstall-reference.md`](autoinstall-reference.md).

Two distinct concepts that are easy to conflate:

- **OS-install automation** — answers the installer's questions (disks, users,
  packages). This is **autoinstall on Ubuntu, Kickstart on RHEL** — *not*
  portable.
- **First-boot configuration** — **cloud-init** (`user-data` / cloud-config).
  This **is** portable: the same cloud-config runs on Ubuntu and Fedora/RHEL
  cloud images. See [`user-data-reference.md`](user-data-reference.md).

| Layer | Debian/Ubuntu | RHEL family |
|---|---|---|
| ISO/bare-metal install automation | autoinstall (subiquity) | **Kickstart** (Anaconda) |
| Autoinstall config format | cloud-init `#cloud-config` autoinstall schema | Kickstart `.ks` directives |
| Install config location | `autoinstall:` in user-data / `nocloud` | `inst.ks=<url\|path>` boot arg |
| First-boot config | cloud-init `user-data` | cloud-init `user-data` (same) |
| Default cloud user | `ubuntu` | `fedora` / `cloud-user` / `ec2-user` (image-dependent) |

---

## Minimal Kickstart file (`ks.cfg`)

```kickstart
# Non-interactive text install
text
lang en_US.UTF-8
keyboard us
timezone UTC --utc

# Network: DHCP on first NIC, set hostname
network --bootproto=dhcp --device=link --activate
network --hostname=web01.example.com

# Disk: wipe and use automatic LVM partitioning
ignoredisk --only-use=sda
clearpart --all --initlabel
autopart --type=lvm

# Bootloader
bootloader --location=mbr

# Root + an admin user (wheel = sudo)
rootpw --iscrypted $6$REPLACE_WITH_HASH
user --name=peter --groups=wheel --iscrypted --password=$6$REPLACE_WITH_HASH

# SELinux + firewall (RHEL defaults — keep them on)
selinux --enforcing
firewall --enabled --service=ssh

services --enabled=sshd,chronyd

# Reboot when done
reboot

%packages
@^minimal-environment
openssh-server
chrony
vim-enhanced
%end

%post --log=/root/ks-post.log
# Runs in the installed system's context after install
dnf -y install epel-release || true
systemctl enable --now sshd
%end
```

Generate a password hash with: `python3 -c 'import crypt;print(crypt.crypt("PW",crypt.mksalt(crypt.METHOD_SHA512)))'`.

---

## autoinstall → Kickstart concept map

| Concept | Ubuntu autoinstall | Kickstart |
|---|---|---|
| Locale/keyboard | `locale:` / `keyboard:` | `lang` / `keyboard` |
| Network | `network:` (netplan v2) | `network --bootproto=…` |
| Storage | `storage:` (curtin) | `clearpart` + `autopart` / `part` |
| Users | `identity:` / `users:` | `rootpw`, `user --groups=wheel` |
| Packages | `packages:` | `%packages … %end` |
| Run commands | `late-commands:` | `%post … %end` |
| Pre-install hooks | `early-commands:` | `%pre … %end` |
| Admin group | `sudo` | `wheel` |
| MAC default | AppArmor | **`selinux --enforcing`** |
| Firewall | (set up post-install) | `firewall --enabled` (firewalld) |

---

## Serving a Kickstart

```bash
# Boot the installer with the kickstart URL (GRUB/PXE kernel args):
inst.ks=https://provision.example.com/ks/web01.cfg
# or from the ISO / local media:
inst.ks=cdrom:/ks.cfg
inst.ks=hd:LABEL=MYUSB:/ks.cfg

# Validate a kickstart before using it:
sudo dnf install -y pykickstart
ksvalidator ks.cfg
```

---

## cloud-init on RHEL (the portable layer)

cloud-init ships in Fedora/RHEL cloud images and consumes the **same**
`#cloud-config` user-data as Ubuntu. A few distro-aware notes:

```yaml
#cloud-config
# package_update/upgrade use the detected package manager (dnf on RHEL)
package_update: true
packages:
  - chrony        # NOT 'systemd-timesyncd' — chrony is the RHEL default
  - firewalld
users:
  - name: peter
    groups: [wheel]            # 'wheel', not 'sudo', on RHEL
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... peter@laptop
runcmd:
  - [ systemctl, enable, --now, firewalld ]
  - [ firewall-cmd, --permanent, --add-service=https ]
  - [ firewall-cmd, --reload ]
```

Differences from Ubuntu cloud-config:

- **Admin group** is `wheel`, not `sudo`.
- **Package names** differ (e.g. `chrony` vs `systemd-timesyncd`; `httpd` vs
  `apache2`) — see [`../../../01-provisioning-and-bootstrap/linux-package-management/SKILL.md`](../../../01-provisioning-and-bootstrap/linux-package-management/SKILL.md).
- **Network rendering**: cloud-init renders `network:` config to
  NetworkManager on RHEL and to Netplan on Ubuntu — write distro-neutral
  network-config v2 and let cloud-init render it.
- SELinux is enforcing — `runcmd` that writes into service paths may need
  `restorecon` (see
  [`../../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md)).

---

## Debugging (portable)

```bash
cloud-init status --long
sudo cloud-init schema --system          # validate the applied user-data
sudo journalctl -u cloud-init -b
sudo cat /var/log/cloud-init-output.log

# Kickstart install logs (in the installed system)
cat /root/anaconda-ks.cfg                 # the kickstart Anaconda actually used
cat /root/ks-post.log                     # your %post --log output
```

See [`debugging.md`](debugging.md) for the full cloud-init debugging tree.

---

## References

- [`autoinstall-reference.md`](autoinstall-reference.md) — the Ubuntu counterpart.
- [`user-data-reference.md`](user-data-reference.md) — cloud-config (portable).
- [`debugging.md`](debugging.md) — cloud-init debugging (portable).
- Docs: `pykickstart` / `ksvalidator(1)`, Fedora "Automating the installation
  with Kickstart", Anaconda Kickstart reference.
