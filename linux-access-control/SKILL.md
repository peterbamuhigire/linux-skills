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

## User Management

```bash
# Fast audit — all users, lock state, sudo, password age:
sudo sk-user-audit

# Add a new administrator with SSH key and sudo in one step:
sudo sk-new-sudoer --user alice --key ~/alice.pub

# Lock / unlock an account:
sudo sk-user-suspend --user alice --lock
sudo sk-user-suspend --user alice --unlock
```

Manual commands:

```bash
sudo adduser <username>                         # create (interactive)
sudo usermod -aG sudo <username>                # grant sudo
sudo deluser <username>                         # remove user (keeps home)
sudo deluser --remove-home <username>           # remove user + home
sudo passwd -l <username>                       # lock account
sudo passwd -u <username>                       # unlock account
```

---

## SSH Key Management

```bash
# Audit all authorized_keys across users:
sudo sk-ssh-key-audit

# Add a key for a user (manual):
mkdir -p /home/<username>/.ssh
chmod 700 /home/<username>/.ssh
echo "<public-key>" >> /home/<username>/.ssh/authorized_keys
chmod 600 /home/<username>/.ssh/authorized_keys
chown -R <username>:<username> /home/<username>/.ssh

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
