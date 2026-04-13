---
name: linux-mail-server
description: Manage Ubuntu/Debian mail servers — Postfix, Exim, Dovecot, SPF/DKIM/DMARC email authentication, queue inspection, SMTP testing, TLS. Use for outbound relay servers, full mailboxes, and debugging mail delivery.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Mail Server

## Use when

- Managing Postfix, Exim, Dovecot, queue behavior, or SMTP testing.
- Debugging delivery failures, spam-folder placement, or TLS/authentication issues.
- Updating SPF, DKIM, or DMARC-related server-side behavior.

## Do not use when

- The task is general DNS hosting unrelated to mail service; use `linux-dns-server`.
- The task is generic network reachability without a mail-specific angle; use `linux-network-admin`.

## Required inputs

- The mail stack in use and the affected domain or hostname.
- The symptom: queue growth, spam placement, auth failure, TLS issue, or delivery failure.
- Any target destination, sender identity, or test recipient involved.

## Workflow

1. Identify whether the issue is configuration, queueing, transport, or authentication.
2. Inspect current config, queue state, and relevant logs.
3. Apply the matching workflow below for reputation, submission, queue, or domain changes.
4. Re-test SMTP flow and authentication to confirm the result.

## Quality standards

- Verify with real SMTP tests and queue inspection, not assumption.
- Keep authentication records and mail config aligned.
- Separate transport problems from reputation and policy problems.

## Anti-patterns

- Treating spam-folder placement as only an SMTP connectivity issue.
- Flushing or deleting queue entries before inspecting why they accumulated.
- Mixing DNS, TLS, and relay changes without verifying each layer independently.

## Outputs

- The mail-path diagnosis or change.
- The commands used to verify queue, auth, or delivery state.
- Any remaining reputation, DNS, or relay follow-up needed.

## References

- [`references/postfix-reference.md`](references/postfix-reference.md)
- [`references/email-authentication.md`](references/email-authentication.md)
- [`references/debugging-delivery.md`](references/debugging-delivery.md)

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool (`postfix`, `postqueue`, `postconf`, `swaks`,
`openssl`, `dig`). The `sk-*` scripts in the **Optional fast path** section
are convenience wrappers — never required.

This skill covers running and debugging mail on a Debian/Ubuntu server:
Postfix (default), Exim (alternative), Dovecot for IMAP, and the three
pillars of email authentication — SPF, DKIM, DMARC.

It does **not** own:

- **Firewall rules for SMTP ports** — `linux-firewall-ssl`.
- **DNS records themselves** (MX, SPF, DKIM, DMARC live at the DNS host) —
  but this skill *validates* them.
- **Mail clients** — out of scope.

Informed by *Linux Network Administrator's Guide* (Sendmail/Exim chapters,
translated to Postfix) and modern email authentication practice.

---

## When to use

- Setting up a server to send mail (transactional, notifications, relay).
- Diagnosing "my email goes to spam."
- Checking a mail queue for stuck messages.
- Testing SMTP from the command line (EHLO, STARTTLS, auth, RCPT).
- Validating SPF, DKIM, DMARC records for a domain.
- Inspecting a remote MX's reachability and TLS.

## When NOT to use

- Setting up cloud email (SES, SendGrid, Postmark) — those are API-based.
- Managing DNS records at a registrar — use the registrar's UI or API.

---

## Standing rules

1. **Never run a mail server without SPF + DKIM + DMARC.** Unauthenticated
   mail is treated as spam by every modern receiver.
2. **Never relay mail for third parties without authentication.** Open
   relays are abuse vectors. `mynetworks` in `main.cf` must be
   `127.0.0.0/8` only by default.
3. **Always enable TLS for submission (port 587).** STARTTLS only, reject
   plain auth.
4. **Always validate config before reload.** `postfix check` for Postfix,
   `exim -bV` for Exim.
5. **The queue is the first thing to check on delivery problems.**
6. **Log everything to `/var/log/mail.log`** (syslog) *and*
   `journalctl -u postfix` — both exist on modern Ubuntu.
7. **Reverse DNS (PTR) of the sending IP must match the HELO name.**
   Mismatched PTR is the single biggest reason mail is flagged as spam.

---

## Quick reference — manual commands

### Postfix config and status

```bash
# Validate config — always run before reload
sudo postfix check

# Show effective config (difference from default)
postconf -n

# Reload
sudo postfix reload

# Or full restart if service behavior is stuck:
sudo systemctl restart postfix

# Service status
sudo systemctl status postfix --no-pager
sudo journalctl -u postfix -n 50 --no-pager
sudo tail -f /var/log/mail.log
```

### Queue inspection

```bash
# Show queue
sudo postqueue -p
sudo mailq                                       # alias

# Count by status
sudo postqueue -p | grep -c '^[A-F0-9]'

# Inspect a specific message
sudo postcat -q <queue-id>

# Force a flush (try delivery now)
sudo postqueue -f

# Delete a specific stuck message
sudo postsuper -d <queue-id>

# Delete everything (use with extreme care)
sudo postsuper -d ALL
```

### SMTP testing from the command line

```bash
# Install swaks if needed
sudo apt install swaks

# Full SMTP conversation with TLS and auth
swaks --server mail.example.com \
      --port 587 \
      --from sender@example.com \
      --to recipient@example.org \
      --auth LOGIN \
      --auth-user sender@example.com \
      --tls \
      --header "Subject: test $(date)" \
      --body "test body"

# Just the handshake (no auth, no send)
swaks --server mail.example.com --port 587 --quit-after STARTTLS

# With openssl (lower level):
openssl s_client -starttls smtp -connect mail.example.com:587 -crlf
# Type: EHLO test.example.com
# Then: QUIT
```

### Email authentication checks

```bash
# SPF lookup
dig +short TXT example.com | grep spf1

# DKIM selector (replace "default" with your actual selector)
dig +short TXT default._domainkey.example.com

# DMARC
dig +short TXT _dmarc.example.com

# MX record with priorities
dig +short MX example.com

# Reverse DNS (PTR) — must match HELO
dig +short -x $(curl -s https://api.ipify.org)

# Online checkers (for humans, but record the dig output yourself first):
# - https://mxtoolbox.com
# - Gmail Postmaster Tools
```

Full email-auth deep dive (record syntax, DKIM key generation via
`opendkim-genkey`, DMARC reporting, example DNS zone snippet) — see
[`references/email-authentication.md`](references/email-authentication.md).

---

## Typical workflows

### Workflow: "Our emails are going to spam"

Walk [`references/debugging-delivery.md`](references/debugging-delivery.md).
Condensed:

```bash
# 1. Queue health
sudo postqueue -p

# 2. Reject reason on a deferred message
sudo postcat -q <queue-id> | tail -20

# 3. SPF / DKIM / DMARC present?
dig +short TXT example.com | grep spf1
dig +short TXT default._domainkey.example.com
dig +short TXT _dmarc.example.com

# 4. PTR matches HELO?
dig +short -x $(postconf -h inet_interfaces | awk '{print $1}')
postconf -h myhostname

# 5. TLS working for submission?
swaks --server mail.example.com --port 587 --quit-after STARTTLS
```

### Workflow: "Is port 587 submission working?"

```bash
swaks --server mail.example.com \
      --port 587 \
      --auth LOGIN \
      --auth-user bot@example.com \
      --tls
```

Reports each step (connection, STARTTLS, AUTH, MAIL FROM, RCPT TO, DATA).

### Workflow: "The queue is growing"

```bash
# 1. How bad?
sudo postqueue -p | tail -5   # last line says "Total requests"

# 2. What's stuck and why?
sudo postqueue -p | head -30

# 3. Pick a message and see the specific rejection:
sudo postcat -q <queue-id>

# 4. Common fixes:
#    - Greylist: just wait; Postfix will retry automatically
#    - TLS handshake error: check recipient server's cert, your own
#    - Auth required: fix relay credentials
#    - Relay denied: check mynetworks, smtpd_recipient_restrictions
```

### Workflow: "Add a new domain to an existing Postfix"

```bash
# 1. Edit main.cf — add to mydestination or virtual_mailbox_domains
sudo nano /etc/postfix/main.cf

# 2. If using virtual mailboxes, update the virtual maps:
sudo nano /etc/postfix/virtual_alias_maps
sudo postmap /etc/postfix/virtual_alias_maps

# 3. Validate
sudo postfix check

# 4. Reload
sudo postfix reload

# 5. Test with swaks
```

---

## Troubleshooting / gotchas

- **PTR record mismatch is the #1 spam trigger.** If your server's IP
  reverse-resolves to `vps-12345.provider.net` but Postfix HELOs as
  `mail.example.com`, receivers downgrade you immediately. Fix the PTR
  at the VPS provider.
- **`postfix reload` doesn't reload everything.** Changes to `master.cf`
  require `sudo systemctl restart postfix`. `postfix reload` only
  re-reads `main.cf`.
- **TLS fails on port 465 but works on 587.** Port 465 is implicit TLS
  (SMTPS), 587 is STARTTLS. They need separate service stanzas in
  `master.cf` — enable both.
- **DKIM signs but receivers fail DMARC.** Check alignment: the signing
  domain (`d=`) must match the `From:` header domain (relaxed alignment)
  or exactly (strict). A DKIM-signed bounce that uses the mail server's
  hostname as `d=` won't align with the sender's domain.
- **Postfix is silently deferring.** Look in `/var/log/mail.log` — the
  rejection reason is there. The queue only shows the summary.
- **Dovecot and Postfix disagree about a user.** Postfix's
  `virtual_mailbox_maps` must match Dovecot's `passdb` / `userdb`. Use
  a single source of truth (MySQL, LDAP, or a flat file) and point both
  at it.

---

## References

- [`references/postfix-reference.md`](references/postfix-reference.md) —
  full Postfix reference: `main.cf` parameters, `master.cf`, queue
  management, 3 complete config examples.
- [`references/email-authentication.md`](references/email-authentication.md) —
  SPF, DKIM (with opendkim), DMARC deep dive with DNS record examples.
- [`references/debugging-delivery.md`](references/debugging-delivery.md) —
  decision tree for delivery problems.
- Book: *Linux Network Administrator's Guide* (Kirch & Dawson) — mail
  chapters (Sendmail/Exim, translated to Postfix).
- Book: *Ubuntu Server Guide* (Canonical) — Postfix and Dovecot.
- Man pages: `postfix(1)`, `postconf(5)`, `master(5)`, `postqueue(1)`,
  `postcat(1)`, `swaks(1)`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-mail-server` installs:

| Task | Fast-path script |
|---|---|
| MX records for domain + reachability + TLS + PTR match | `sudo sk-mx-check --domain <d>` |
| Audit SPF, DKIM, DMARC records for a domain | `sudo sk-spf-dkim-dmarc --domain <d>` |
| Postfix/Exim queue inspection grouped by recipient | `sudo sk-mail-queue` |
| Full SMTP conversation tester (wraps swaks) | `sudo sk-smtp-test --host <h> --port 587 --tls` |

These are optional wrappers around `dig`, `swaks`, `postqueue`, and
`openssl s_client`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-mail-server
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-mx-check | scripts/sk-mx-check.sh | no | MX records for a domain, preference order, reachability, reverse DNS, TLS cert of each MX. |
| sk-spf-dkim-dmarc | scripts/sk-spf-dkim-dmarc.sh | no | Audit SPF, DKIM, and DMARC records for a domain; report missing or misaligned. |
| sk-mail-queue | scripts/sk-mail-queue.sh | no | Postfix/Exim queue inspection: depth, oldest, stuck, by recipient domain. |
| sk-smtp-test | scripts/sk-smtp-test.sh | no | Full SMTP handshake tester (EHLO / STARTTLS / AUTH / MAIL FROM / RCPT TO / DATA), reports each step. |
