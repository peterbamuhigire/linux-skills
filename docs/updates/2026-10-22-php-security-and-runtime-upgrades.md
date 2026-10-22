# PHP emergency security and runtime upgrade guidance — 2026-10-22

## Change

Added [`php-security-and-runtime-upgrades.md`](../../04-web-and-mail-services/linux-webstack/references/php-security-and-runtime-upgrades.md) and routed it from `linux-webstack` and `linux-package-management`. The procedure records the two Critical PHP RCE issues published on 2026-10-21, checks the vendor-fixed package revision, inventories CLI/web/FPM/container/worker execution surfaces, previews a scoped transaction, restarts confirmed long-lived handlers, verifies real HTTP paths, and stages PHP 8.5 site by site. It distinguishes shell commands from interactive program prompts and makes blank input a deliberate way to skip optional, unconfirmed worker units.

## Event record

PHP's 2026-10-21 advisories GHSA-w8hw-w9fx-j79w (CVE-2026-109618) and GHSA-6wmf-4rv5-p3rp (CVE-2026-109619) rate each issue Critical with CVSS 4.0 9.2/10. The sources describe remote code execution. The record does not repeat “biggest security vulnerability ever found”: the sources provide no defined historical comparison to substantiate that claim.

| Claim ID | Source ID / publication date | Scope | Access and verification date | Freshness / status / confidence | Uncertainty and review trigger |
|---|---|---|---|---|---|
| PHPSEC-001 | PHP-GHSA-001 + PHP-GHSA-002 / 2026-10-21 | Severity, score and RCE impact of two upstream PHP flaws | 2026-10-22 / 2026-10-22 | Incident-specific; supported; high confidence | SAPI reachability varies; re-open advisories during incident response |
| PHPSEC-002 | Ubuntu-USN-8948-1 / 2026-10-21 | Ubuntu 24.04 Noble package fix: `8.3.6-0ubuntu0.24.04.13` | 2026-10-22 / 2026-10-22 | Time-sensitive; supported; high confidence | Verify each host's candidate origin and handlers before patching |
| PHPSEC-003 | Debian-DSA-6574-1 / 2026-10-21 | Debian 13 Trixie package fix: `8.4.27-1~deb13u1` | 2026-10-22 / 2026-10-22 | Time-sensitive; supported; high confidence | Verify package version/source on each host before patching |
| PHPSEC-004 | PHP-downloads / 2026-10-21 | Upstream PHP 8.5.12 release | 2026-10-22 / 2026-10-22 | Volatile; supported; high confidence | Distro packages/extensions may differ; recheck before staging |
| PHPSEC-005 | PHP 8.4/8.5 migration guides; Composer CLI / accessed 2026-10-22 | Migration incompatibilities and actual-runtime platform checks | 2026-10-22 / 2026-10-22 | Version/tool dependent; supported; high confidence | Read intervening guides and verify Composer version before each migration |
| PHPSEC-006 | APT and DNF official command manuals / accessed 2026-10-22 | Transaction simulation and scoped package operations | 2026-10-22 / 2026-10-22 | CLI-version dependent; supported; high confidence | Confirm installed package-manager options and transaction before use |

Source links: [PHP OOM advisory](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w), [PHP stale-global-state advisory](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp), [Ubuntu USN-8948-1](https://ubuntu.com/security/notices/USN-8948-1), [Debian DSA-6574-1](https://lists.debian.org/debian-security-announce/2026/msg00489.html), [PHP downloads](https://www.php.net/downloads.php), [PHP migration 8.4](https://www.php.net/manual/en/migration84.php), [PHP migration 8.5](https://www.php.net/manual/en/migration85.php), [Composer CLI](https://getcomposer.org/doc/03-cli.md), [APT manual](https://manpages.debian.org/bookworm/apt/apt-get.8), [DNF reference](https://dnf.readthedocs.io/en/stable/command_ref.html).

## Currentness process and limits

The local Digital Research checkout was unavailable. The canonical public `source-evaluation`, `source-verification`, and Kaizen currentness gate skill bodies were retrieved on 2026-10-22. Official upstream, Ubuntu, Debian, APT, DNF and Composer sources were opened and compared against each recorded claim. The source-tier metadata-manifest replay and local Digital Research engine execution remain `NOT ASSESSED`.

PHP 8.5.12 is an upstream release; package availability is release-specific. On 2026-10-21, USN-8948-1 listed Noble's fix in PHP 8.3 and PHP 8.5 packages for Ubuntu 26.04/26.10. Debian 13's DSA listed its PHP 8.4 fix. The procedure therefore stops when no trusted side-by-side source exists and does not prescribe a blind PPA, OS release upgrade, or source build.

The advisories' temporary INI mitigations are documented as partial. In particular, setting `memory_limit=-1` broadly can cause resource exhaustion and is not recommended as a shared-host default. Isolate exposure while arranging the patched package when immediate patching is not possible.

## Acceptance and follow-up

- Keep the runbook current by checking official vendor advisories and package candidate origin before each security update.
- Recheck PHP lifecycle and upstream release sources before selecting a target branch.
- Use a staged target-runtime test and per-site FPM/socket or container cutover; maintain the previous patched runtime for recovery.
- Debian-family validation is source-backed. RHEL-family command paths are documented from the DNF manual but host execution is `NOT ASSESSED`.
- The one-off Ubuntu operator script remains outside this repository; no repo-owned executable script was added because a safe `sk-*` implementation needs two-family test fixtures and manifest integration.

Model-policy currentness was checked for this Kaizen. OpenAI's [current model documentation](https://developers.openai.com/api/docs/models) lists GPT-6 Astra as the flagship and GPT-6.1 Sol as a balanced option (accessed 2026-10-22); the active tool catalogue exposes GPT-6 Astra/Sol/Luna and GPT-5.6 Sol/Luna. No model-policy change was proposed. Account-specific model availability and comparative task quality/latency were not evaluated. `ensure_model_policy.py --check` reports drift between the Linux engine's local Luna-default rule and the user-provided root Astra rule; this task did not alter model configuration, and the conflict remains unresolved.
