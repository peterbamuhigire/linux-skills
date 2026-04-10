# Postfix Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Postfix is the default Mail Transfer Agent on Debian and Ubuntu — fast,
secure, sendmail-compatible, and broken into small daemons supervised by the
`master` process. This reference covers the package layout, every commonly-used
`main.cf` parameter, the `master.cf` entries for submission and submissions
ports, queue management, logging, the deferral patterns you will see in
production, and three complete `main.cf` examples you can paste and adapt.

## Table of contents

- [Package layout](#package-layout)
- [The main.cf parameters you will actually touch](#the-maincf-parameters-you-will-actually-touch)
- [The master.cf service table](#the-mastercf-service-table)
- [Submission port 587 (STARTTLS)](#submission-port-587-starttls)
- [Submissions port 465 (implicit TLS / SMTPS)](#submissions-port-465-implicit-tls--smtps)
- [Queue management](#queue-management)
- [Logging: journald and mail.log](#logging-journald-and-maillog)
- [Common deferral and rejection patterns](#common-deferral-and-rejection-patterns)
- [Example 1: outbound relay only (no mailboxes)](#example-1-outbound-relay-only-no-mailboxes)
- [Example 2: full mailbox server with Dovecot SASL](#example-2-full-mailbox-server-with-dovecot-sasl)
- [Example 3: transport through a smart host](#example-3-transport-through-a-smart-host)
- [Safe reload workflow](#safe-reload-workflow)
- [Sources](#sources)

## Package layout

Install the base package and, if you are running a full mailbox server, add
Dovecot for IMAP and SASL:

```bash
sudo apt update
sudo apt install postfix                          # MTA
sudo apt install dovecot-imapd dovecot-pop3d \
                 dovecot-core                     # IMAP + SASL provider
```

Where Postfix puts things on Debian/Ubuntu:

| Path | Purpose |
|---|---|
| `/etc/postfix/main.cf` | Core daemon parameters (the file you edit 90% of the time) |
| `/etc/postfix/master.cf` | Service table — which daemons run on which ports with which overrides |
| `/etc/postfix/sasl/` | SASL passwd maps for relayhost auth (`smtp_sasl_password_maps`) |
| `/etc/postfix/virtual` | Virtual alias map source (hashed with `postmap`) |
| `/etc/postfix/transport` | Per-domain transport overrides |
| `/etc/aliases` | Local aliases (`root: you@example.com`) — rebuild with `newaliases` |
| `/etc/mailname` | Short hostname used by `myorigin = /etc/mailname` |
| `/var/spool/postfix/` | Queue root — chrooted spool for most daemons |
| `/var/spool/postfix/active/` | Messages currently being delivered |
| `/var/spool/postfix/deferred/` | Messages that hit a temporary failure |
| `/var/spool/postfix/hold/` | Held messages (paused by `postsuper -h`) |
| `/var/log/mail.log` | Legacy combined mail log (still populated via rsyslog) |
| `/var/log/mail.err` | Errors and warnings only — easiest file to grep first |

Useful discovery commands:

```bash
postconf -d | wc -l                 # ~900 default parameters — all documented
postconf -n                         # only the ones you have changed
postconf mail_version               # Postfix version
postconf -M                         # dump master.cf programmatically
postfix check                       # validate config before reload
```

## The main.cf parameters you will actually touch

### Identity, interfaces, destinations, relaying

```ini
# FQDN announced in banner and Received: headers. Must match forward AND
# reverse DNS of the sending IP or most receivers will quarantine your mail.
myhostname = mail.example.com
mydomain   = example.com                    # parent domain, usually derived
myorigin   = /etc/mailname                  # domain appended to local-only mail

# Which interfaces smtpd binds to. "all" = public MX; "loopback-only" = pure
# outbound relay that should never accept mail from the internet.
inet_interfaces = all
inet_protocols  = all                       # use "ipv4" if PTR/SPF is v4-only

# Domains for which this host is the FINAL destination. Mail for anyone NOT
# listed is either relayed (if permitted) or rejected. Do NOT put virtual
# domains here — those belong in virtual_mailbox_domains.
mydestination = $myhostname, localhost.$mydomain, localhost

# Clients in mynetworks relay without authenticating. Keep to loopback.
# ANY broader value risks becoming an open relay.
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128

# Explicit relaying — usually empty.
relay_domains =
relayhost     =                             # smart host; [brackets] = no MX lookup
```

### TLS — incoming (smtpd_tls_*) and outgoing (smtp_tls_*)

```ini
# Incoming: "may" = offer STARTTLS on port 25 MX. "encrypt" = require it
# (only correct on submission ports — see master.cf).
smtpd_tls_security_level = may
smtpd_tls_cert_file = /etc/letsencrypt/live/mail.example.com/fullchain.pem
smtpd_tls_key_file  = /etc/letsencrypt/live/mail.example.com/privkey.pem
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtpd_tls_loglevel = 1                     # 1 = summary per connection
smtpd_tls_received_header = yes            # record cipher in Received:
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache

# Outgoing: opportunistic TLS — required default for internet delivery.
# "encrypt" here would break any receiver without STARTTLS.
smtp_tls_security_level = may
smtp_tls_note_starttls_offer = yes
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
```

### SASL — letting authenticated clients relay

```ini
# Delegate SASL to Dovecot (recommended) — it already knows your users.
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth           # relative to Postfix queue directory
smtpd_sasl_auth_enable = yes

# Refuse anonymous and plaintext (outside TLS). Inside TLS, PLAIN/LOGIN is OK.
smtpd_sasl_security_options = noanonymous, noplaintext
smtpd_sasl_tls_security_options = noanonymous
smtpd_sasl_local_domain =
broken_sasl_auth_clients = yes           # tolerate legacy Outlook AUTH quirks
```

### The recipient restriction chain — the single most important knob

`smtpd_recipient_restrictions` is evaluated left-to-right at RCPT TO time. Each
rule either accepts, rejects, or passes ("dunno") the decision to the next rule.
This is where you keep the server from being an open relay:

```ini
smtpd_recipient_restrictions =
    permit_mynetworks,               # trust 127.0.0.0/8
    permit_sasl_authenticated,       # trust logged-in users
    reject_unauth_destination,       # everything else MUST be for us, or bounce
    reject_invalid_hostname,
    reject_non_fqdn_recipient,
    reject_unknown_recipient_domain
```

Rules worth knowing:

| Rule | Meaning |
|---|---|
| `permit_mynetworks` | Allow clients in `$mynetworks` (loopback) |
| `permit_sasl_authenticated` | Allow clients that completed SASL |
| `reject_unauth_destination` | **The anti-open-relay rule — never remove it** |
| `reject_unknown_recipient_domain` | Bounce if recipient domain has no MX/A |
| `reject_non_fqdn_recipient` | Bounce if recipient is not fully qualified |
| `reject_rbl_client zen.spamhaus.org` | Bounce clients listed on an RBL |
| `check_policy_service unix:private/policyd-spf` | Hand off to an SPF policy daemon |

### Virtual domains, limits, and housekeeping

For a single-domain mailbox server where users exist in `/etc/passwd` you do
not need virtual maps — `mydestination` is enough. For multi-domain hosting:

```ini
virtual_mailbox_domains = /etc/postfix/virtual_domains
virtual_mailbox_base    = /var/mail/vhosts
virtual_mailbox_maps    = hash:/etc/postfix/vmailbox
virtual_alias_maps      = hash:/etc/postfix/virtual
virtual_uid_maps        = static:5000
virtual_gid_maps        = static:5000
```

After editing any `hash:` source file, rebuild its `.db` with
`sudo postmap /etc/postfix/virtual` and `systemctl reload postfix`.

```ini
# Limits — always set these explicitly.
message_size_limit    = 26214400      # 25 MB
mailbox_size_limit    = 0             # 0 = unlimited
smtpd_recipient_limit = 100           # max recipients per message
queue_minfree         = 15728640      # refuse new mail if spool < 15 MB free

# Housekeeping
smtpd_banner        = $myhostname ESMTP   # do not leak the version
append_dot_mydomain = no                  # appending domains is the MUA's job
recipient_delimiter = +                   # enables user+tag@example.com
```

## The master.cf service table

`/etc/postfix/master.cf` is the service table. Each row defines a daemon:

```text
service  type  private  unpriv  chroot  wakeup  maxproc  command
```

The key entries on a fresh install are `smtp inet ... smtpd` (the public
port-25 MX), `pickup` and `qmgr` (queue handlers), `smtp unix ... smtp` (the
outbound client), and `local`/`virtual` (local delivery). `postconf -M` dumps
the current table.

The `-o` lines below a service definition override `main.cf` for that daemon
only — the mechanism you use to run a submission service with stricter rules
than the port-25 MX.

### Submission port 587 (STARTTLS)

Port 587 is the **Message Submission** port (RFC 6409). It accepts mail from
authenticated users, requires STARTTLS, and applies stricter restrictions than
the MX port. Uncomment and edit these lines in `master.cf`:

```text
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
  -o smtpd_tls_wrappermode=no
```

What each override does:

- `smtpd_tls_security_level=encrypt` — require STARTTLS. Clients that will not
  upgrade get dropped.
- `smtpd_sasl_auth_enable=yes` — the whole point of this port.
- `smtpd_client_restrictions=permit_sasl_authenticated,reject` — no anonymous
  connections at all. If you did not authenticate, you are rejected before
  RCPT TO.
- `milter_macro_daemon_name=ORIGINATING` — tells milters (OpenDKIM, OpenDMARC)
  that this message is outbound so they sign it instead of verifying it.

### Submissions port 465 (implicit TLS / SMTPS)

Port 465 is **Submissions** (RFC 8314) — implicit TLS from the first byte, no
STARTTLS handshake. Modern clients prefer it because it fails closed on MITM.
Enable in `master.cf`:

```text
smtps      inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
```

The critical override is `smtpd_tls_wrappermode=yes` — that is what flips
smtpd from STARTTLS to implicit TLS.

## Queue management

Postfix has five queues: `incoming`, `active`, `deferred`, `hold`, `corrupt`.
The tools:

```bash
# Show the deferred queue in a human-readable list.
postqueue -p
mailq                            # sendmail-compatible alias

# Print one message by queue ID (envelope + headers + body).
postcat -q D3E5F1A2C4

# Force Postfix to try EVERY deferred message again right now.
postqueue -f

# Force a flush for ONE specific destination domain (often what you really want).
postqueue -s example.com

# Delete a specific message from the queue.
sudo postsuper -d D3E5F1A2C4

# Delete EVERY deferred message (dangerous — you lose them).
sudo postsuper -d ALL deferred

# Put a message on hold (it stays in the queue but will not be retried).
sudo postsuper -h D3E5F1A2C4

# Release a held message.
sudo postsuper -H D3E5F1A2C4

# Count messages per queue.
find /var/spool/postfix/deferred -type f | wc -l
find /var/spool/postfix/active -type f | wc -l
```

Group deferrals by reason to see the real failure pattern:

```bash
postqueue -p | awk '/^[A-F0-9]/{flag=1} flag && /\(.*\)/{print; flag=0}' \
             | sort | uniq -c | sort -rn | head
```

## Logging: journald and mail.log

Postfix logs via syslog. On a default Debian/Ubuntu install rsyslog writes all
mail facility messages to `/var/log/mail.log`, errors to `/var/log/mail.err`,
and warnings to `/var/log/mail.warn`. systemd-journald also captures everything
under the `postfix@-` unit.

```bash
# Tail live mail log.
sudo tail -f /var/log/mail.log

# Errors only — first place to look when something breaks.
sudo tail -n 100 /var/log/mail.err

# Modern journalctl view (works even if rsyslog is not installed).
sudo journalctl -u 'postfix@-*' -f
sudo journalctl -u 'postfix@-*' --since '1 hour ago'

# Grep the log for all activity touching a specific queue ID.
grep D3E5F1A2C4 /var/log/mail.log

# Everything that went to a specific domain.
grep 'to=<.*@example.com>' /var/log/mail.log

# Everything that was deferred or bounced in the last hour.
awk -v d="$(date -d '1 hour ago' '+%b %e %H:%M')" '$0 >= d' /var/log/mail.log \
  | grep -E 'status=(deferred|bounced)'
```

Turn up TLS detail temporarily when you are debugging a handshake:

```bash
sudo postconf -e 'smtpd_tls_loglevel = 2'
sudo postconf -e 'smtp_tls_loglevel = 2'
sudo systemctl reload postfix
# ... reproduce the problem ...
sudo postconf -e 'smtpd_tls_loglevel = 1'
sudo postconf -e 'smtp_tls_loglevel = 1'
sudo systemctl reload postfix
```

## Common deferral and rejection patterns

When `postqueue -p` shows deferred mail, the reason in parentheses is the
first place to look. The patterns you will see over and over:

| Log / queue snippet | What it means | First fix |
|---|---|---|
| `status=deferred (connect to mx.example.com[1.2.3.4]:25: Connection timed out)` | Outbound 25 blocked by your host provider or their firewall | Provider probably blocks outbound 25 — route through a smart host via port 587 |
| `status=deferred (host mx.example.com[1.2.3.4] refused to talk to me: 421 4.7.0 ... try again later)` | Greylisting — receiver wants you to retry later | Wait. Postfix retries automatically. If every domain greylists, check your PTR and SPF |
| `status=deferred (Relay access denied)` | Receiver thinks this message is not for them | Wrong MX, or the recipient domain just lost a DNS record |
| `status=deferred (TLS is required, but was not offered by host ...)` | You set `smtp_tls_security_level=encrypt` and the peer has no STARTTLS | Go back to `may` unless you really need strict TLS |
| `status=deferred (lost connection with mx.example.com[...] while receiving the initial server greeting)` | Peer is hanging up before the banner — usually a per-IP rate limit or a block | Check the receiver's postmaster tools; check RBLs for your sending IP |
| `status=bounced (host ... said: 550 5.7.1 ... Message rejected due to DMARC policy)` | Your DKIM or SPF did not align with the From: domain | See `email-authentication.md` — fix alignment before retrying |
| `status=bounced (host ... said: 550 5.7.1 Client host [1.2.3.4] blocked using zen.spamhaus.org)` | Your sending IP is on a blocklist | Delist via Spamhaus, then check what got you listed |
| `warning: hostname ... does not resolve to address ...: Name or service not known` | Missing or broken reverse DNS (PTR) on your sending IP | Set the PTR at your hosting provider |

## Example 1: outbound relay only (no mailboxes)

A server that sends transactional mail (cron, app notifications) directly from
loopback to the internet. No IMAP, no SASL, no inbound.

```ini
# /etc/postfix/main.cf
smtpd_banner = $myhostname ESMTP
biff = no
append_dot_mydomain = no
compatibility_level = 3.6

myhostname = app01.example.com
mydomain = example.com
myorigin = /etc/mailname
inet_interfaces = loopback-only        # never expose to the internet
inet_protocols = all

mydestination = $myhostname, localhost.$mydomain, localhost
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
relay_domains =
relayhost =                             # direct-to-MX; use Example 3 if 25 is blocked

smtp_tls_security_level = may
smtp_tls_note_starttls_offer = yes
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

message_size_limit = 26214400
mailbox_size_limit = 0
recipient_delimiter = +
```

Rebuild the alias database and reload:

```bash
sudo newaliases
sudo postfix check && sudo systemctl reload postfix
```

## Example 2: full mailbox server with Dovecot SASL

A public MX that accepts mail for `example.com`, lets users log in on 587 and
465 to send outbound, and hands SASL to Dovecot.

```ini
# /etc/postfix/main.cf
smtpd_banner = $myhostname ESMTP
biff = no
append_dot_mydomain = no
compatibility_level = 3.6

myhostname = mail.example.com
mydomain = example.com
myorigin = /etc/mailname
inet_interfaces = all
inet_protocols = all

mydestination = $myhostname, localhost.$mydomain, localhost, example.com
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
relay_domains =
home_mailbox = Maildir/

# TLS
smtpd_tls_cert_file = /etc/letsencrypt/live/mail.example.com/fullchain.pem
smtpd_tls_key_file  = /etc/letsencrypt/live/mail.example.com/privkey.pem
smtpd_tls_security_level = may
smtpd_tls_loglevel = 1
smtpd_tls_received_header = yes
smtpd_tls_protocols = !SSLv2, !SSLv3, !TLSv1, !TLSv1.1
smtp_tls_security_level = may
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

# SASL via Dovecot
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous, noplaintext
smtpd_sasl_tls_security_options = noanonymous
broken_sasl_auth_clients = yes

smtpd_recipient_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination,
    reject_unknown_recipient_domain,
    reject_non_fqdn_recipient

smtpd_client_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_rbl_client zen.spamhaus.org

message_size_limit = 26214400
mailbox_size_limit = 0
smtpd_recipient_limit = 100
recipient_delimiter = +
```

Dovecot-side SASL socket (`/etc/dovecot/conf.d/10-master.conf`):

```text
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode  = 0660
    user  = postfix
    group = postfix
  }
}
```

And enable the submission ports by uncommenting the `submission` and `smtps`
entries in `master.cf` (see above).

## Example 3: transport through a smart host

Many hosting providers (AWS, GCP, DigitalOcean, most home ISPs) block outbound
port 25. Route all mail through an authenticated smart host on 587 instead —
SendGrid, Amazon SES SMTP, Mailgun, or your own relay.

```ini
# /etc/postfix/main.cf  (smart-host outbound)
myhostname = app01.example.com
mydomain = example.com
myorigin = /etc/mailname
inet_interfaces = loopback-only
mydestination = $myhostname, localhost
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128

# Force outbound through this relay. Brackets = no MX lookup. :587 = submission.
relayhost = [smtp.sendgrid.net]:587

smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_tls_security_options = noanonymous

# Smart hosts always offer TLS — require it.
smtp_tls_security_level = encrypt
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
```

Create the credentials file, lock it down, hash it:

```bash
sudo tee /etc/postfix/sasl_passwd >/dev/null <<'EOF'
[smtp.sendgrid.net]:587    apikey:SG.xxxxxxxxxxxxxxxxxxxxxxxx
EOF
sudo chmod 600 /etc/postfix/sasl_passwd
sudo postmap /etc/postfix/sasl_passwd          # builds sasl_passwd.db
sudo postfix check && sudo systemctl reload postfix
```

Test:

```bash
echo "smart host test" | mail -s "hello" you@gmail.com
sudo tail -f /var/log/mail.log
```

You should see `relay=smtp.sendgrid.net[...]:587` and `status=sent`.

## Safe reload workflow

Never reload a mail server without validating first. The four-step ritual:

```bash
sudo postfix check                   # parse main.cf and master.cf
sudo postconf -n                     # review non-default parameters
sudo systemctl reload postfix        # SIGHUP, no downtime
sudo systemctl status postfix        # confirm active (running)
```

If `postfix check` prints anything at all, fix it before reloading. A broken
`main.cf` will refuse to start and drop the queue until you intervene.

## Sources

- *Ubuntu Server Guide Documentation (Linux 20.04 LTS, Focal)* — Canonical,
  2020. Postfix and Dovecot sections.
- *Linux Network Administrator's Guide, 2nd Edition* — chapters on Sendmail
  (Chapter 18) and Exim (Chapter 19), used to translate legacy Sendmail
  concepts into Postfix equivalents.
- Postfix upstream documentation — <https://www.postfix.org/documentation.html>.
- RFC 6409 (Message Submission) and RFC 8314 (Cleartext Considered Obsolete /
  Submissions on port 465).
