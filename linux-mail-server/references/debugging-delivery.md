# Debugging Mail Delivery

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

"My email isn't being delivered" is one of the most common — and most
frustrating — sysadmin tasks, because the failure can sit anywhere between
your application's `sendmail` call and the receiving user's spam folder. This
reference is a decision tree: start at the top, work down, and at each step
run the command shown against your own server.

## Table of contents

- [The decision tree](#the-decision-tree)
- [Step 1 — check the live log](#step-1--check-the-live-log)
- [Step 2 — check the queue](#step-2--check-the-queue)
- [Step 3 — classify the failure](#step-3--classify-the-failure)
- [Local config failures](#local-config-failures)
- [Authentication and TLS failures](#authentication-and-tls-failures)
- [DNS and MX failures](#dns-and-mx-failures)
- [SPF, DKIM, DMARC failures](#spf-dkim-dmarc-failures)
- [Receiver-side rejections (5xx) and deferrals (4xx)](#receiver-side-rejections-5xx-and-deferrals-4xx)
- [Greylisting](#greylisting)
- [Blacklists](#blacklists)
- [Rate limiting](#rate-limiting)
- [SMTP conversation testing with swaks](#smtp-conversation-testing-with-swaks)
- [Raw STARTTLS handshake with openssl](#raw-starttls-handshake-with-openssl)
- [DNS checks with dig](#dns-checks-with-dig)
- [SMTP response code cheatsheet](#smtp-response-code-cheatsheet)
- [When to trust your logs vs the receiver's postmaster tools](#when-to-trust-your-logs-vs-the-receivers-postmaster-tools)
- [Sources](#sources)

## The decision tree

```text
1. Is mail leaving your server?     journalctl -u 'postfix@-*' ; postqueue -p
   ├─ nothing logged    → app never called sendmail, fix the app
   ├─ status=sent       → it left, problem is receiver-side → step 3
   ├─ status=deferred   → stuck in queue → step 2
   └─ status=bounced    → permanent failure → step 3

2. Why is it deferred?               postcat -q <queue_id>
   ├─ "Connection timed out" :25    → ISP blocks 25, use smart host
   ├─ "Relay access denied"          → wrong MX or receiver config
   ├─ "TLS handshake failure"        → peer cert / protocol mismatch
   ├─ "4.7.0 try again later"        → greylist, wait
   └─ "4.7.1 blocked using ..."      → RBL, see Blacklists

3. Did receiver reject 5xx or accept-then-drop?   grep <queue_id> mail.log
   ├─ 550 DMARC policy               → fix SPF/DKIM alignment
   ├─ 550 Spamhaus / 554             → blacklist / reputation
   ├─ 550 no such user               → bad address
   ├─ 250 sent, landed in spam       → reputation / content
   └─ Accepted but never arrived     → recipient's spam folder first
```

## Step 1 — check the live log

```bash
sudo journalctl -u 'postfix@-*' --since '1 hour ago'
sudo journalctl -u 'postfix@-*' -f       # stream live
sudo tail -f /var/log/mail.log           # legacy combined log
sudo tail -n 100 /var/log/mail.err       # errors only — fastest to spot breakage
```

Look for one of these three patterns:

| Pattern | Meaning | Next step |
|---|---|---|
| `status=sent` | Postfix handed the message off successfully | Problem is on receiver side — step 3 |
| `status=deferred` | Temporary failure, will retry | Step 2 — read the reason in parentheses |
| `status=bounced` | Permanent failure, returned to sender | Step 3 — decode the 5xx code |

If you see **nothing** relating to your attempted send, your application did
not actually invoke Postfix. Check the app's logs, not the mail server's.

## Step 2 — check the queue

```bash
postqueue -p                             # summary of the deferred queue
postcat -q D3E5F1A2C4                    # dump one message by queue ID
sudo postqueue -f                        # force retry of ALL deferred (use sparingly)
sudo postqueue -s example.com            # retry just one destination domain

# Group deferrals by reason, most common first.
postqueue -p | awk '/^[A-F0-9]/{flag=1} flag && /\(.*\)/{print; flag=0}' \
             | sort | uniq -c | sort -rn | head
```

Do **not** run `postsuper -d ALL` to "clear the queue" as a first step — you
lose every stuck message with no forensic trail.

## Step 3 — classify the failure

Every log line for one delivery attempt shares the same queue ID. Grep it to
see the full lifecycle (`cleanup` → `smtpd` → `qmgr` → `smtp` → `status=`):

```bash
grep D3E5F1A2C4 /var/log/mail.log
```

The last line tells you who said what.

## Local config failures

- `warning: /etc/postfix/main.cf, line NN: missing '=' after attribute name`
  → Broken parameter. Run `sudo postfix check` for line numbers.
- `fatal: parameter inet_interfaces: no local interface found for ::1`
  → You listed IPv6 but disabled IPv6 kernel support. Set `inet_protocols = ipv4`.
- `Temporary lookup failure` → DNS resolver broken. Test with
  `dig @1.1.1.1 mx gmail.com`.

Fix-then-verify loop: `sudo postfix check && sudo systemctl reload postfix &&
sudo systemctl status postfix`.

## Authentication and TLS failures

```text
SASL authentication failed; cannot authenticate to server ...
SASL authentication failed: no mechanism available
```

Smart host credentials wrong, or Postfix is advertising an incompatible
mechanism. Verify `/etc/postfix/sasl_passwd`, rebuild with
`sudo postmap /etc/postfix/sasl_passwd`, then reload. For deeper detail set
`smtp_tls_loglevel = 2` temporarily.

TLS-specific — `TLS library problem: ... certificate verify failed`:

- System CA bundle stale → `sudo update-ca-certificates`.
- `smtp_tls_security_level = verify` with an incomplete peer chain → drop to
  `may` unless there is a real reason.
- Your own cert expired → `sudo certbot renew && sudo systemctl reload postfix`.

## DNS and MX failures

`Host or domain name not found ... type=MX` means the recipient's domain has
no MX, or your resolver cannot reach DNS.

```bash
dig +short MX example.com                # recipient's MX
dig MX example.com +noall +answer        # with TTL
dig @1.1.1.1 mx example.com              # compare against a known-good resolver

# Forward / reverse DNS sanity on YOUR server.
dig +short A mail.example.com            # must resolve to your sending IP
dig +short -x 203.0.113.10                # PTR must match $myhostname
postconf myhostname                      # what Postfix announces in EHLO
```

A forward/reverse mismatch — you announce `mail.example.com` but PTR says
`vps-203-0-113-10.provider.com` — causes silent spam-folder placement even
when every other check passes.

## SPF, DKIM, DMARC failures

Full details live in `email-authentication.md`. For debugging, the short form:

```bash
dig +short TXT example.com | grep spf1
dig +short TXT mail._domainkey.example.com
dig +short TXT _dmarc.example.com
```

Open a delivered message at the receiver → "Show original" → read the
`Authentication-Results:` header. If any of these show `fail`, see
`email-authentication.md`. Quick classifier:

| Result | Cause | Fix |
|---|---|---|
| `spf=neutral` | No SPF record at all | Publish one |
| `spf=softfail` | Your sending IP is not in SPF | Add the IP or provider include |
| `dkim=neutral` | No DKIM-Signature header | Enable OpenDKIM |
| `dkim=fail` | Signature present but does not verify | Wrong selector, body modified, or key corrupt in DNS |
| `dmarc=fail` | Neither SPF nor DKIM aligned with From: | Align — usually DKIM `d=` ≠ From: domain |

## Receiver-side rejections (5xx) and deferrals (4xx)

The receiver's error message is the best source of truth. Pull 4xx/5xx
replies with `grep -E 'said: (4|5)[0-9][0-9]' /var/log/mail.log | tail`.
Common ones:

- **550 5.7.1 rejected due to DMARC policy** — fix SPF/DKIM alignment.
- **550 5.7.1 blocked using zen.spamhaus.org** — RBL hit, see Blacklists.
- **550 5.1.1 ... does not exist** — recipient typo, not your problem.
- **550 5.7.26 Unauthenticated email is not accepted** — Gmail/M365 DMARC.
- **554 5.7.1 Access denied** — blocklisted at IP or domain.
- **421 4.7.0 Try again later** — temporary rate limit or greylist.

## Greylisting

A `451 4.7.1 Greylisted` deferral means the receiver is asking you to retry.
Postfix retries automatically — **wait**. If every domain greylists you on
every message, your sender reputation is broken (check SPF/DKIM/DMARC/PTR).
To retry faster while debugging, lower `minimal_backoff_time`, `queue_run_delay`
via `postconf -e` and reload, then revert.

## Blacklists

Receiver rejection like "blocked using zen.spamhaus.org" means your IP is on
an RBL. Look it up directly:

```bash
# Reverse the IP octets + the RBL domain. Any answer = listed.
dig +short 10.113.0.203.zen.spamhaus.org

# Check many lists at once via the web:
#   https://mxtoolbox.com/blacklists.aspx
#   https://check.spamhaus.org/        (delisting form)
```

Delisting is usually self-service — you attest you fixed the problem, and
Spamhaus removes you within minutes. Do **not** pay any "blacklist removal"
service — they are scams.

If you are listed unexpectedly: check for a spam run in `/var/log/mail.log`,
audit `mynetworks` (must be `127.0.0.0/8` only), check `who -u`, `last`, and
`journalctl -u ssh` for unauthorised logins.

## Rate limiting

Gmail, Microsoft 365, and Yahoo silently throttle new senders with messages
like `421 4.7.28 ... unusual rate of unsolicited mail`. Slow down — IP warmup
takes 2-4 weeks. Cap concurrency and add a delay:

```bash
sudo postconf -e 'default_destination_concurrency_limit = 2'
sudo postconf -e 'smtp_destination_rate_delay = 1s'
sudo systemctl reload postfix
```

Check Google Postmaster Tools "Spam Rate" — above 0.3% and throttling stays
until the complaint rate drops.

## SMTP conversation testing with swaks

`swaks` is the Swiss Army knife of SMTP testing. Install it and use it
instead of raw telnet whenever possible.

```bash
sudo apt install swaks
```

```bash
# Plain test — port 25, no auth.
swaks --to you@example.com --from notifications@mydomain.com \
      --server mail.mydomain.com:25

# Submission — 587 with STARTTLS and SASL.
swaks --to you@gmail.com --from bot@mydomain.com \
      --server mail.mydomain.com:587 --tls \
      --auth LOGIN --auth-user bot@mydomain.com --auth-password 'S3cret!' \
      --header "Subject: swaks test $(date)" --body "Hello from swaks."

# Submissions — 465 implicit TLS.
swaks --to you@gmail.com --from bot@mydomain.com \
      --server mail.mydomain.com:465 --tls-on-connect \
      --auth LOGIN --auth-user bot@mydomain.com --auth-password 'S3cret!'
```

Flags worth knowing: `--tls` (require STARTTLS), `--tls-on-connect` (implicit
TLS), `--auth LOGIN`/`PLAIN` (force mechanism), `--ehlo` (override EHLO name),
`--show-raw-text` (print exact bytes). Swaks labels both sides of the
conversation; when a step fails it is obvious which one.

## Raw STARTTLS handshake with openssl

When swaks is not enough — you need the actual certificate chain or a
TLS-level failure — use `openssl s_client`:

```bash
# Port 587 STARTTLS
openssl s_client -starttls smtp -crlf -connect mail.example.com:587 -servername mail.example.com

# Port 465 implicit TLS
openssl s_client -crlf -connect mail.example.com:465 -servername mail.example.com

# Port 25 MX STARTTLS (testing someone else's inbound)
openssl s_client -starttls smtp -crlf -connect mx.gmail.com:25

# Expiry / subject only
echo | openssl s_client -starttls smtp -connect mail.example.com:587 2>/dev/null \
    | openssl x509 -noout -dates -subject -issuer
```

Check: **certificate chain** (missing intermediates are the #1 MTA cert bug),
**SAN matches hostname**, **protocol TLSv1.2 or TLSv1.3**, **cipher is AEAD
(AES-GCM / CHACHA20)**, **verify return code 0 (ok)**.

## DNS checks with dig

```bash
dig MX example.com +noall +answer                       # recipient's MX
dig TXT _dmarc.example.com +noall +answer               # DMARC
dig TXT mail._domainkey.example.com +noall +answer      # DKIM
dig A mail.example.com +noall +answer                   # forward
dig -x 203.0.113.10 +noall +answer                      # reverse / PTR
dig @1.1.1.1 mx example.com                             # bypass local resolver
nc -vz mx.example.com 25                                # port reachable?
nc -vz mx.example.com 587
```

## SMTP response code cheatsheet

| Code | Meaning |
|---|---|
| 220 | Service ready (banner) |
| 235 | Authentication successful |
| 250 | Command OK / message accepted |
| 334 | Server challenge during AUTH |
| 354 | Start mail input (after DATA), end with `.` on its own line |
| 421 | Service not available — **temporary**, retry |
| 450/451/452 | Mailbox / local error / storage — **temporary**, retry |
| 454 | Temporary authentication failure |
| 500/501/502/503/504 | Syntax / command — **permanent** |
| 530 | Authentication required |
| 535 | Authentication credentials invalid |
| 550 | Mailbox unavailable, or policy rejection |
| 552 | Message size exceeds limit |
| 553 | Mailbox name not allowed |
| 554 | Transaction failed (generic) |

**4xx = retry later**, **5xx = give up and bounce**. Postfix handles this
automatically.

## When to trust your logs vs the receiver's postmaster tools

Your logs tell you what **left the building** — Postfix accepted it, TLS
succeeded, the receiver returned `250 Ok: queued`. They cannot tell you
whether it landed in inbox or spam, whether the receiver silently scored and
dropped it, or what your reputation looks like. For that, use the receiver's
postmaster tools:

- **Gmail** → <https://postmaster.google.com>
- **Microsoft 365** → SNDS + JMRP via <https://sendersupport.olc.protection.outlook.com/>
- **Yahoo** → <https://senders.yahooinc.com/>

If Postfix says `status=sent` but the user says "I never got it," the next
place to look is the receiver's postmaster dashboard, not your own logs.

## Sources

- *Ubuntu Server Guide Documentation (Linux 20.04 LTS, Focal)* — Canonical,
  2020. Postfix log viewing, increasing daemon verbosity, SASL debug output.
- *Linux Network Administrator's Guide, 2nd Edition* — Chapter 18 (Sendmail)
  and Chapter 19 (Exim) on queue management and log files, translated to
  Postfix terminology.
- Postfix upstream docs — <https://www.postfix.org/DEBUG_README.html>.
- `swaks(1)` manual page.
