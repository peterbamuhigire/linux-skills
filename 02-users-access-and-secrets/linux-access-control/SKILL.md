---
name: linux-access-control
description: Use when creating, revoking, or auditing Linux users, groups, SSH keys, sudo/wheel access, PAM settings, SELinux user mappings, or file permissions. Use linux-secrets for credential material and linux-server-hardening for broader host policy.
license: MIT
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Access Control

## Distro support

Two-family skill. `useradd`/`usermod`/`passwd`, SSH keys, and `/etc/sudoers.d/`
work the same on both. The notable differences are the **admin group** and a
couple of RHEL-only auth/SELinux layers. Body uses Debian/Ubuntu; substitute
per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Sudo admin group | `sudo` | `wheel` |
| Grant admin | `usermod -aG sudo <u>` | `usermod -aG wheel <u>` |
| User/group tools | `useradd`, `usermod`, `passwd` | identical |
| Sudoers drop-ins | `/etc/sudoers.d/` | same |
| PAM config | `/etc/pam.d/` | `/etc/pam.d/` (managed via `authselect` on RHEL) |
| Password quality | `libpam-pwquality` | `pam_pwquality` (in `pwquality.conf`) |
| SELinux user mapping | n/a | `semanage login` maps Linux users → SELinux users |

**RHEL-family note:** the admin group is `wheel`, not `sudo`. RHEL manages the
PAM/nsswitch stack through `authselect` (don't hand-edit what it owns), and
SELinux can confine users (`semanage login`, `semanage user`). See
[`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md)
and [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

<!-- dual-compat-start -->
## Use when

- Managing Linux users, groups, sudo access, SSH keys, or file permissions.
- Auditing who can log in or who has elevated access on a server.
- Fixing ownership or permission problems in web roots, home directories, or credential files.

## Do not use when

- The task is firewalling or TLS; use `linux-firewall-ssl`.
- The task is broader security analysis or hardening; use `linux-security-analysis` or `linux-server-hardening`.

## Required inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Target identities, groups, paths, keys, and requested privileges | Access request or system owner | required | Stay read-only and return the missing identity/scope. |
| Current account, group, sudoers, SSH, PAM, and file state | Target host | required | Do not mutate; provide inspection commands only. |
| Approval, expiry, owner, and recovery access | Authorised approver | required for mutation | Stop before granting or revoking access. |

## Workflow

1. Identify the account or path being changed and inspect current state first.
2. Apply the least-privilege change with the manual commands below.
3. Re-check login access, sudo membership, and file ownership after the change.
4. Use optional scripts only when they are installed and clearly match the task.
5. Stop if the approver, target identity, recovery administrator, or ownership boundary is unresolved.
6. Recover a failed access change through the tested alternate session, restore the saved sudoers/key/file state, and verify login again.

## Quality standards

- Prefer reversible, explicit changes over blanket permission fixes.
- Preserve SSH access and validate the impact before removing keys or users.
- Credential files must remain tightly permissioned.

## Anti-patterns

- Running recursive `chmod` or `chown` without scoping the target. Fix: inspect boundaries and change only the named tree or files.
- Granting sudo or shell access without an approved need. Fix: use the least privilege and record the owner and expiry.
- Deleting an account before reviewing its files, processes, jobs, and keys. Fix: disable first, inventory dependencies, then remove deliberately.
- Editing `/etc/sudoers` without validation. Fix: use a drop-in and validate with `visudo` before ending the recovery session.
- Revoking the only working administrator or SSH key. Fix: prove an independent break-glass path first.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Access decision/change record | System owner | Names identity, privilege, approver, expiry, files changed, and rationale. |
| Final-state verification | Operator | Login, group/sudo membership, key fingerprints, and affected permissions match the request. |
| Recovery note | On-call administrator | Preserves a tested alternate administrator and reversal steps. |

## References

- [`references/users-sudoers-pam.md`](references/users-sudoers-pam.md)
- [`references/permissions-reference.md`](references/permissions-reference.md)
- [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux user confinement (RHEL family)

## Evidence Produced

| Artefact | Acceptance condition |
|---|---|
| Access-control evidence | Shows before/after identity state, key fingerprints, sudoers validation, affected modes, tested login/privilege behaviour, and approval. |

## Capability contract

Audit requests default to read-only. Read access to account and permission state is required; editing users, groups, keys, PAM, sudoers, SELinux mappings, or files requires explicit authority. Never expose private keys or revoke the last tested administrator.

## Degraded mode

Without privileged access, report observable state and exact root-level checks as `not assessed`. Without a safe second login or console, stop before lockout-capable changes.

## Decision rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Temporary privileged task | Use narrow sudo command rules with expiry | Permanent broad administration. |
| Suspected compromised key | Disable that key, preserve evidence, rotate dependants | Continued unauthorised access. |
| Account departure | Disable, inventory ownership/jobs, transfer, then remove | Orphaned data and services. |

## Worked example

To offboard a deployment user, record current groups, keys, processes, cron jobs, and owned files; disable login; verify the replacement automation identity; transfer required ownership; remove authorised keys; then confirm the account cannot authenticate while the service still deploys.

<!-- dual-compat-end -->

**This skill is self-contained.** Every command below is a standard tool on
both families (Debian/Ubuntu and RHEL); substitute the admin group and
RHEL-only auth/SELinux layers per the **Distro support** matrix above. The
`sk-*` scripts in the **Optional fast path** section are convenience
wrappers — never required.

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
