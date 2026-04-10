---
name: linux-secrets
description: Handle secrets on Ubuntu/Debian servers — scan for leaked credentials, encrypt config with age/sops, rotate managed credential files. Use whenever sensitive material touches the filesystem or a repo.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Secrets

**This skill is self-contained.** Every command below is a standard tool
(`trufflehog`, `gitleaks`, `age`, `sops`, `gpg`, `stat`, `find`). The
`sk-*` scripts in the **Optional fast path** section are convenience
wrappers — never required.

This skill owns **secret hygiene** on a managed server: scanning for
credentials that have leaked into files or repos, encrypting config at
rest with `age` or `sops`, and rotating credentials without downtime.

Informed by *Linux System Administration for the 2020s* (secrets are a
first-class operational concern, not an afterthought).

It does **not** own:

- **User SSH keys** for access — `linux-access-control`.
- **TLS certificates** — `linux-firewall-ssl`.
- **Application secrets lifecycle inside code repos** (beyond scanning)
  — application teams own their own vaulting.

---

## When to use

- Scanning a repo or directory for accidentally committed credentials.
- Encrypting a config file (database password, API key) with `age` or
  `sops`.
- Rotating a managed credential: backup GPG key, MySQL user password,
  API token.
- Auditing which files on the server contain credentials and verifying
  their permissions.

## When NOT to use

- Storing a single personal secret — use a password manager.
- Managing cloud provider secret stores (AWS Secrets Manager, Vault) —
  out of scope for v1.

---

## Standing rules

1. **Credential files are mode `0600`, owned by the process that needs
   them.**
2. **Credentials never live in a git-tracked file in plain text.**
   Secret scanning is a pre-commit requirement.
3. **Every rotation has a verification step.** A rotation that doesn't
   prove the new credential works is worse than no rotation at all.
4. **Rotation is dry-runnable.** Every rotation supports `--dry-run`
   which prints the steps without writing.
5. **`age` is preferred over `gpg` for new encryption.** Smaller,
   simpler, modern key format. `sops` wraps it with config-file
   awareness.
6. **Leaked secrets are revoked immediately, not "after we understand
   the scope."** Scope analysis happens *after* revocation.
7. **Rotation order is: generate → deploy alongside → verify → revoke.**
   Never revoke first (guaranteed outage). Never big-bang (no rollback).

---

## Quick reference — manual commands

### Secret scanning

```bash
# trufflehog v3 (recommended)
# Install: curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sudo sh -s -- -b /usr/local/bin
trufflehog filesystem /var/www/my-app --no-update
trufflehog git file:///home/user/my-repo --no-update

# gitleaks (alternative)
# Install: sudo apt install gitleaks  (or from GitHub releases for newer versions)
gitleaks detect --source . --verbose
gitleaks detect --source . --log-opts="--since=2026-01-01"

# detect-secrets (Python, pre-commit friendly)
sudo apt install detect-secrets
detect-secrets scan > .secrets.baseline

# Audit filesystem credential file permissions
find /etc /root /home -type f \( -name "*.key" -o -name "*.pem" -o -name ".mysql-backup.cnf" -o -name "rclone.conf" \) -printf "%m %u:%g %p\n" 2>/dev/null
```

Full scanning playbook (custom rule files, pre-commit hook integration,
false-positive suppression, history rewrite with `git-filter-repo`,
cron-scheduled sweeps) — see
[`references/secret-scanning.md`](references/secret-scanning.md).

### age encryption (modern, simple)

```bash
# Install
sudo apt install age

# Generate a key (owner)
mkdir -p ~/.config/age && chmod 700 ~/.config/age
age-keygen -o ~/.config/age/keys.txt
chmod 600 ~/.config/age/keys.txt

# Get the public key (shareable)
grep "# public key:" ~/.config/age/keys.txt
# age1abcd...

# Encrypt to a single recipient
age -r age1abcd... -o secret.age secret.txt

# Decrypt (needs the private key)
age -d -i ~/.config/age/keys.txt -o secret.txt secret.age

# Encrypt to multiple recipients (backup + primary)
age -r age1abcd... -r age1efgh... -o secret.age secret.txt

# Use an SSH key as recipient (age reads ssh-ed25519 directly)
age -R ~/.ssh/id_ed25519.pub -o secret.age secret.txt
age -d -i ~/.ssh/id_ed25519 -o secret.txt secret.age
```

### sops (wraps age for config-file-aware encryption)

```bash
# Install sops from GitHub releases
SOPS_VER=3.9.0
curl -LO https://github.com/getsops/sops/releases/download/v${SOPS_VER}/sops-v${SOPS_VER}.linux.amd64
sudo install -m 0755 sops-v${SOPS_VER}.linux.amd64 /usr/local/bin/sops

# Create .sops.yaml — who can decrypt what
cat > .sops.yaml <<'EOF'
creation_rules:
  - path_regex: secrets/.*\.yaml$
    age: age1abcd...,age1efgh...
EOF

# Encrypt YAML/JSON/ENV (only values, not keys)
sops -e -i secrets/db.yaml

# Edit in place (opens $EDITOR with decrypted content)
sops secrets/db.yaml

# Decrypt to stdout (for CI)
sops -d secrets/db.yaml

# Rotate recipients after adding/removing a team member
sops updatekeys secrets/db.yaml
```

Full age/sops deep dive (multi-recipient, SSH keys, YubiKey via
age-plugin-yubikey, threat model, Ansible integration via
`community.sops`, systemd `LoadCredentialEncrypted=`, docker-compose
secrets, complete `database.env` example) — see
[`references/age-and-sops.md`](references/age-and-sops.md).

### Credential rotation

```bash
# Pattern: generate → deploy alongside → verify → revoke
# Example: backup GPG key rotation

# 1. Generate new key
gpg --quick-generate-key "backup-$(date +%Y)" default default 2y

# 2. Re-encrypt a test file with the new key
gpg --encrypt --recipient "backup-$(date +%Y)" --output test.gpg test.txt

# 3. Verify decryption works
gpg --decrypt test.gpg > /tmp/test.out && diff test.txt /tmp/test.out

# 4. Update the backup script config to reference the new key ID

# 5. Run a real backup with the new key (dry-run first)
sudo /usr/local/bin/mysql-backup.sh --dry-run

# 6. Real run + verification
sudo /usr/local/bin/mysql-backup.sh

# 7. Only now mark the old key for eventual revocation (keep for grace period
#    so old backups can still be decrypted)

# 8. Log the rotation to the append-only audit trail
echo "$(date -Iseconds) rotated backup gpg key from <old-id> to <new-id>" | \
    sudo tee -a /var/log/linux-skills/secret-rotations.log
```

Full rotation playbook (category cadences, three concrete runbooks,
append-only audit log with `chattr +a`) — see
[`references/rotation-playbook.md`](references/rotation-playbook.md).

---

## Typical workflows

### Workflow: "Scan a repo before commit"

```bash
cd /var/www/my-app
trufflehog filesystem . --no-update

# If anything is found:
# 1. REVOKE the credential at its source immediately (database, API, etc.)
# 2. Rotate
# 3. Only then consider history cleanup
```

### Workflow: "Encrypt a new secrets file for Ansible"

```bash
# Add the sops rule for this repo (one-time per recipient change)
cat > .sops.yaml <<'EOF'
creation_rules:
  - path_regex: ansible/group_vars/.*/vault\.yaml$
    age: age1abcd...
EOF

# Create the plaintext values, then encrypt in place
cat > ansible/group_vars/all/vault.yaml <<'EOF'
database_password: supersecret
api_token: tk_live_abc
EOF

sops -e -i ansible/group_vars/all/vault.yaml

# Edit later with:
sops ansible/group_vars/all/vault.yaml

# Ansible side: use community.sops.load_vars
```

### Workflow: "Rotate the backup GPG key annually"

See [`references/rotation-playbook.md`](references/rotation-playbook.md)
for the full runbook. Summary:

1. Generate new key with 2-year expiry.
2. Re-encrypt the current credential file to both old AND new (grace period).
3. Run a dry-run backup with the new key.
4. Run a real backup, verify it decrypts.
5. Update documentation with the new key ID and fingerprint.
6. Schedule old-key revocation for 90 days from now.
7. Append rotation entry to `/var/log/linux-skills/secret-rotations.log`.

### Workflow: "Audit credential file permissions"

```bash
# Walk known credential locations
sudo find /etc/mysql /root/.ssh /etc/ssl/private /etc/letsencrypt/live \
    /home/*/.config/rclone /home/*/.mysql-backup.cnf \
    -type f -printf "%m %u:%g %p\n" 2>/dev/null | sort

# Anything not 600 or 640 is a finding
sudo find /etc/mysql /root/.ssh /etc/ssl/private -type f \
    -not -perm 600 -not -perm 640 -printf "%m %p\n" 2>/dev/null
```

---

## Troubleshooting / gotchas

- **`trufflehog` false positives on test fixtures.** Add them to a
  baseline file (`trufflehog` supports `--exclude-paths`). Baselines are
  safer than inline `// nosecrets` comments because baselines are
  reviewed during changes.
- **Big-bang rotation breaks production.** Every consumer must see the
  new credential before the old one is revoked. Design for
  dual-credentials during the grace period.
- **`sops updatekeys` is silent.** It re-encrypts the data key to the
  new recipients but doesn't tell you which files it touched. Always
  run in a clean git tree and inspect the diff.
- **age keys in `~/.config/age/keys.txt` are plaintext on disk.** They
  are protected by filesystem permissions only. For higher assurance,
  use `age-plugin-yubikey` so the private half lives on hardware.
- **Revoking a backup GPG key before the grace period expires orphans
  old backups.** Keep the old key for at least one full backup cycle
  after rotation — longer for compliance retention.
- **`chattr +a` on the rotation log prevents accidental deletion but
  does NOT stop root from unlinking the file.** Combine with off-host
  log shipping for real tamper evidence.

---

## References

- [`references/secret-scanning.md`](references/secret-scanning.md) —
  trufflehog, gitleaks, detect-secrets, pre-commit integration, history
  rewrite, filesystem audit.
- [`references/age-and-sops.md`](references/age-and-sops.md) — full age
  and sops deep dive with Ansible and systemd integration.
- [`references/rotation-playbook.md`](references/rotation-playbook.md) —
  rotation discipline, three concrete runbooks, tamper-evident audit log.
- Book: *Linux System Administration for the 2020s* — DevSecOps chapter,
  security gates before artifacts flow downstream.
- Upstream docs: age (https://github.com/FiloSottile/age), sops
  (https://github.com/getsops/sops), trufflehog
  (https://github.com/trufflesecurity/trufflehog).

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-secrets` installs:

| Task | Fast-path script |
|---|---|
| Scan a tree or filesystem for credentials + permissions | `sudo sk-secret-scan --path <dir>` |
| Rotate a managed credential with verification | `sudo sk-secret-rotate --credential <name> --verify-with <cmd>` |

These are optional wrappers around `trufflehog`, `age`, `sops`, `gpg`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-secrets
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-secret-scan | scripts/sk-secret-scan.sh | no | Scan a repo tree or filesystem path for credentials, API keys, private keys; verify credential file permissions. |
| sk-secret-rotate | scripts/sk-secret-rotate.sh | no | Rotate a managed credential, update dependent services, run a verification command, audit-log the rotation. |
