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

This skill owns **secret hygiene** on a managed server: scanning for
credentials that have leaked into files or repos, encrypting config at
rest with `age` or `sops`, and rotating credentials without downtime.

Informed by *Linux System Administration for the 2020s* (secrets are a
first-class operational concern, not an afterthought).

It does **not** own:

- **SSH keys** for user access — that's `linux-access-control`.
- **TLS certificates** for web services — that's `linux-firewall-ssl`.
- **Secrets inside application code repos** (beyond scanning) — application
  teams own their own vaulted secrets.

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

- Storing a single secret for one operator's personal use — use their
  own password manager.
- Managing cloud provider secret stores (AWS Secrets Manager, Vault) —
  out of scope for v1.

---

## Standing rules

1. **Credential files are mode `0600`, owned by the process that needs
   them.** `sk-audit` flags anything else.
2. **Credentials never live in a git-tracked file in plain text.**
   `sk-secret-scan` runs as a pre-commit hook in this repo and in any
   application repo where possible.
3. **Every rotation has a verification step.** A rotation that doesn't
   prove the new credential works is worse than no rotation at all
   (service quietly breaks; detected when the old credential would have
   been revoked anyway). `sk-secret-rotate` enforces a `--verify-with`
   parameter.
4. **Rotation is dry-runnable.** Every rotation supports `--dry-run`
   which prints the steps without writing.
5. **`age` is preferred over `gpg` for new encryption.** `age` is
   smaller, simpler, and has a modern key format. `sops` wraps it with
   config-file-aware encryption.
6. **Leaked secrets are revoked immediately, not "after we understand the
   scope."** Scope analysis happens *after* the credential is revoked.

---

## Typical workflows

### Scanning a repo before commit

```bash
sk-secret-scan --path /var/www/my-app
```

Runs trufflehog-style rules against the tree, reports any matches with
file:line, the rule that matched, and a one-line remediation.

### Rotating the backup GPG key

```bash
sudo sk-secret-rotate \
    --credential backup-gpg \
    --verify-with "sudo sk-mysql-backup --dry-run"
```

- Generates a new GPG key.
- Re-encrypts `/etc/linux-skills/backup.key` with the new key.
- Runs the verification command to prove the new key works.
- On success, marks the old key for revocation (but doesn't delete it;
  there's a grace period to decrypt old backups).
- Audit line written to `/var/log/linux-skills/sk-secret-rotate.log`.

### Auditing credential file permissions on a server

```bash
sudo sk-secret-scan --filesystem
```

Walks known credential locations (`/etc/mysql/`, `/etc/linux-skills/`,
`/root/.aws/`, `/etc/letsencrypt/live/`) and reports any files whose mode
isn't `0600` or whose owner doesn't match the expected process.

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-secrets
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-secret-scan | scripts/sk-secret-scan.sh | no | Scan a repo tree or filesystem path for credentials, API keys, private keys using trufflehog-style rules; verify credential file permissions. |
| sk-secret-rotate | scripts/sk-secret-rotate.sh | no | Rotate a managed credential (backup GPG, DB password, API token), update dependent services, run a verification command, audit-log the rotation. |

---

## See also

- `linux-access-control` — user SSH keys and sudoers.
- `linux-firewall-ssl` — TLS certs and renewal.
- `linux-disaster-recovery` — backup encryption keys are the
  highest-value credentials; rotation must not orphan existing backups.
- `linux-config-management` — Ansible Vault integration.
