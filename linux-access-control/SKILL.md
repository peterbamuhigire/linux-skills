---
name: linux-access-control
description: Manage users, groups, SSH keys, sudo access, and file permissions on Ubuntu/Debian servers. Create/delete users, manage sudo group, add/revoke SSH authorized_keys, audit who has access, fix file permissions in web roots and credential files.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Access Control

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool. The `sk-*` scripts in the **Optional fast path** section
are convenience wrappers — never required.

## User Management

```bash
sudo adduser <username>                         # create (interactive)
sudo usermod -aG sudo <username>                # grant sudo
sudo deluser <username>                         # remove user (keeps home)
sudo deluser --remove-home <username>           # remove user + home
sudo passwd -l <username>                       # lock account
sudo passwd -u <username>                       # unlock account

# Audit
grep -v "nologin\|false" /etc/passwd | cut -d: -f1,3
grep ^sudo /etc/group                           # who has sudo
awk -F: '$3 == 0 {print $1}' /etc/passwd       # UID-0 accounts
```

---

## SSH Key Management

```bash
# Add a key for a user
mkdir -p /home/<username>/.ssh
chmod 700 /home/<username>/.ssh
echo "<public-key>" >> /home/<username>/.ssh/authorized_keys
chmod 600 /home/<username>/.ssh/authorized_keys
chown -R <username>:<username> /home/<username>/.ssh

# Audit all keys on the server
find /home /root -name authorized_keys 2>/dev/null | \
    while read f; do echo "=== $f ==="; cat "$f"; done

# Revoke: edit the file, delete the key line
sudo nano /home/<username>/.ssh/authorized_keys

# Test before restarting SSH (keep existing session open!)
sudo sshd -t && sudo systemctl restart sshd
```

---

## File Permissions — Quick Reference

```bash
# Web root standard
sudo find /var/www -type d -exec chmod 755 {} \;
sudo find /var/www -type f -exec chmod 644 {} \;
sudo chown -R www-data:www-data /var/www/html/
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;   # remove world-write

# Critical system files
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group

# Backup credentials (must be 600)
chmod 600 ~/.mysql-backup.cnf ~/.backup-encryption-key
chmod 600 ~/.config/rclone/rclone.conf
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

Full permission patterns and audit commands: `references/permissions-reference.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-access-control` installs:

| Task | Fast-path script |
|---|---|
| All users, UID, lock state, sudo, password age | `sudo sk-user-audit` |
| All authorized_keys across users | `sudo sk-ssh-key-audit` |
| Create user + SSH key + sudo in one step | `sudo sk-new-sudoer --user <u> --key <file>` |
| Lock or unlock a user account | `sudo sk-user-suspend --user <u> --lock\|--unlock` |

These are optional wrappers. The manual commands above are the source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-access-control
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-user-audit | scripts/sk-user-audit.sh | yes | All users, UID/GID, lock state, password age, last login, sudoers. |
| sk-ssh-key-audit | scripts/sk-ssh-key-audit.sh | yes | All `authorized_keys` across users, key type/age/comment, orphaned keys. |
| sk-new-sudoer | scripts/sk-new-sudoer.sh | no | Create user, deploy SSH key, add to sudo group, verify with `sudo -l`. |
| sk-user-suspend | scripts/sk-user-suspend.sh | no | Lock or unlock a user account (`passwd -l`, `usermod -s /usr/sbin/nologin`), with audit log. |
