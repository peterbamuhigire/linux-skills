# Step 5 — currentness and support review, pass 2

Access date for every row: **2026-10-31**. Method: the Kaizen currentness gate, primary sources
only, fetched with the web reader; page content treated as data. This supplements the
29 October matrix in `docs/kaizen/2026-10-engine-kaizen/currency.md` (still inside its
5 November review) and does not repeat rows that were not re-checked. A fetched page shows the
state of that page, not of any host: host applicability is `NOT_ASSESSED` throughout.

## Re-checked and new rows

| ID | Claim | Source (primary) | Support state | Limitation | Review by |
|---|---|---|---|---|---|
| P2-C01 | Debian 13 "trixie" is stable; latest point release 13.7 dated 2026-09-12; Debian 12 "bookworm" is oldstable. | [Debian releases](https://www.debian.org/releases/) | `verified` for page state | Page shows both "last modified" 2026-06-17 and "last built" 2026-09-23; the reader flagged the mismatch with the 13.7 date. Oldstable support end not shown. | 2026-11-30 |
| P2-C02 | RHEL 10.2 and 9.8 reached general availability on 2026-05-19; 10.1 and 9.7 on 2025-11-11. | [Red Hat release dates](https://access.redhat.com/articles/red-hat-enterprise-linux-release-dates) | `verified` | Lifecycle phase of a given minor release not read. | 2026-11-30 |
| P2-C03 | Nginx: mainline 1.31.8, stable 1.30.6 (the Fedora 44 package row checked on 29 October is also 1.30.6). | [nginx download page](https://nginx.org/en/download.html) | `verified` for listed versions | Page shows no release dates. Debian 13 and RHEL streams ship older branches (1.26 per the 29 October record): upstream version is not the installed version. | 2026-11-30 |
| P2-C04 | Apache HTTP Server 2.4.69, released 2026-10-01, is the latest 2.4 release. | [Apache download page](https://httpd.apache.org/download.cgi) | `verified` | The 29 October Fedora row (2.4.69-1.fc44) matches. Debian stable-security carried 2.4.69-1~deb13u1 on 29 October. | 2026-11-30 |
| P2-C05 | PHP: 8.2 security-only to 2026-12-31; 8.3 security-only to 2027-12-31; 8.4 active to 2026-12-31, security to 2028-12-31; 8.5 active to 2027-12-31, security to 2029-12-31. | [php.net supported versions](https://www.php.net/supported-versions.php) | `verified` | 8.4 leaves active support and 8.2 reaches end of life on the same day, 2026-12-31. RHEL 10 initial PHP 8.3 and Debian 13 PHP 8.4 follow distro lifecycles, not these dates. | 2026-12-15 |
| P2-C06 | PostgreSQL supported majors 14 to 18; current minors 14.24, 15.19, 16.15, 17.11, 18.6; final releases 14 on 2026-11-12, 15 on 2027-11-11, 16 on 2028-11-09, 17 on 2029-11-08, 18 on 2030-11-14; 13 and older unsupported. | [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/) | `verified` | Project support only. Vendor back-port windows differ and were not assessed. PostgreSQL 14 ends in 12 days: re-review in November. | 2026-11-16 |
| P2-C07 | RHEL 9 `postgresql` module streams: 13 (initial; plain install), 15 (9.2), 16 (9.4), 18 (9.8); one stream installable at a time. | [Red Hat RHEL 9, Using PostgreSQL](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_using_database_servers/using-postgresql_configuring-and-using-database-servers) | `verified` (page read to character 100000 of 113450) | Used to rewrite the PostgreSQL install guidance. RHEL 10 packaging not read for this row. | 2026-11-30 |
| P2-C08 | MySQL 8.0 community edition reached end of life in April 2026 (8.0.46 final); MySQL 8.4 is the LTS successor under Oracle's lifetime policy (five years premier, three extended). | [MySQL 8.0 release notes](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/); [Oracle MySQL blog on LTS](https://dev.mysql.com/blog-archive/introducing-mysql-innovation-and-long-term-support-lts-versions/) via search extract | `partial` | An exact official end date for 8.4 was not found; "about April 2032" appeared only in a third-party slide deck and is not admitted. Engine content names no 8.0 end-of-life dates. | 2026-12-15 |
| P2-C09 | CIS Benchmarks: RHEL 10 v1.0.1, RHEL 9 v3.0.0, RHEL 8 v4.0.0 (page lists no dates). | [CIS Red Hat Linux](https://www.cisecurity.org/benchmark/red_hat_linux) | `verified` for page state | Ubuntu rows were not re-fetched; the 29 October values stand. A benchmark label is not an on-host profile mapping. | 2026-11-30 |
| P2-C10 | Let's Encrypt: `tlsserver` profile 45-day certificates from 2026-05-13 (opt-in); default profile 64 days from 2027-02-10; 45 days from 2028-02-16. | [Let's Encrypt, From 90 to 45](https://letsencrypt.org/2025/12/02/from-90-to-45/) | `context-bound` plan (post dated 2025-12-02) | The page's "current values" sentence describes its publication date, not today. Recheck before 2027-02-10. | 2026-12-15 |
| P2-C11 | Cisco IOS XE Software Hardening Guide is reachable and covers SSHv2 and vty/tty line hardening. | [Cisco IOS XE hardening guide](https://sec.cloudapps.cisco.com/security/center/resources/IOS_XE_hardening) | `partial` | No publication or revision date on the page; the reader did not read the last 61 663 characters. The network skills name no IOS XE release numbers, so no release claim exists to verify; device-release applicability `NOT_ASSESSED`. | 2026-11-30 |

## The ten expired source rows

The ten rows LSR-01 to LSR-10 in `docs/continuous-improvement/skills-kaizen/P03-linux-web-service-preservation.md`
(review dates 2026-10-03 and 2026-10-26, all passed) were opened at their primary sources on
2026-10-31. Result: **8 verified, 2 partial.** Partial rows are narrowed in place, not upgraded.

| Row | Result | Detail |
|---|---|---|
| LSR-01 | verified | Debian `a2ensite(8)`: symlinks in `/etc/apache2/sites-enabled`; `sites-available` holds site files. |
| LSR-02 | verified | RHEL 9 section 1.3: `/etc/httpd/conf.d/` auxiliary directory; `apachectl configtest`. (The single-page guide returned HTTP 503; the chapter page was read instead.) |
| LSR-03 | partial | Ubuntu Nginx page and RHEL 9 sections 2.2 to 2.5 support their halves; the Ubuntu Apache page names `sites-available` and `a2ensite` but not `sites-enabled`. |
| LSR-04 | verified | `configtest` parses the files and reports `Syntax OK` or the error; equivalent to `-t`. |
| LSR-05 | verified | `nginx -t` checks syntax and opens referenced files; `-s reload` is a separate signal. |
| LSR-06 | verified | Certbot docs now at 5.9.0 (5.8.0 on 2026-09-26); `--dry-run` only for `certonly` and `renew`. |
| LSR-07 | verified | RFC 6797, November 2012: `max-age`, `includeSubDomains`. The reader read the first 100 000 of 115 923 characters; whether a later RFC updates it was not confirmed. |
| LSR-08 | verified | `http2` directive since 1.25.1; the `listen` `http2` parameter (1.9.5) is documented as deprecated, without a version. |
| LSR-09 | partial | Section 2.1 names 1.20 and shows 1.22 in sample output only; newer RHEL 9 streams appear in release notes, not in that section. |
| LSR-10 | verified | Mozilla `ssl-config-generator` archived by its owner on 2026-05-28, read-only. |

Measured with `scripts/kaizen_metrics.py`: expired structured source rows **10 to 0**.

## Engine edits driven by this review

- PostgreSQL install guidance on RHEL 9 named a default (13) that the project no longer
  supports; it now says to choose a stream and gives the commands and dates (commit P2-09).
- dnf automatic-update guidance rewritten for both dnf generations (commit P2-05).

## NOT_ASSESSED

Installed versions, enabled repositories and vendor back-port windows on any host; RHEL 10
database packaging; Oracle's official MySQL 8.4 end date; Ubuntu CIS rows; Cisco device-release
applicability; a Debian oldstable end date; advisories since 29 October (the security register
and triage runbook are inside their 5 November review and were not re-run).

Model currentness: no model-policy change is proposed. This pass makes no model call and the
Claude runtime keeps its own selection; a comparative benchmark is `NOT_ASSESSED`, as on 29 October
(`docs/continuous-improvement/model-review-2026-10-29.md`).

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
