# cloud-init user-data reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

cloud-init is the industry-standard multi-distribution mechanism for
cross-platform cloud instance initialisation. It runs on first boot of a
cloud image, reads a YAML **user-data** document from the cloud's metadata
service, and turns the blank image into a configured server. On Ubuntu
cloud images it is pre-installed and active by default. This reference
covers the `#cloud-config` YAML format — the modules, their schema, the
lifecycle they run in, and the pitfalls that silently break a first-boot.

## Table of contents

- [The `#cloud-config` header](#the-cloud-config-header)
- [Lifecycle and module ordering](#lifecycle-and-module-ordering)
- [Datasource detection](#datasource-detection)
- [Idempotency and re-running](#idempotency-and-re-running)
- [Core modules](#core-modules)
  - [Hostname and hosts file](#hostname-and-hosts-file)
  - [`users` — user accounts and SSH keys](#users--user-accounts-and-ssh-keys)
  - [`ssh_pwauth`, `disable_root`, `chpasswd`](#ssh_pwauth-disable_root-chpasswd)
  - [`packages`, `package_update`, `package_upgrade`](#packages-package_update-package_upgrade)
  - [`apt` — sources, PPAs, keys, proxy](#apt--sources-ppas-keys-proxy)
  - [`write_files`](#write_files)
  - [`runcmd` and `bootcmd`](#runcmd-and-bootcmd)
  - [`timezone`, `locale`, `ntp`](#timezone-locale-ntp)
  - [`swap` and `mounts`](#swap-and-mounts)
  - [`power_state` and `final_message`](#power_state-and-final_message)
- [Common pitfalls](#common-pitfalls)
- [Five worked examples](#five-worked-examples)
- [Sources](#sources)

## The `#cloud-config` header

Every user-data file MUST begin with the literal line `#cloud-config` on
line 1 — no leading whitespace, no BOM, no blank line before it. This is
not a comment. cloud-init treats it as a magic marker that selects the
YAML config handler. Omit it and cloud-init treats the file as a shell
script or silently ignores it.

```yaml
#cloud-config
# All cloud-init user-data files must start with the line above.
hostname: web01
```

To inspect what cloud-init parsed, run `cloud-init query userdata` on the
booted instance. A file that fails the magic check will show up as
`type: text/x-not-multipart` and nothing will run.

## Lifecycle and module ordering

cloud-init runs in four systemd stages. Each stage runs a fixed module
set configured in `/etc/cloud/cloud.cfg`. Understanding the stages is
essential when runcmd doesn't see a package you expected earlier:

| Stage | systemd unit | Purpose | Runs modules like |
|---|---|---|---|
| `init-local` | `cloud-init-local.service` | Before networking | `seed_random`, `bootcmd`, network config |
| `init` | `cloud-init.service` | After networking | `write_files`, `set_hostname`, `update_hostname`, `users_groups`, `ssh` |
| `config` | `cloud-config.service` | Main config | `apt_configure`, `package_update_upgrade_install`, `timezone`, `ntp`, `locale`, `mounts`, `ssh_authkey_fingerprints` |
| `final` | `cloud-final.service` | Last — user scripts | `runcmd`, `scripts_user`, `power_state_change`, `final_message` |

Key consequences:

- `runcmd` runs in the **final** stage — after packages are installed,
  users exist, and `write_files` has already dropped files into place.
  Use it to glue everything together.
- `bootcmd` runs in **init-local**, on **every** boot, before the
  network is up. Use it only for low-level tasks like setting up a
  virtual console or a partition that must exist before networking.
- `write_files` happens before `runcmd`, so a runcmd script is free to
  execute a file written by `write_files`.
- `packages` runs in `config` stage, before `runcmd`. You may rely on
  any installed binary in runcmd.

## Datasource detection

cloud-init discovers user-data from a **datasource**. On first boot it
probes a list until one responds. Common datasources:

- **NoCloud** — a vfat or iso9660 volume labelled `cidata` containing
  `user-data` and `meta-data` files. Used for bare-metal, libvirt,
  VMware, and autoinstall.
- **EC2** — AWS metadata service at `http://169.254.169.254/`.
- **ConfigDrive** — OpenStack-style config drive ISO.
- **LXD** — LXD provides user-data via the container's metadata socket.
- **Azure**, **GCE**, **DigitalOcean**, **Hetzner** — each has its own
  metadata endpoint; cloud-init auto-detects them.

To force a specific datasource, edit `/etc/cloud/cloud.cfg.d/90_dpkg.cfg`
and set `datasource_list: [ NoCloud, None ]`. Check the detected
datasource on a booted instance with `cloud-init query ds`.

## Idempotency and re-running

cloud-init runs user-data **once per instance id**. On subsequent boots
it no-ops unless the instance id changed (e.g. a new AMI). To re-run
during testing, clean the state and reboot:

```bash
sudo cloud-init clean --logs --seed
sudo reboot
```

`clean` removes `/var/lib/cloud/` and forces cloud-init to re-seed on
next boot. `--logs` also wipes `/var/log/cloud-init.log` so you get a
fresh trace. Never run `clean` on a production system unless you have
the user-data and are prepared for it to re-run.

## Core modules

### Hostname and hosts file

```yaml
#cloud-config
hostname: web01
fqdn: web01.example.com
manage_etc_hosts: true
preserve_hostname: false
```

- `hostname` — short name. Written to `/etc/hostname`.
- `fqdn` — fully qualified name. Used in `/etc/hosts`.
- `manage_etc_hosts: true` — cloud-init rewrites `/etc/hosts` on every
  boot so `127.0.1.1 fqdn hostname` is always correct. Without this,
  `sudo` complains about unresolvable host.
- `preserve_hostname: false` — let cloud-init overwrite the hostname
  even if it was set manually. Set to `true` on snapshots.

### `users` — user accounts and SSH keys

This is the most important module for server provisioning. It creates
users, installs SSH keys, and grants sudo:

```yaml
#cloud-config
users:
  - default                       # keep the distro default user (ubuntu)
  - name: peter                   # create a new admin
    gecos: Peter Bamuhigire       # real name in /etc/passwd
    groups: [sudo, adm, docker]   # supplementary groups
    shell: /bin/bash              # login shell
    sudo: ALL=(ALL) NOPASSWD:ALL  # passwordless sudo
    lock_passwd: true             # no password login; key only
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3Nz... peter@laptop
      - ssh-rsa AAAAB3Nz... peter@backup
  - name: deploy
    system: true                  # system account (UID < 1000)
    shell: /usr/sbin/nologin      # can't log in interactively
    homedir: /srv/deploy
```

Key fields:

- `- default` — a literal string, not a dict. Keeps the cloud image's
  default user (`ubuntu` on Ubuntu images). Drop it to remove that user.
- `lock_passwd: true` — recommended. Disables password login entirely
  so the account is key-only.
- `sudo` — passed verbatim to `/etc/sudoers.d/90-cloud-init-users`. Use
  `ALL=(ALL) NOPASSWD:ALL` for fully unattended admin, or
  `ALL=(ALL) ALL` to require the user's password.
- `ssh_authorized_keys` — list of public keys written to
  `~/.ssh/authorized_keys` with mode 600.
- `passwd` — crypted password (from `mkpasswd --method=SHA-512`). Only
  use when `lock_passwd: false`.

### `ssh_pwauth`, `disable_root`, `chpasswd`

```yaml
#cloud-config
ssh_pwauth: false          # disable password auth in sshd_config
disable_root: true         # comment out root's authorized_keys
chpasswd:
  expire: false            # do NOT force password change on first login
  list: |                  # only if you really must set plain passwords
    peter:TemporaryP@ss1
```

- `ssh_pwauth: false` — sets `PasswordAuthentication no` in
  `/etc/ssh/sshd_config.d/50-cloud-init.conf`. Always set this for
  internet-facing servers.
- `disable_root: true` — the default. Prevents SSH login as root.
- `chpasswd.expire: false` — without this, every user cloud-init sets
  a password for is marked expired and must change it on first login.

### `packages`, `package_update`, `package_upgrade`

```yaml
#cloud-config
package_update: true       # apt update before installing
package_upgrade: true      # apt upgrade all packages
package_reboot_if_required: true
packages:
  - nginx
  - ufw
  - fail2ban
  - git
  - curl
  - [libpython3-dev, 3.10.*]  # pin version with a two-element list
```

- `package_update: true` runs `apt-get update` once, in the `config`
  stage.
- `package_upgrade: true` runs `apt-get upgrade -y`. Slow on first boot
  but essential for security.
- `package_reboot_if_required: true` — if upgrade installs a new kernel,
  cloud-init reboots the VM automatically after the final stage.

### `apt` — sources, PPAs, keys, proxy

```yaml
#cloud-config
apt:
  preserve_sources_list: false   # let cloud-init overwrite sources.list
  primary:
    - arches: [default]
      uri: http://archive.ubuntu.com/ubuntu
  security:
    - arches: [default]
      uri: http://security.ubuntu.com/ubuntu
  proxy: http://apt-cache.internal:3142
  sources:
    docker.list:
      source: "deb [signed-by=$KEY_FILE] https://download.docker.com/linux/ubuntu $RELEASE stable"
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88
    nodejs.list:
      source: "deb https://deb.nodesource.com/node_20.x $RELEASE main"
      key: |
        -----BEGIN PGP PUBLIC KEY BLOCK-----
        mQINBFdDN1...
        -----END PGP PUBLIC KEY BLOCK-----
```

PPAs use the `source: ppa:...` shortcut:

```yaml
apt:
  sources:
    certbot-ppa:
      source: "ppa:certbot/certbot"
```

### `write_files`

Drops arbitrary files into the filesystem before `runcmd` runs:

```yaml
#cloud-config
write_files:
  - path: /etc/nginx/sites-available/default
    owner: root:root
    permissions: '0644'
    content: |
      server {
        listen 80 default_server;
        server_name _;
        root /var/www/html;
      }
  - path: /etc/environment
    append: true               # append instead of overwrite
    content: |
      NODE_ENV=production
  - path: /root/.aws/config
    owner: root:root
    permissions: '0600'
    encoding: b64              # content is base64
    content: W2RlZmF1bHRdCnJlZ2lvbiA9IHVzLWVhc3QtMQo=
  - path: /usr/local/bin/healthcheck
    owner: root:root
    permissions: '0755'
    content: |
      #!/bin/bash
      curl -fsS http://localhost/health || exit 1
```

Fields:

- `permissions` — **must** be a quoted string like `'0644'`. Unquoted
  `0644` is parsed by YAML as decimal 644.
- `encoding` — `text` (default), `b64`, `gzip`, `gz+b64`. Use `b64` for
  binary files or secrets that should not be readable in plaintext in
  the user-data document on-disk (note: this is obfuscation, not
  encryption — the user-data is cached in `/var/lib/cloud/`).
- `append: true` — append to an existing file instead of overwriting.
- `defer: true` — defer the write to the `final` stage so it runs after
  packages and users (rare; only needed when the target path is created
  by a package).

### `runcmd` and `bootcmd`

```yaml
#cloud-config
runcmd:
  - [systemctl, enable, --now, nginx]
  - [ufw, allow, OpenSSH]
  - [ufw, allow, 'Nginx Full']
  - [ufw, --force, enable]
  - /usr/local/bin/bootstrap-skills.sh
  - |
    set -euxo pipefail
    cd /root
    git clone https://github.com/petebwire/linux-skills.git .claude/skills
```

Rules:

- Each list item is one command. A **list** (`[cmd, arg1, arg2]`) runs
  exec-style without a shell. A **string** runs under `sh -c`.
- **Always use absolute paths**. cloud-init's PATH is minimal and
  `which` does not always resolve. A bare `nginx -t` may fail where
  `/usr/sbin/nginx -t` succeeds.
- Exit codes are logged to `/var/log/cloud-init-output.log`. A non-zero
  exit does **not** abort cloud-init — later commands still run. Use
  `set -e` in heredoc blocks if you need fail-fast behaviour.
- Output (stdout + stderr) is captured in
  `/var/log/cloud-init-output.log`. For structured debug, pipe into
  `logger -t my-bootstrap`.

`bootcmd` has the same syntax but runs **every boot**, in the
`init-local` stage, before the network is up. Use it sparingly — for
example to create a device node or tweak kernel parameters that must
be set before any service starts.

### `timezone`, `locale`, `ntp`

```yaml
#cloud-config
timezone: Africa/Kampala
locale: en_US.UTF-8
ntp:
  enabled: true
  ntp_client: systemd-timesyncd
  servers:
    - 0.ubuntu.pool.ntp.org
    - 1.ubuntu.pool.ntp.org
    - time.google.com
```

### `swap` and `mounts`

```yaml
#cloud-config
swap:
  filename: /swap.img
  size: "2147483648"           # 2 GiB, quoted string
  maxsize: 4294967296
mounts:
  - [/dev/disk/by-id/scsi-0DO_Volume_data, /mnt/data, ext4, "defaults,nofail,discard", "0", "2"]
  - [tmpfs, /tmp, tmpfs, "defaults,noatime,size=1G", "0", "0"]
```

`mounts` entries are six-element lists matching `/etc/fstab` columns:
device, mountpoint, fstype, options, dump, pass. Always use
`by-id`/`by-uuid` paths for attached volumes — raw `/dev/sdb` may be
reassigned on reboot.

### `power_state` and `final_message`

```yaml
#cloud-config
final_message: "cloud-init finished after $UPTIME seconds"
power_state:
  mode: reboot                 # reboot | poweroff | halt
  delay: now                   # "now" or "+5"
  message: "Rebooting after first-boot provisioning"
  timeout: 30
  condition: true              # or a shell command; only reboot if it returns 0
```

Use `power_state: reboot` when the user-data installs a new kernel,
changes `/etc/default/grub`, or adds a user to the `docker` group —
anything where the session needs to restart cleanly.

## Common pitfalls

1. **Missing `#cloud-config` header.** cloud-init silently treats the
   file as a shell script and ignores every module. Always validate
   with `cloud-init schema --config-file user-data.yaml`.
2. **Tabs in YAML.** YAML forbids tabs for indentation. Use spaces.
3. **Unquoted octal permissions.** `permissions: 0644` is decimal 644 —
   resulting file is mode 01204. Always quote: `'0644'`.
4. **Non-absolute paths in runcmd.** `nginx -t` may work interactively
   but fail in cloud-init's minimal PATH.
5. **Secrets in plaintext.** user-data is cached in
   `/var/lib/cloud/instance/user-data.txt` and readable by root. Use
   Vault, SSM, or a post-boot pull instead.
6. **Running the upgrade without `package_reboot_if_required`.** A new
   kernel lands but the old one keeps running — services end up
   inconsistent.
7. **Relying on runcmd order across modules.** `runcmd` runs last, so
   you cannot put a runcmd before `packages`. If you need ordering
   within the package stage, use `apt` custom hooks or a systemd unit.
8. **Assuming runcmd re-runs on reboot.** It does not — cloud-init runs
   once per instance. Use `bootcmd` for per-boot tasks.

## Five worked examples

### Example 1 — Minimal web server (nginx + admin user + SSH key)

```yaml
#cloud-config
# Brings up a basic nginx host with one admin user and a locked-down firewall.

hostname: web01
fqdn: web01.example.com
manage_etc_hosts: true
timezone: Africa/Kampala

users:
  - default
  - name: peter
    gecos: Peter Bamuhigire
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

ssh_pwauth: false
disable_root: true

package_update: true
package_upgrade: true
packages:
  - nginx
  - ufw
  - fail2ban

write_files:
  - path: /var/www/html/index.html
    owner: www-data:www-data
    permissions: '0644'
    content: |
      <h1>web01</h1><p>provisioned by cloud-init</p>

runcmd:
  - [systemctl, enable, --now, nginx]
  - [ufw, allow, OpenSSH]
  - [ufw, allow, 'Nginx Full']
  - [ufw, --force, enable]
  - [systemctl, enable, --now, fail2ban]

final_message: "web01 ready after $UPTIME s"
```

### Example 2 — Full linux-skills bootstrap

```yaml
#cloud-config
# Standard bootstrap for every server: admin user, firewall, linux-skills repo.
# This is the template referenced by the linux-server-provisioning skill.

hostname: srv01
manage_etc_hosts: true
timezone: Africa/Kampala

users:
  - default
  - name: peter
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

ssh_pwauth: false
disable_root: true

package_update: true
package_upgrade: true
package_reboot_if_required: true
packages:
  - git
  - curl
  - ufw
  - fail2ban
  - htop
  - unattended-upgrades

write_files:
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    owner: root:root
    permissions: '0644'
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";

runcmd:
  # Firewall first so nothing is exposed while packages install
  - [ufw, allow, OpenSSH]
  - [ufw, --force, enable]
  # Clone the linux-skills knowledge base into the admin's ~/.claude/skills
  - [install, -d, -o, peter, -g, peter, /home/peter/.claude]
  - |
    sudo -u peter git clone https://github.com/petebwire/linux-skills.git \
      /home/peter/.claude/skills
  # Install the core sk-* scripts so sk-provision-fresh etc. are on PATH
  - /home/peter/.claude/skills/scripts/install-skills-bin core
  - [systemctl, enable, --now, fail2ban]

final_message: "Server bootstrap complete. Run sk-provision-fresh next."
```

### Example 3 — Docker host

```yaml
#cloud-config
# Installs Docker Engine from the official repo, adds admin user to docker group,
# enables the service, and reboots so the group membership takes effect.

hostname: docker01
manage_etc_hosts: true

users:
  - default
  - name: peter
    groups: [sudo, docker]
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

ssh_pwauth: false

apt:
  sources:
    docker.list:
      source: "deb [arch=amd64 signed-by=$KEY_FILE] https://download.docker.com/linux/ubuntu $RELEASE stable"
      keyid: 9DC858229FC7DD38854AE2D88D81803C0EBFCD88

package_update: true
packages:
  - docker-ce
  - docker-ce-cli
  - containerd.io
  - docker-compose-plugin
  - ufw

write_files:
  - path: /etc/docker/daemon.json
    owner: root:root
    permissions: '0644'
    content: |
      {
        "log-driver": "json-file",
        "log-opts": { "max-size": "10m", "max-file": "3" },
        "live-restore": true
      }

runcmd:
  - [systemctl, enable, --now, docker]
  - [ufw, allow, OpenSSH]
  - [ufw, --force, enable]
  - [docker, info]

power_state:
  mode: reboot
  delay: now
  message: "Rebooting so peter's docker group membership applies"
```

### Example 4 — LXD container bring-up with managed SSH

```yaml
#cloud-config
# Passed via `lxc launch ubuntu:22.04 c1 --config=user.user-data=-`.
# LXD datasource injects this at boot; no network metadata required.

hostname: c1
manage_etc_hosts: true

users:
  - default
  - name: peter
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

ssh_pwauth: false

package_update: true
packages:
  - openssh-server
  - curl

runcmd:
  # LXD containers have no UFW by default — keep it simple
  - [systemctl, enable, --now, ssh]
  # Print the container's IP so the host can grab it from the LXD console log
  - |
    ip -4 addr show eth0 | awk '/inet /{print "container-ip:",$2}' \
      | systemd-cat -t cloud-init

final_message: "LXD container $HOSTNAME reachable over SSH"
```

### Example 5 — Database server with external volume

```yaml
#cloud-config
# PostgreSQL host with data on a separately attached block device.
# The volume is referenced by its stable by-id path, never /dev/sdb.

hostname: db01
manage_etc_hosts: true
timezone: Africa/Kampala

users:
  - default
  - name: peter
    groups: [sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... peter@laptop

ssh_pwauth: false

package_update: true
package_upgrade: true
packages:
  - postgresql-15
  - ufw
  - xfsprogs

# The data volume must exist before the mount entry is applied.
# bootcmd runs at init-local, before mounts are processed.
bootcmd:
  - |
    DEV=/dev/disk/by-id/scsi-0DO_Volume_db01data
    if ! blkid "$DEV"; then
      mkfs.xfs -L pgdata "$DEV"
    fi

mounts:
  - [LABEL=pgdata, /var/lib/postgresql, xfs, "defaults,noatime,nofail", "0", "2"]

write_files:
  - path: /etc/postgresql/15/main/conf.d/99-listen.conf
    owner: postgres:postgres
    permissions: '0644'
    content: |
      listen_addresses = '*'
      max_connections = 200
      shared_buffers = 512MB
  - path: /etc/postgresql/15/main/pg_hba.conf
    owner: postgres:postgres
    permissions: '0640'
    append: true
    content: |
      host all all 10.0.0.0/8 scram-sha-256

runcmd:
  # Stop postgres so the data dir can be moved onto the mounted volume
  - [systemctl, stop, postgresql]
  - [rsync, -a, /var/lib/postgresql.dist/, /var/lib/postgresql/]
  - [chown, -R, 'postgres:postgres', /var/lib/postgresql]
  - [systemctl, enable, --now, postgresql]
  - [ufw, allow, OpenSSH]
  - [ufw, allow, 'from 10.0.0.0/8 to any port 5432 proto tcp']
  - [ufw, --force, enable]

final_message: "db01 online; postgres listening on 5432"
```

## Sources

- Canonical, *Ubuntu Server Guide Documentation — Linux 20.04 LTS
  (Focal)*, 2020. "Automated Server Installs" and "Virtualization"
  chapters, which document the cloud-init integration for autoinstall
  and for uvt-kvm/LXD first-boot provisioning.
- cloud-init upstream documentation (referenced by the Ubuntu guide
  via `https://cloudinit.readthedocs.io/`) for module schemas.
- `linux-cloud-init/SKILL.md` — standing rules for this skill.
