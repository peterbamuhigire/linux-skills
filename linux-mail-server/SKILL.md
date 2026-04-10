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

This skill covers running and debugging mail on a Debian/Ubuntu server:
Postfix (default), Exim, Dovecot for IMAP, and the three pillars of email
authentication — SPF, DKIM, DMARC.

It does **not** own:

- **Firewall rules for SMTP ports** — that's `linux-firewall-ssl`.
- **DNS records themselves** (the MX, SPF, DKIM, DMARC records live at the
  DNS host) — but this skill *validates* them.
- **Mail clients** — out of scope.

Informed by *Linux Network Administrator's Guide* (Sendmail/Exim chapters,
translated to Postfix) and modern email authentication best practice.

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
- Managing DNS records at your registrar — use your registrar's UI or API.

---

## Standing rules

1. **Never run a mail server without SPF + DKIM + DMARC.** Unauthenticated
   mail is treated as spam by every modern receiver. `sk-spf-dkim-dmarc`
   audits all three.
2. **Never relay mail for third parties without authentication.** Open
   relays are abuse vectors — `mynetworks` in `main.cf` must be
   `127.0.0.0/8` only by default.
3. **Always enable TLS for submission (port 587).** STARTTLS only, reject
   plain auth. `sk-smtp-test` verifies this.
4. **Always validate config before reload.** `postfix check` for Postfix,
   `exim -bV` for Exim. Scripts enforce this.
5. **The queue is the first thing to check on delivery problems.**
   `sk-mail-queue` shows depth, oldest, stuck.
6. **Log everything to `/var/log/mail.log`** and rotate weekly. `journalctl
   -u postfix` is the modern alternative but the legacy log is still the
   easiest to grep.

---

## Typical workflows

### "Our emails are going to spam"

1. `sk-spf-dkim-dmarc --domain example.com` — audit all three records.
2. Look up the receiver's feedback (Gmail's postmaster tools, etc.).
3. `sk-mx-check --domain example.com` — verify MX records and reverse DNS
   match the sending IP (PTR alignment).
4. `sk-mail-queue` — check for deferred bounces that reveal the real
   rejection reason.

### "Is the submission server working?"

```bash
sk-smtp-test --host mail.example.com --port 587 --user bot@example.com --tls
```

Runs the full EHLO → STARTTLS → AUTH → MAIL FROM → RCPT TO → DATA handshake
and reports each step.

### "The queue is growing"

```bash
sk-mail-queue
```

Output groups stuck messages by recipient domain, shows oldest, and
highlights common rejection classes (greylist, auth, TLS).

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-mail-server
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-mx-check | scripts/sk-mx-check.sh | no | Look up MX records for a domain, show preference order, reachability, reverse DNS match, and TLS cert of each MX. |
| sk-spf-dkim-dmarc | scripts/sk-spf-dkim-dmarc.sh | no | Audit SPF, DKIM, and DMARC records for a domain; report missing or misaligned. |
| sk-mail-queue | scripts/sk-mail-queue.sh | no | Inspect Postfix or Exim queue: depth, oldest message, stuck messages, grouped by recipient domain. |
| sk-smtp-test | scripts/sk-smtp-test.sh | no | Full SMTP handshake tester (EHLO / STARTTLS / AUTH / MAIL FROM / RCPT TO / DATA), reports each step. |

---

## See also

- `linux-network-admin` — reverse DNS (PTR) from the server side.
- `linux-firewall-ssl` — opening 25/465/587/143/993 as needed.
- `linux-log-management` — mail log parsing and retention.
