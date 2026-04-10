# Email Authentication — SPF, DKIM, DMARC

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Modern receivers (Gmail, Microsoft 365, Yahoo, Fastmail, Proton) treat any
unauthenticated mail as spam — or drop it silently. Running an MTA without
SPF, DKIM, and DMARC is running a mail server that nobody receives from. This
reference covers what each standard does, why all three are needed, the exact
DNS syntax, how to generate DKIM keys with OpenDKIM and wire them into
Postfix, how DMARC alignment works, how to read aggregate reports, and the
failures you will hit in the first week.

## Table of contents

- [Why all three are needed](#why-all-three-are-needed)
- [SPF — Sender Policy Framework](#spf--sender-policy-framework)
- [DKIM — DomainKeys Identified Mail](#dkim--domainkeys-identified-mail)
- [Wiring OpenDKIM into Postfix](#wiring-opendkim-into-postfix)
- [DMARC — the policy layer that ties SPF and DKIM together](#dmarc--the-policy-layer-that-ties-spf-and-dkim-together)
- [Reading DMARC aggregate reports](#reading-dmarc-aggregate-reports)
- [Common failures and how to fix them](#common-failures-and-how-to-fix-them)
- [Google Postmaster Tools](#google-postmaster-tools)
- [Complete zone snippet](#complete-zone-snippet)
- [Validation commands](#validation-commands)
- [Sources](#sources)

## Why all three are needed

Each standard answers a different question:

| Standard | Question it answers | What is signed / checked |
|---|---|---|
| **SPF** | "Is this SMTP client allowed to send mail for this envelope-from domain?" | The IP of the connecting SMTP client vs a DNS-published list. Checked against the **envelope-from** (MAIL FROM, the bounce address), *not* the header From: |
| **DKIM** | "Were the headers and body of this message actually written by someone holding the private key for this domain?" | A cryptographic signature in a `DKIM-Signature:` header, verified against a public key in DNS |
| **DMARC** | "Does either the SPF or the DKIM identity **align** with the header From: domain, and what should I do if neither does?" | Alignment of SPF/DKIM identities with the header From:, plus a published policy (`none`/`quarantine`/`reject`) |

SPF alone breaks the moment mail is forwarded (the forwarder's IP is not in
your SPF). DKIM alone can be replayed. DMARC alone is just a policy with
nothing to enforce. You need SPF + DKIM to make **alignment** work, and DMARC
to publish the policy receivers should act on.

## SPF — Sender Policy Framework

SPF is a single DNS TXT record on the envelope-from domain. It lists the IPs
and hostnames authorised to send mail for that domain, followed by a default
action for everything else.

### Record format

```dns
example.com.    IN    TXT   "v=spf1 mx a ip4:203.0.113.10 include:_spf.google.com ~all"
```

Decoded left-to-right:

| Token | Meaning |
|---|---|
| `v=spf1` | Version marker — must be first and exactly this |
| `mx` | Allow every host listed in the domain's MX records |
| `a` | Allow the A/AAAA of the domain itself |
| `ip4:203.0.113.10` | Allow this literal IPv4 address |
| `ip6:2001:db8::1` | Allow this literal IPv6 address |
| `include:_spf.google.com` | Recursively include another domain's SPF record — use for Google Workspace, SES, SendGrid, Mailgun, etc. |
| `exists:%{i}._spf.example.com` | Allow only if the named DNS record exists (advanced) |
| `ptr` | Allow if the PTR of the client matches the domain — **deprecated, do not use** |
| `~all` | **Soft-fail** everything not matched above (receivers mark as suspicious) |
| `-all` | **Hard-fail** everything not matched (receivers reject) |
| `?all` | Neutral — do not use, equivalent to no SPF |
| `+all` | Allow anyone — catastrophic, never use |

### Mechanisms and qualifiers

Every mechanism can be prefixed with a qualifier that controls what happens on
a match:

```text
+   Pass    (default — what you mean when you just write "mx")
-   Fail    (reject)
~   SoftFail (accept but tag)
?   Neutral  (treat as if no SPF)
```

So `-mx` means "fail if the client is one of my MXes" (nonsense) and `~all`
means "soft-fail everything else."

### The 10-lookup limit

An SPF record requiring more than **10 DNS lookups to fully evaluate** is
invalid (PermError). Every `include`, `a`, `mx`, `exists`, `redirect` counts.
Stacking several provider includes blows the budget fast.

### A realistic SPF for a small business

```dns
example.com.  IN  TXT  "v=spf1 mx ip4:203.0.113.10 include:_spf.google.com include:amazonses.com ~all"
```

`mx` = your own mail server; `ip4:` = a secondary sender (cron box);
`include:` = Google Workspace and SES for their senders; `~all` = softfail
everything else. Move to `-all` once the DMARC reports come back clean.

## DKIM — DomainKeys Identified Mail

DKIM adds a cryptographic signature header to outbound mail. The receiver
retrieves the public key from DNS (`<selector>._domainkey.<domain>`), hashes
the signed headers plus the body, and verifies the signature.

### What a DKIM-Signature header looks like

```text
DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=example.com; s=mail;
    t=1712750000; bh=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=;
    h=From:To:Subject:Date:Message-ID:MIME-Version:Content-Type;
    b=YGk4...signature bytes...==
```

| Tag | Meaning |
|---|---|
| `v=1` | Version |
| `a=rsa-sha256` | Signature algorithm — `rsa-sha256` or `ed25519-sha256` |
| `c=relaxed/relaxed` | Header/body canonicalisation (relaxed tolerates whitespace changes in transit) |
| `d=example.com` | Signing domain — **this is the identity that DMARC aligns against** |
| `s=mail` | Selector — tells the receiver which DNS key to fetch |
| `h=From:To:...` | Which headers were signed (signing `From:` is mandatory) |
| `bh=...` | Body hash |
| `b=...` | The signature itself |

The selector lets you rotate keys without downtime: publish `s=mail2`, sign
with it, wait a day, remove the old `s=mail` key.

### Generating a key with opendkim-genkey

```bash
sudo apt install opendkim opendkim-tools
sudo mkdir -p /etc/opendkim/keys/example.com
cd /etc/opendkim/keys/example.com
sudo opendkim-genkey -b 2048 -d example.com -s mail
sudo chown -R opendkim:opendkim /etc/opendkim/keys
sudo chmod 600 mail.private
```

Result: `mail.private` (secret key, mode 600) and `mail.txt` (public key
formatted as a DNS TXT record).

### The DNS record format

`mail.txt` will contain something like:

```dns
mail._domainkey  IN  TXT  ( "v=DKIM1; h=sha256; k=rsa; "
    "p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw..."
    "...QIDAQAB" )
```

Flatten it (most DNS providers want one unquoted string) and publish:

- **Name:** `mail._domainkey.example.com`
- **Type:** `TXT`
- **Value:** `v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkq...QIDAQAB`

### Selector conventions

Use something descriptive: `mail`, `ses`, `mailgun`, `202504`, `key1`.
Date-stamped selectors make rotation obvious. Different sending sources
should use different selectors so one compromised key does not invalidate
everything. Keys under 2048 bits are flagged as weak by Gmail — always 2048.

## Wiring OpenDKIM into Postfix

OpenDKIM runs as a milter. Postfix sends every outbound message through it,
OpenDKIM signs it, Postfix sends the signed version out.

### /etc/opendkim.conf

```ini
# Logging
Syslog                   yes
SyslogSuccess            yes
LogWhy                   yes

# Run as the opendkim user with a UNIX socket Postfix can reach.
UserID                   opendkim
UMask                    007
Socket                   local:/var/spool/postfix/opendkim/opendkim.sock
PidFile                  /run/opendkim/opendkim.pid

# Canonicalisation and signing mode.
Canonicalization         relaxed/relaxed
Mode                     sv                 # s = sign, v = verify
SubDomains               no
OversignHeaders          From

# Key tables.
KeyTable                 refile:/etc/opendkim/key.table
SigningTable             refile:/etc/opendkim/signing.table
ExternalIgnoreList       refile:/etc/opendkim/trusted.hosts
InternalHosts            refile:/etc/opendkim/trusted.hosts
```

### /etc/opendkim/signing.table

```text
# Every address @example.com signs with the key named "example-mail"
*@example.com     example-mail
```

### /etc/opendkim/key.table

```text
# Key name        domain:selector:path-to-private-key
example-mail      example.com:mail:/etc/opendkim/keys/example.com/mail.private
```

### /etc/opendkim/trusted.hosts

```text
127.0.0.1
localhost
::1
example.com
*.example.com
```

### Socket directory for the Postfix chroot

```bash
sudo mkdir -p /var/spool/postfix/opendkim
sudo chown opendkim:postfix /var/spool/postfix/opendkim
sudo chmod 750 /var/spool/postfix/opendkim
```

### Tell Postfix to use the milter

```bash
sudo postconf -e 'milter_protocol = 6'
sudo postconf -e 'milter_default_action = accept'
sudo postconf -e 'smtpd_milters = local:/opendkim/opendkim.sock'
sudo postconf -e 'non_smtpd_milters = local:/opendkim/opendkim.sock'
sudo systemctl restart opendkim
sudo systemctl reload postfix
```

Send a test message and grep the headers:

```bash
echo "test" | mail -s "dkim test" you@gmail.com
# Open the message in Gmail → Show Original → expect ARC-Authentication-Results
# to show dkim=pass header.d=example.com
```

## DMARC — the policy layer that ties SPF and DKIM together

DMARC publishes, on the **header From: domain**, a policy telling receivers
what to do with mail that fails alignment, plus where to send reports.

### Record format

```dns
_dmarc.example.com.  IN  TXT  "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; adkim=s; aspf=s; pct=100; fo=1"
```

| Tag | Meaning |
|---|---|
| `v=DMARC1` | Version — must be first and exactly this |
| `p=none` | Monitor only. Start here for the first month — no mail is affected |
| `p=quarantine` | Send failing mail to spam. Second stage — once reports show DKIM and SPF are stable |
| `p=reject` | Reject failing mail outright. Final stage — the goal |
| `sp=reject` | Subdomain policy — overrides `p` for `*.example.com` |
| `rua=mailto:...` | Aggregate reports (daily XML summaries) — you WILL want these |
| `ruf=mailto:...` | Failure / forensic reports (per-message, sensitive) — rarely honoured |
| `adkim=s` | Strict DKIM alignment — `d=` must equal the From: domain exactly |
| `adkim=r` | Relaxed DKIM alignment — `d=` may be a parent/subdomain (default) |
| `aspf=s` | Strict SPF alignment — envelope-from must equal From: exactly |
| `aspf=r` | Relaxed SPF alignment — organisational domain match is enough (default) |
| `pct=100` | Apply the policy to this percentage of mail (ramp-up tool) |
| `fo=1` | Failure reporting options — `1` = report on any SPF/DKIM failure |

### Alignment in one paragraph

"Alignment" is the only DMARC concept that trips people up. SPF aligns if the
domain in MAIL FROM (the envelope) matches the domain in the header From:.
DKIM aligns if the `d=` in the DKIM-Signature matches the header From:. In
**relaxed** mode (the default, `adkim=r` / `aspf=r`) a subdomain match counts
— `d=mail.example.com` aligns with `From: user@example.com`. In **strict**
mode (`s`) they must be identical. DMARC passes if **either** SPF or DKIM
aligns. You only need both to fail for DMARC to fail.

### Ramp-up plan

1. **Week 1 — `p=none`, `pct=100`, `rua=mailto:...`**. No mail is affected.
   Reports tell you what is actually sending as your domain.
2. **Week 2-3**. Fix everything you find. Add missing sources to SPF.
   Enable DKIM on every sender.
3. **Week 4 — `p=quarantine; pct=25`**. Quarantine 25% of failing mail.
4. **Week 5 — `p=quarantine; pct=100`**. Quarantine everything.
5. **Week 6 — `p=reject`**. Goal reached.

Gmail and Microsoft 365 now **require** at least `p=quarantine` on bulk
senders. `p=none` no longer qualifies as "DMARC in use" for their thresholds.

## Reading DMARC aggregate reports

Aggregate reports arrive daily, one ZIP/GZIP per reporting provider,
containing an XML summary of everything they saw claiming to be from your
domain. The interesting bits are `<record>` blocks with a `<source_ip>`,
`<count>`, `<policy_evaluated>` (disposition, dkim, spf) and `<auth_results>`.

What to look for:

- **`source_ip` values you do not recognise** — something is spoofing you, or
  a legitimate sender you forgot about.
- **`dkim=fail` on mail you expect to pass** — check the selector, check
  whether a forwarder is modifying headers.
- **`spf=fail` but `dkim=pass`** — forwarding. DKIM survives forwarding, SPF
  does not. This is exactly why you need both.
- **`disposition=quarantine` or `reject`** — mail that was acted on. Fix before
  it becomes lost sales.

Paid tools (dmarcian, Postmark DMARC Digest, URIports, EasyDMARC) parse the
XML and give you dashboards. For a free option, `parsedmarc` is open-source
and dumps reports to Elasticsearch or a file.

## Common failures and how to fix them

| Symptom | Cause | Fix |
|---|---|---|
| Gmail shows "no encryption" / no DKIM badge | No DKIM or wrong selector in DNS | Verify `dig +short TXT mail._domainkey.example.com` returns the key |
| DMARC aggregate shows `dkim=fail` for all mail | Signed body was modified in transit (whitespace, footer injection) | Use `c=relaxed/relaxed` canonicalisation; stop mailing-list footers from modifying your body |
| DMARC shows `spf=softfail` for your own IPs | SPF does not list the IP — often Amazon SES or a new VPS | Add to SPF or include the provider's SPF |
| SPF PermError | More than 10 DNS lookups, or syntax error | Flatten includes, remove `ptr`, run `dig TXT example.com` and count |
| DMARC shows `p=quarantine` but `disposition=none` | `pct` is less than 100, or receiver is in report-only mode | Raise `pct`; wait for the receiver |
| Mail from forwarder fails DMARC | Forwarder rewrote From: or broke DKIM body | You cannot fix forwarders — publish `p=quarantine` only once you see the damage |
| `p=reject` and mail to a mailing list vanishes | Mailing lists rewrite headers, which breaks DKIM and SPF | Use ARC-aware lists, or stay at `p=quarantine` |
| Gmail Postmaster Tools shows "IP reputation: bad" | Your sending IP is warmed up badly or sent spam | Slow your ramp, clean your list, warm the IP gradually |

## Google Postmaster Tools

Google publishes per-domain delivery telemetry at
<https://postmaster.google.com>. It is the single most useful feedback loop
for any domain sending to Gmail.

Setup:

1. Add your domain.
2. Prove ownership with a DNS TXT record Google provides.
3. Wait 24-48 hours for the first data.

Dashboards you get:

- **Spam Rate** — user-reported spam as a percentage of inbox-delivered mail.
  Keep this under 0.1%. Above 0.3% and Gmail starts deprioritising you.
- **IP Reputation** — High / Medium / Low / Bad per sending IP.
- **Domain Reputation** — same scale, aggregated across IPs.
- **Authentication** — pass rates for SPF, DKIM, DMARC.
- **Encryption** — percentage of mail delivered over TLS (should be 100%).
- **Delivery Errors** — rejections grouped by reason.

Microsoft has an equivalent at <https://sendersupport.olc.protection.outlook.com/snds/>
(SNDS for IP health, JMRP for junk feedback).

## Complete zone snippet

A working zone showing SPF, DKIM, and DMARC together. Replace the placeholders
and paste into your DNS provider.

```dns
; ----- SPF -----
; Authorise:
;   - your MX (the mail.example.com host)
;   - Google Workspace for staff
;   - Amazon SES for app transactional mail
; Everything else softfails while you watch the DMARC reports.
example.com.                  IN  TXT   "v=spf1 mx include:_spf.google.com include:amazonses.com ~all"

; ----- DKIM -----
; Key for outbound mail signed by the server's own OpenDKIM instance.
mail._domainkey.example.com.  IN  TXT   "v=DKIM1; h=sha256; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw...QIDAQAB"

; Google Workspace will ask you to add a second DKIM key under its own selector.
google._domainkey.example.com. IN TXT   "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb..."

; ----- DMARC -----
; Start at p=none for the first month; move to quarantine once reports are clean.
_dmarc.example.com.           IN  TXT   "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; adkim=r; aspf=r; pct=100; fo=1"

; Optional but recommended: an MX for the DMARC mailbox domain that accepts
; reports (or forward dmarc@example.com to an inbox somewhere).
```

## Validation commands

```bash
# SPF
dig +short TXT example.com | grep spf1

# DKIM — selector "mail"
dig +short TXT mail._domainkey.example.com

# DMARC
dig +short TXT _dmarc.example.com

# Send yourself a test and inspect the auth headers at the receiver.
swaks --to you@gmail.com --from notifications@example.com \
      --server mail.example.com:587 --tls --auth-user you --auth-password REDACTED

# Offline SPF evaluation for a given sender IP.
python3 -m spf 203.0.113.10 notifications@example.com example.com

# OpenDKIM test mode — sign a file and show the signature it would emit.
opendkim-testkey -d example.com -s mail -vvv

# Fetch and verify a DKIM public key from DNS.
opendkim-testkey -d example.com -s mail -k /etc/opendkim/keys/example.com/mail.private
```

Third-party web checkers worth bookmarking:

- <https://mxtoolbox.com/spf.aspx>
- <https://mxtoolbox.com/dkim.aspx>
- <https://dmarcian.com/dmarc-inspector/>
- <https://www.mail-tester.com/> — send a message, get a 0-10 score with each
  reason broken out.

## Sources

- *Ubuntu Server Guide Documentation (Linux 20.04 LTS, Focal)* — Canonical,
  2020. Postfix and Dovecot sections, SMTP-AUTH and TLS configuration.
- *Linux Network Administrator's Guide, 2nd Edition* — MTA fundamentals and
  the envelope-vs-header distinction that makes SPF alignment make sense.
- RFC 7208 (SPF), RFC 6376 (DKIM), RFC 7489 (DMARC), RFC 8617 (ARC).
- Google Bulk Sender Guidelines (2024) — the threshold that moved "nice to
  have" DMARC to "required."
