# Credential Rotation Playbook

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Rotation is a discipline, not a task. *Linux System Administration for
the 2020s* is emphatic about the distinction: a task gets done once
and forgotten; a discipline is how you run the estate. Every credential
on a managed server has a rotation runbook and every rotation has a
verification step, because a silent rotation failure is worse than no
rotation at all — the service quietly breaks, the breakage is noticed
only when the old credential would have been revoked anyway, and you
end up firefighting in the middle of the revocation window.

The two failure modes to avoid:

- **Revoke-first rotation** — kill the old credential, then try to
  deploy the new one. The service is down for the entire deploy
  window. If the deploy fails, the service is down until someone
  manually un-revokes or issues a third credential. Outage
  guaranteed.
- **Big-bang rotation** — generate a new credential, swap every
  consumer in one motion, pray. No rollback path. If any consumer
  fails to pick up the new value, you have no clean way back.

The correct pattern is **generate, deploy alongside, cut over,
verify, revoke old after grace period**. This is sometimes called
"dual-credential bridging" and it is the only pattern that gives you
a rollback window.

## Table of contents

1. The rotation discipline in one paragraph
2. Categories of secrets and their cadences
3. The general rotation pattern
4. Why revoke-first fails
5. Why big-bang fails
6. Rotation runbook template
7. Runbook: backup GPG key rotation
8. Runbook: MySQL application user password with dual-creds
9. Runbook: API token stored in /etc/linux-skills
10. The rotation audit log
11. Dry-run and verification requirements

---

## 1. The rotation discipline in one paragraph

For every credential the server holds: it has an owner, a rotation
cadence, a documented runbook, a dry-run mode, a verification
command that proves the new credential actually works before the
old one is revoked, a grace period during which both credentials
are valid, and a tamper-evident audit log entry for every rotation.
If any of those are missing, the credential is not managed — it is
just something that happens to be on the box.

## 2. Categories of secrets and their cadences

| Category | Example | Cadence | Grace period | Notes |
|---|---|---|---|---|
| **Backup encryption keys** | `/etc/linux-skills/backup.key` | Annual | 6 months | Old backups encrypted with the old key must remain decryptable for the retention window. Never revoke hard. |
| **Database user passwords** | MySQL app user | Quarterly + on staff departure | 24-48 hours dual-creds | Use two parallel user accounts or a password-version field. |
| **Third-party API tokens** | Stripe, SendGrid, Cloudflare | Every 6 months + on staff departure | Whatever the provider's grace period allows | Rotation is done in the provider's admin UI; your local work is updating the stored copy. |
| **TLS certificates** | Nginx cert, mail cert | Automated (certbot) | Automated | See `linux-firewall-ssl`. Rotation is literally `systemctl reload`; verification is `curl -I`. |
| **SSH deploy keys** | `authorized_keys` for the deploy user | Every 6 months + on staff departure | 1-2 weeks | Generate new, add to `authorized_keys`, deploy via new key, remove old. |
| **Admin / root-equivalent passwords** | Local root password, `sudo` NOPASSWD paths | On staff departure only | N/A | Cadence-based rotation of root passwords is security theatre on a server where only key-based SSH is allowed. |

Match the cadence to the blast radius and the operational cost. A
monthly rotation of a rarely-used backup key is all cost and no
benefit; an annual rotation of an internet-facing API token is
negligence.

## 3. The general rotation pattern

The five-phase pattern every runbook follows:

1. **Generate** the new credential. Do not deploy it anywhere yet.
   Keep it somewhere encrypted (sops-managed file, password manager).
2. **Deploy alongside** the old credential. Both are live
   simultaneously. This is the dual-creds phase. For a DB user this
   might mean a second user row; for a key it might mean two keys in
   `authorized_keys`; for an API token it might mean a second token
   stored in the config.
3. **Cut over** consumers to the new credential. Change the config,
   restart the services, confirm the new credential is being used.
4. **Verify**. Run a command that actively exercises the new
   credential end-to-end. Not "the process started" — "the process
   did its thing with the new credential and the thing worked".
5. **Revoke** the old credential, but only after a grace period
   during which you watch for any consumer that was missed in step 3.
   Log the rotation with timestamp and operator.

Every runbook maps onto these five phases. If a rotation procedure
cannot be expressed in these phases, it is probably a replacement,
not a rotation, and it needs a maintenance window.

## 4. Why revoke-first fails

"Let's rotate the DB password. First we change it on the DB
server. Then we update the app config. Then we restart the app."

Between step one and step three, the app cannot connect. If the app
is public-facing, users see errors for the entire window. If step
two has a typo, the window extends until someone notices. If step
three fails (the service file is wrong, the container won't pull,
the deploy script has a bug), the app is down indefinitely and the
only rollback is to un-revoke on the DB server — which is often
impossible if the old password was never recorded.

Revoke-first is an outage disguised as security hygiene. It converts
a routine maintenance activity into an incident.

## 5. Why big-bang fails

"Let's rotate the API token. First we generate the new one. Then we
update every consumer simultaneously. Then we revoke the old."

If "every consumer" is one consumer, this is fine. If it is five
consumers across three hosts, it is an accident waiting for a
network partition. The moment one consumer fails to pick up the
new token, you have no way to roll back without issuing a third
token — and by then the old one is revoked, so the rollback means
reissuing everywhere again.

The dual-creds pattern gives you **idempotency under partial
failure**: if only three of five consumers rotated, the remaining
two are still working with the old credential, the system is still
healthy, and you fix the two stragglers in your own time. The book's
automation chapter calls this out directly — idempotent code that
converges to the desired state is the only kind of automation that
survives contact with production.

## 6. Rotation runbook template

Every runbook in `/etc/linux-skills/runbooks/rotate-*.md` follows
the same shape. Filling in the template is the first step of
onboarding a new credential to the managed set.

```markdown
# Rotate: <credential name>

**Owner:** <team or person>
**Cadence:** <interval + trigger events>
**Grace period:** <how long both credentials stay live>
**Consumers:** <list of services, hosts, configs that read this>

## Prerequisites
- <what needs to be true before starting>
- <operator permissions required>
- <backups or exports taken before starting>

## Generate
1. <commands to produce the new credential>

## Deploy alongside
1. <how both old and new coexist>

## Cut over
1. <commands to point consumers at the new credential>

## Verify
- <exact command to prove the new credential works end-to-end>
- <expected output>
- <what a failure looks like and how to roll back>

## Revoke
- <when to revoke (date + verified observation)>
- <how to revoke>

## Log
- Append to /var/log/linux-skills/secret-rotations.log
- Format: <ISO8601> <operator> <credential> <status> <verify-output-hash>
```

Runbooks are themselves tracked in git (not encrypted — they contain
procedure, not secrets) and reviewed in PRs like any other change.

## 7. Runbook: backup GPG key rotation

This is the highest-value credential on the box — if the backup key
leaks, an attacker can read every backup; if the backup key is lost,
every backup is a brick. The rotation is therefore **the most
conservative possible**: annual cadence, six-month grace period, the
old key is moved offline but never destroyed while old backups still
need decryption.

**Generate:**

```bash
# New age keypair for backup encryption
sudo install -d -m 0700 -o root -g root /etc/linux-skills/keys
sudo age-keygen -o /etc/linux-skills/keys/backup-$(date +%Y).key
sudo chmod 600 /etc/linux-skills/keys/backup-$(date +%Y).key

# Extract public key for backup scripts
sudo grep "public key" /etc/linux-skills/keys/backup-$(date +%Y).key
```

**Deploy alongside:**

The backup script should already read a **list** of recipients from
`/etc/linux-skills/backup-recipients.conf`, not a single key. Rotation
means appending the new pubkey to that list. New backups are now
encrypted to both keys; old backups remain encrypted to only the old
key.

```bash
sudo sh -c 'echo "age1new..." >> /etc/linux-skills/backup-recipients.conf'
sudo systemctl restart linux-skills-backup.timer
```

**Cut over:** no cut over required. The backup script already uses
every recipient in the list. Dual-encryption is automatic.

**Verify:**

```bash
# Run the next scheduled backup manually in dry-run mode
sudo sk-mysql-backup --dry-run --verbose

# Confirm the resulting file decrypts with the NEW key
sudo age -d -i /etc/linux-skills/keys/backup-$(date +%Y).key \
    /var/backups/mysql/latest.sql.age | head -5
```

**Revoke (after 6 months and confirmation that no backup older than
the retention window is still needed):**

```bash
# Remove the old recipient from the list
sudo sed -i '/age1old.../d' /etc/linux-skills/backup-recipients.conf

# Move the old private key to offline cold storage — do NOT delete
# for at least another 12 months beyond the retention window
sudo mv /etc/linux-skills/keys/backup-$(date -d 'last year' +%Y).key \
    /mnt/offline-safe/archive/
```

**Log:**

```bash
sudo sh -c 'printf "%s %s backup-gpg-key rotated verify=ok\n" \
    "$(date -Iseconds)" "$USER" \
    >> /var/log/linux-skills/secret-rotations.log'
```

## 8. Runbook: MySQL application user password with dual-creds

Quarterly rotation. The trick that makes this zero-downtime: create
a **second user account** with a versioned name, migrate consumers,
then drop the old. MySQL has no "old and new password" feature, but
two user rows work just as well.

**Generate:**

```bash
# New password, stored in sops-managed env file
NEW_PASS=$(openssl rand -base64 32 | tr -d '/+=')
echo "$NEW_PASS"   # capture into your password manager immediately
```

**Deploy alongside:**

```sql
-- On the database
CREATE USER 'myapp_v2'@'10.%.%.%' IDENTIFIED BY 'NEW_PASS_HERE';
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'myapp_v2'@'10.%.%.%';
FLUSH PRIVILEGES;

-- Old user 'myapp_v1' is still live. Both work.
```

**Cut over:** update the sops-encrypted app config on every host, one
host at a time, verifying each before moving on.

```bash
# On the admin host
EDITOR=vim sops config/prod/database.yaml   # change user to myapp_v2, pw to new
git add config/prod/database.yaml
git commit -m "secrets: rotate MySQL app user to v2"
git push

# On each app host, in a controlled rollout
ssh web01 "cd /srv/myapp && git pull && sudo systemctl restart myapp && \
    curl -sf http://localhost:8080/healthz"
ssh web02 "..."
```

If any host's healthcheck fails, stop the rollout. The previously
updated hosts are fine because `myapp_v1` is still live and any
consumer on `myapp_v2` is also fine. You can investigate the failure
without time pressure.

**Verify:**

```bash
# Confirm every host is now using myapp_v2 by tailing the DB's general log
# or by querying processlist
mysql -e "SELECT user, host FROM information_schema.processlist WHERE db='myapp';"
# -> should show only myapp_v2, not myapp_v1
```

**Revoke (after 24-48 hours of clean processlist):**

```sql
DROP USER 'myapp_v1'@'10.%.%.%';
FLUSH PRIVILEGES;
```

**Log:**

```bash
sudo sh -c 'printf "%s %s mysql-myapp-user rotated v1->v2 verify=processlist-clean\n" \
    "$(date -Iseconds)" "$USER" \
    >> /var/log/linux-skills/secret-rotations.log'
```

Next rotation creates `myapp_v3`. Version the suffix so the rotation
has a clear, audit-friendly identity.

## 9. Runbook: API token stored in /etc/linux-skills

Example: a Cloudflare API token used by `certbot` and by a dynamic-DNS
updater. Rotation cadence: every 6 months or on staff departure. The
token is stored in a sops-managed file at
`/etc/linux-skills/cloudflare.token.sops`.

**Generate:** create the new token **in the Cloudflare dashboard**
with the same scopes as the old one. Do **not** revoke the old token
yet.

**Deploy alongside:** append the new token to the sops file with a
`_new` suffix key, so both are present.

```bash
sudo EDITOR=vim sops /etc/linux-skills/cloudflare.token.sops
# Before:
#   cloudflare_token: OLD_TOKEN
# After:
#   cloudflare_token: OLD_TOKEN
#   cloudflare_token_new: NEW_TOKEN
```

**Cut over:** update each consumer to read `cloudflare_token_new`.
Restart the consumer. Verify.

```bash
# Update certbot's credentials file (ini, not sops — certbot does not read sops natively)
sudo sops --decrypt --extract '["cloudflare_token_new"]' \
    /etc/linux-skills/cloudflare.token.sops \
    | sudo tee /etc/letsencrypt/cloudflare.ini > /dev/null
sudo chmod 600 /etc/letsencrypt/cloudflare.ini

# Verify — force a dry-run certbot renewal
sudo certbot renew --dry-run
```

Once verified, swap the keys in the sops file so the live name is
again `cloudflare_token` and the new value is what it holds. This
keeps the config file shape stable across rotations.

```bash
sudo EDITOR=vim sops /etc/linux-skills/cloudflare.token.sops
# After swap:
#   cloudflare_token: NEW_TOKEN    (was cloudflare_token_new)
#   cloudflare_token_old: OLD_TOKEN (kept for grace period)
```

**Revoke (after 7 days, or sooner if Cloudflare's own audit log shows
no traffic on the old token):**

- Delete the old token in the Cloudflare dashboard.
- Remove `cloudflare_token_old` from the sops file.
- Log the rotation.

## 10. The rotation audit log

All rotations append a single line to
`/var/log/linux-skills/secret-rotations.log`. The file is
append-only (`chattr +a`), rotated monthly, and shipped to the
central log host by the same pipeline that ships auth.log.

```bash
sudo install -d -m 0750 -o root -g adm /var/log/linux-skills
sudo touch /var/log/linux-skills/secret-rotations.log
sudo chmod 0640 /var/log/linux-skills/secret-rotations.log
sudo chattr +a /var/log/linux-skills/secret-rotations.log
```

Log line format:

```
<ISO8601 timestamp> <operator> <credential-id> <action> verify=<result>
```

Examples:

```
2026-04-10T09:31:17+03:00 peter backup-gpg-key rotated verify=ok
2026-04-10T14:02:00+03:00 peter mysql-myapp-user rotated-v3 verify=processlist-clean
2026-04-10T15:45:22+03:00 peter cloudflare-api-token rotated verify=certbot-dry-run-ok
```

The `chattr +a` (append-only) flag means even an operator with root
cannot edit past entries without first removing the attribute — a
step that is itself auditable in auth.log. This is not tamper-proof,
but it is tamper-evident, which is the standard to aim for on a
single-host audit trail.

## 11. Dry-run and verification requirements

Every `sk-secret-rotate` invocation must support `--dry-run`, which
prints the steps without writing. Every invocation must require
`--verify-with="<command>"` and must run that command after the
rotation, refusing to mark the rotation "done" unless the verify
command exits zero.

A rotation with no verification step is not a rotation — it is an
unprotected change to a live system. The book's self-healing chapter
makes the same point in a different context: automation that does not
observe its own output is just a faster way to make mistakes.

The rotation script should also refuse to proceed if:

- The audit log is not append-only (tamper-evident guarantee gone).
- The new credential is identical to the old (no-op rotation —
  almost certainly an operator error).
- The grace period on the previous rotation has not yet expired
  (you are about to revoke a credential that might still be in use).

These are guard-rails, not annoyances. Every one of them exists
because a rotation that skipped it caused an incident somewhere.

## Sources

- *Linux System Administration for the 2020s: The Modern Sysadmin
  Leaving Behind the Culture of Build and Maintain* — Kenneth
  Hitchcock (Apress). Chapters on Automation ("idempotent code"),
  Self-Healing, Maintenance ("zero-downtime environments"), and
  Security.
- `age` — https://filippo.io/age
- `sops` — https://getsops.io
- MySQL 8 user management — https://dev.mysql.com/doc/refman/8.0/en/account-management-statements.html
- `chattr(1)` for append-only files — e2fsprogs manual.
- Operational experience running rotations on long-lived Ubuntu
  servers; patterns cross-checked against Google SRE Book chapter on
  managing critical state.
