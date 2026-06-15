# Users, Sudoers, and PAM Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Deep reference for user and group management, password aging, the
sudoers grammar, PAM stack fundamentals, account locking, and SSH key
discipline on Ubuntu/Debian. Every command assumes you are on stock
Ubuntu 22.04 or 24.04 and root (via `sudo`). Read this alongside
`permissions-reference.md` — the two files cover the two halves of
"who can do what" on the box.

## Table of contents

- [/etc/passwd, /etc/shadow, /etc/group, /etc/gshadow](#etcpasswd-etcshadow-etcgroup-etcgshadow)
- [useradd, usermod, userdel in depth](#useradd-usermod-userdel-in-depth)
- [Password aging with chage](#password-aging-with-chage)
- [Groups: adding, removing, listing](#groups-adding-removing-listing)
- [The sudoers file](#the-sudoers-file)
- [PAM stack basics](#pam-stack-basics)
- [Locking, expiring, and disabling accounts](#locking-expiring-and-disabling-accounts)
- [SSH key management discipline](#ssh-key-management-discipline)
- [Auditing: who has access, when did they last log in](#auditing-who-has-access-when-did-they-last-log-in)
- [Sources](#sources)

## /etc/passwd, /etc/shadow, /etc/group, /etc/gshadow

These four files are the source of truth for local authentication.
Edit them only via `useradd`, `usermod`, `chage`, `passwd`, and
`visudo` — never by hand. Everything below is what those tools are
modifying under the covers.

### /etc/passwd

One line per user. Seven colon-separated fields:

```
deploy:x:1001:1001:Deploy user,,,:/home/deploy:/bin/bash
  1    2  3    4        5           6          7
```

| # | Field                    | Notes                                         |
|---|--------------------------|-----------------------------------------------|
| 1 | Username                 | Unique, up to 32 chars                        |
| 2 | Password placeholder     | `x` = stored in `/etc/shadow`                 |
| 3 | UID                      | 0 = root; <1000 = system; ≥1000 = interactive |
| 4 | Primary GID              | Matches a group in `/etc/group`               |
| 5 | GECOS (comment)          | Full name, office, phone — free text          |
| 6 | Home directory           | `/home/<user>` or `/root`                     |
| 7 | Login shell              | `/bin/bash`, `/usr/sbin/nologin`, `/bin/false`|

Anything with shell `/usr/sbin/nologin` or `/bin/false` cannot log in
interactively — this is the right shell for service accounts.

### /etc/shadow

One line per user. Nine colon-separated fields:

```
deploy:$y$j9T$wP7...$xK:19700:7:90:14::::
  1      2             3    4  5  6 7 8 9
```

| # | Field                              | Meaning                                         |
|---|-----------------------------------|-------------------------------------------------|
| 1 | Username                          | Must match passwd                               |
| 2 | Password hash                     | `$y$` = yescrypt, `$6$` = sha512, `!`/`!!` = locked, empty = no password |
| 3 | Last password change              | Days since 1970-01-01                            |
| 4 | Minimum days between changes      | `PASS_MIN_DAYS`                                  |
| 5 | Maximum days password valid       | `PASS_MAX_DAYS`                                  |
| 6 | Days before expiry to warn        | `PASS_WARN_AGE`                                  |
| 7 | Days after expiry account disabled| Inactivity grace                                 |
| 8 | Account expiration date           | Days since epoch; `0` = expired now              |
| 9 | Reserved                          | Unused                                           |

**Never put an empty field 2 into `/etc/shadow` — that is the "empty
password" CRITICAL finding from the security audit.** Use `passwd -l`
(which prepends `!`) or leave the distro's `*` for service accounts.

### /etc/group and /etc/gshadow

```
sudo:x:27:alice,bob,deploy
  1  2 3        4
```

| # | Field        | Notes                                |
|---|--------------|--------------------------------------|
| 1 | Group name   |                                      |
| 2 | Placeholder  | Password stored in `/etc/gshadow`    |
| 3 | GID          |                                      |
| 4 | Members      | Comma-separated usernames            |

`gshadow` holds the (rarely-used) group password and administrator
list; mode must be 640 root:shadow.

## useradd, usermod, userdel in depth

### useradd — raw, exact, scriptable

```bash
sudo useradd \
    --create-home \
    --shell /bin/bash \
    --groups sudo,ssh-users \
    --comment "Alice Sysadmin,,,alice@example.com" \
    --uid 1100 \
    alice
```

| Flag                       | Purpose                                          |
|----------------------------|--------------------------------------------------|
| `-m` / `--create-home`     | Create home dir from `/etc/skel`                 |
| `-d /custom/home`          | Override home path                                |
| `-s /bin/bash`             | Set login shell                                  |
| `-G sudo,ssh-users`        | Supplementary groups (comma-separated, no spaces)|
| `-g <group>`               | Primary group (must already exist)               |
| `-u 1100`                  | Specific UID (fail if taken)                     |
| `-c "Full Name,,,"`        | GECOS comment                                    |
| `-e 2026-12-31`            | Account expiry date                              |
| `-f 30`                    | Disable account 30 days after password expiry    |
| `--system`                 | System user: UID <1000, no home, no aging        |
| `-N` / `--no-user-group`   | Don't create a same-named group                  |
| `-M` / `--no-create-home`  | Don't create a home directory                    |

**`adduser` (Debian wrapper) vs `useradd` (POSIX):** `adduser` is
interactive, sets defaults from `/etc/adduser.conf`, and creates a
same-named group. Prefer `useradd` in scripts and `adduser` at the
keyboard.

### Service account — no login, no home

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin \
    --home-dir /var/lib/myapp myapp
```

### usermod — modify an existing user

```bash
# Add to a group (NEVER omit -a, it will replace!)
sudo usermod -aG sudo alice

# Remove from a group (since shadow-utils 4.14; on older use gpasswd)
sudo gpasswd -d alice sudo

# Change login shell
sudo usermod -s /bin/zsh alice

# Change username (and optionally home dir)
sudo usermod -l newname oldname
sudo usermod -d /home/newname -m newname     # -m moves contents

# Lock / unlock
sudo usermod -L alice
sudo usermod -U alice

# Expire account immediately
sudo usermod -e 1 alice      # field 8 = 1 day since epoch
sudo usermod -e '' alice     # clear expiry
```

**Gotcha:** `usermod -aG` without `-a` silently replaces all
supplementary groups. Always use `-a` with `-G`.

### userdel — remove a user

```bash
sudo userdel alice               # removes account, keeps /home and files
sudo userdel -r alice            # also removes /home/alice and mail spool
sudo userdel -f alice            # force, even if logged in (careful)
```

Before removing anyone, run the audit first:

```bash
# Who's logged in as them?
who | grep alice
ps -u alice

# What files do they own outside home?
sudo find / -user alice -not -path '/proc/*' 2>/dev/null | head -40

# Any cron jobs?
sudo crontab -l -u alice 2>/dev/null
ls -l /var/spool/cron/crontabs/alice 2>/dev/null
```

After deletion, `find ... -nouser` will show orphan files. Either
`chown` them to a real owner or delete.

## Password aging with chage

`chage` manipulates fields 3–8 of `/etc/shadow`.

```bash
# Show current aging
sudo chage -l alice
```

```
Last password change             : Jan 15, 2026
Password expires                 : Apr 15, 2026
Password inactive                : never
Account expires                  : never
Minimum number of days between password change        : 7
Maximum number of days between password change        : 90
Number of days of warning before password expires     : 14
```

```bash
# Set policy
sudo chage -m 7 -M 90 -W 14 -I 7 alice
#       | |    |    |    +-- inactive grace after expiry
#       | |    |    +------- warn N days before expiry
#       | |    +------------ max days valid
#       | +----------------- min days between changes
#       + -----------------

# Force password change on next login
sudo chage -d 0 alice

# Expire account on a specific date
sudo chage -E 2026-12-31 alice

# Remove expiry
sudo chage -E -1 alice
```

System-wide defaults live in `/etc/login.defs`:

```bash
grep -E '^PASS_(MAX|MIN|WARN)_DAYS|^UID_MIN|^UID_MAX|^ENCRYPT_METHOD' \
    /etc/login.defs
```

Recommended values for interactive users on a production host:

```
PASS_MAX_DAYS   90
PASS_MIN_DAYS   7
PASS_WARN_AGE   14
ENCRYPT_METHOD  YESCRYPT
```

Service accounts should keep `PASS_MAX_DAYS 99999` — rotating a service
account password every 90 days breaks integrations.

## Groups: adding, removing, listing

```bash
# Create
sudo groupadd -r system-group       # -r for system GID <1000
sudo groupadd ssh-users

# Remove
sudo groupdel ssh-users

# Add user to existing group
sudo usermod -aG ssh-users alice
sudo gpasswd -a alice ssh-users     # equivalent

# Remove user from group
sudo gpasswd -d alice ssh-users

# List everyone in a group
getent group ssh-users
grep '^ssh-users:' /etc/group

# List all groups a user belongs to
id alice
groups alice
```

After changing group membership, the user must log out and back in for
new groups to take effect in their shell. Or use `newgrp <group>` to
launch a sub-shell with the new group active.

## The sudoers file

`/etc/sudoers` is the authoritative policy. Edit **only** with `visudo`
— it runs a syntax check and refuses to save an invalid file, which
would otherwise lock everyone out of sudo:

```bash
sudo visudo
sudo visudo -f /etc/sudoers.d/10-deploy        # drop-in file
sudo visudo -c                                 # check only
```

Drop-in files under `/etc/sudoers.d/` are evaluated after the main
file. Prefer drop-ins for per-purpose policies — easier to diff, easier
to remove, and they don't clutter the main file.

### Grammar cheat sheet

```
who    where = (as_whom[:group]) [NOPASSWD:] [tag,tag] commands
```

```
alice          ALL = (ALL:ALL) ALL
%sudo          ALL = (ALL:ALL) ALL
bob            app-prod = (www-data) NOPASSWD: /usr/bin/systemctl restart nginx
%devs          ALL = (root) NOPASSWD: /usr/local/bin/deploy.sh
deployer       ALL = (www-data) NOPASSWD: /usr/bin/rsync -a *
```

Meaning of the fields:

| Field       | Example           | Notes                                              |
|-------------|-------------------|----------------------------------------------------|
| who         | `alice`, `%sudo`  | `%` prefix = group; `+netgroup` = netgroup         |
| where       | `ALL`, `app-prod` | Host restriction; `ALL` or a hostname              |
| as_whom     | `(ALL:ALL)`       | First = target user; second = target group        |
| NOPASSWD:   | optional          | No password prompt for that entry                  |
| commands    | `/bin/systemctl`  | Absolute paths, space-separated; `ALL` for any     |

### Aliases — Cmnd, User, Host, Runas

Aliases let you name a set once and reuse it:

```
# /etc/sudoers.d/20-deploy
Cmnd_Alias WEBCTL = /usr/bin/systemctl restart nginx, \
                    /usr/bin/systemctl reload nginx, \
                    /usr/bin/nginx -t
Cmnd_Alias PHPCTL = /usr/bin/systemctl restart php8.3-fpm, \
                    /usr/bin/systemctl reload php8.3-fpm
Cmnd_Alias DEPLOY = /usr/local/bin/deploy.sh, /usr/local/bin/rollback.sh

User_Alias DEPLOYERS = alice, bob, carol
Host_Alias WEB_HOSTS = web1, web2, web3

DEPLOYERS WEB_HOSTS = (root) NOPASSWD: WEBCTL, PHPCTL, DEPLOY
```

### Dangerous patterns — avoid these

- **`NOPASSWD: ALL`** on a broad group. One RCE → full root.
- **`NOPASSWD`** on an editor (`vi`, `nano`, `vim`). The editor can
  launch a shell (`:!sh`) → you just gave away root.
- **`NOPASSWD`** on `find`. `find . -exec /bin/sh \;` → root shell.
- **`NOPASSWD`** on `tar`, `zip`, `rsync` with wildcards. Any of these
  can overwrite arbitrary files with `--checkpoint-action=exec=...`.
- **Relative paths** in commands. A user with `PATH` control can drop a
  malicious `systemctl` under `/tmp` and win.
- **Shell metacharacters** in commands — they do not act as a shell.
  `ALL=(ALL) /bin/cat /var/log/*.log` looks like it globs; it doesn't.

### Lockdown patterns

Lock the sudoers file mode and ownership — most distros do this already
but double-check:

```bash
sudo chown root:root /etc/sudoers /etc/sudoers.d /etc/sudoers.d/*
sudo chmod 440 /etc/sudoers /etc/sudoers.d/*
sudo chmod 755 /etc/sudoers.d
```

Audit who can sudo:

```bash
sudo -l -U alice
getent group sudo
grep -r '^[^#]' /etc/sudoers /etc/sudoers.d/
```

Log all sudo commands to a dedicated file:

```
# /etc/sudoers.d/99-logging
Defaults logfile=/var/log/sudo.log
Defaults log_input, log_output
Defaults iolog_dir=/var/log/sudo-io/%{user}
```

And protect that log:

```bash
sudo install -d -m 750 -o root -g adm /var/log/sudo-io
```

## PAM stack basics

PAM (Pluggable Authentication Modules) is the framework that sits
between "a program wants to authenticate a user" and "`/etc/shadow` has
the hash". Configs live in `/etc/pam.d/<service>`. For Debian/Ubuntu
the relevant files are:

| File                       | When it's run                                  |
|----------------------------|------------------------------------------------|
| `/etc/pam.d/common-auth`   | "Who are you" — password / key check            |
| `/etc/pam.d/common-account`| "Are you allowed" — account validity check     |
| `/etc/pam.d/common-password`| Password change rules (pwquality lives here)  |
| `/etc/pam.d/common-session`| Per-session setup (limits, mounts, motd)       |

Other files (`sshd`, `login`, `sudo`) usually just `@include` these.
This keeps policy uniform across entry points.

### A typical common-auth after hardening

```
auth    [success=1 default=ignore]  pam_unix.so nullok
auth    requisite                   pam_deny.so
auth    required                    pam_permit.so
auth    required                    pam_faillock.so preauth silent deny=5 unlock_time=600
auth    sufficient                  pam_unix.so try_first_pass nullok
auth    [default=die]               pam_faillock.so authfail
auth    sufficient                  pam_faillock.so authsucc
auth    required                    pam_deny.so
```

### A typical common-password

```
password    requisite       pam_pwquality.so retry=3
password    [success=1 default=ignore]  pam_unix.so obscure use_authtok try_first_pass yescrypt
password    requisite       pam_deny.so
password    required        pam_permit.so
```

### Module semantics (control field)

| Control     | Meaning                                                        |
|-------------|----------------------------------------------------------------|
| `required`  | Must succeed; failure is remembered but stack continues        |
| `requisite` | Must succeed; failure returns immediately                      |
| `sufficient`| Success returns immediately (if no prior `required` failed)    |
| `optional`  | Result only matters if it's the only module of its type        |
| `[...]`     | Fine-grained action table (modern Debian uses this)            |

### Pam-auth-update — the Debian way

Instead of hand-editing the common-* files, Debian uses
`pam-auth-update` which assembles them from snippets in
`/usr/share/pam-configs/`. After installing `libpam-pwquality` or
`pam_faillock`, run:

```bash
sudo pam-auth-update
# Use space to toggle, Enter to apply.
```

Then diff the result:

```bash
grep -E 'pwquality|faillock' /etc/pam.d/common-auth /etc/pam.d/common-password
```

## Locking, expiring, and disabling accounts

Four distinct actions — pick the right one:

| Goal                                    | Command                     | What happens                                        |
|-----------------------------------------|-----------------------------|-----------------------------------------------------|
| User cannot log in with password        | `passwd -l alice`           | Prepends `!` to shadow hash                         |
| Same, via usermod                       | `usermod -L alice`          | Equivalent                                          |
| Unlock                                  | `passwd -u alice` / `usermod -U alice` | Removes the `!`                        |
| User account dead forever               | `chage -E 0 alice`          | Account expiry = today                              |
| Disable all shells but keep files       | `usermod -s /usr/sbin/nologin alice` | Can still own files, run cron, receive mail |
| Fully remove                            | `userdel -r alice`          | Destroys home dir and mail                          |

After locking, kill any existing sessions:

```bash
sudo pkill -KILL -u alice
sudo loginctl terminate-user alice 2>/dev/null
```

Verify:

```bash
sudo passwd -S alice          # L = locked, P = usable password, NP = no password
sudo chage -l alice
who | grep alice
```

**The break-glass pattern for an incident:** lock the account, expire
it, replace its shell with nologin, kill sessions, and rotate the SSH
keys so even a compromised key can't log back in.

```bash
sudo usermod -L alice
sudo chage -E 0 alice
sudo usermod -s /usr/sbin/nologin alice
sudo pkill -KILL -u alice
sudo mv /home/alice/.ssh/authorized_keys /home/alice/.ssh/authorized_keys.disabled
```

## SSH key management discipline

### Where keys live

| Path                                      | What's in it                                 |
|-------------------------------------------|----------------------------------------------|
| `~/.ssh/authorized_keys`                  | Public keys allowed to log in as this user   |
| `~/.ssh/id_ed25519`, `id_rsa`, ...        | Private keys (don't put these on servers!)   |
| `~/.ssh/id_ed25519.pub`, ...              | Matching public keys                         |
| `~/.ssh/known_hosts`                      | Host keys we've accepted                     |
| `~/.ssh/config`                           | Client-side config                           |
| `/etc/ssh/ssh_host_*_key{,.pub}`          | Server host keys                             |
| `/etc/ssh/sshd_config`                    | Server config                                |
| `/etc/ssh/sshd_config.d/99-hardening.conf`| Your hardening drop-in                       |

**Private keys should never live on the server.** A web host should
have only public keys in `authorized_keys` files and the server host
keys in `/etc/ssh`. If you find `id_rsa` in `/root/.ssh` or
`/home/deploy/.ssh`, treat it as a finding.

### Adding a key the right way

```bash
# Generate ON THE OPERATOR'S LAPTOP, not on the server
ssh-keygen -t ed25519 -C "alice@laptop" -f ~/.ssh/id_ed25519_alice

# Push it to the server with ssh-copy-id (uses existing auth to install)
ssh-copy-id -i ~/.ssh/id_ed25519_alice.pub alice@server

# Or manually (on the server, as alice):
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... alice@laptop" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Auditing every key on the server

```bash
sudo find / -name authorized_keys 2>/dev/null -exec sh -c '
    echo "=== $1 ===";
    awk "{ print NR\". \"\$1, \$3, \$NF }" "$1";
' _ {} \;
```

For each line, verify:

1. **Who is the comment?** If it's `root@old-laptop` and that laptop is
   gone, revoke.
2. **What key type?** `ssh-rsa` under 3072 bits is weak. Prefer
   `ssh-ed25519`.
3. **From restrictions?** Consider adding `from="10.0.0.0/8,198.51.100.0/24"`
   in front of keys that only need to work from known networks:

```
from="10.0.0.0/8" ssh-ed25519 AAAA... alice@laptop
```

### Revoking a key safely

```bash
# 1. Make a dated backup
sudo cp ~alice/.ssh/authorized_keys ~alice/.ssh/authorized_keys.bak.$(date +%F)

# 2. Remove the line (prefer sed with a unique fingerprint)
sudo sed -i '/alice@old-laptop/d' ~alice/.ssh/authorized_keys

# 3. Verify exactly what's left
sudo cat ~alice/.ssh/authorized_keys

# 4. Test from a second session — existing sessions stay open
ssh alice@server
```

Test the new state **from a second terminal** before closing the
original session. This is the #1 rule of SSH key management: never
burn the only working authorized_keys file without an escape hatch.

### Key lifecycle rules of thumb

- One key per operator device. Never share private keys across devices.
- Comment every key with `user@device-purpose` so you can decommission
  by identity.
- Rotate on suspicion — if a laptop is lost, revoke its key that day
  and regenerate, don't wait.
- Never commit private keys to git. `git-secrets` and pre-commit hooks
  help.
- CI/CD deploy keys are restricted-command keys — add
  `command="/usr/local/bin/deploy-only.sh",no-agent-forwarding,no-port-forwarding,no-pty`
  in front of the public key.

## Auditing: who has access, when did they last log in

```bash
# Real users (UID >= 1000, shell not nologin/false)
awk -F: '$3>=1000 && $7 !~ /nologin|false/ {print $1, $3, $6, $7}' /etc/passwd

# Everyone in privileged groups
getent group sudo adm root

# Password aging for interactive users
for u in $(awk -F: '$3>=1000 && $7 ~ /bash|zsh|sh/ {print $1}' /etc/passwd); do
    printf '=== %s ===\n' "$u"
    sudo chage -l "$u"
done

# Last login for every user
lastlog | head -20

# Recent interactive logins
last -a -F -n 30

# Failed logins (faillock on 22.04+, faillog on 20.04-)
sudo faillock 2>/dev/null || sudo faillog -a

# Currently logged in
w

# User activity (login/logout transitions)
last -F -n 100 | head
```

Flag anything unexpected — users with `NP` (no password) and an
interactive shell, users in `sudo` with no recent login for 180+ days,
SSH keys with no matching `last` entry.

## Optional fast path

When the `sk-*` scripts are installed, `sudo sk-user-audit` runs the
audit commands in this file, `sudo sk-ssh-key-audit` walks every
`authorized_keys` with age and fingerprint, and `sudo sk-new-sudoer
--user <u> --key <file>` creates a hardened sudoer in one step. These
are wrappers around the manual commands documented here.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd
  Edition, Packt — Chapter 2 "Securing User Accounts" (sudo, sudo
  policy file, limited sudo privileges, sudo timer), Chapter 3
  "Securing Normal User Accounts" (pwquality, pam_faillock on Ubuntu
  20.04 and 22.04).
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt —
  user management, password aging, account locking recipes.
- *Ubuntu Server Guide*, Canonical — "Security / Users" chapter:
  user and group management, account policy, root access.
- Manual pages: `useradd(8)`, `usermod(8)`, `userdel(8)`, `passwd(1)`,
  `chage(1)`, `visudo(8)`, `sudoers(5)`, `pam.conf(5)`, `pam_unix(8)`,
  `pam_faillock(8)`, `pam_pwquality(8)`, `ssh-keygen(1)`,
  `authorized_keys(5)`.
