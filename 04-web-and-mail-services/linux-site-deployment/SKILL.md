---
name: linux-site-deployment
description: Use when releasing one named website from a pinned repository revision to an existing Linux host, including versioned candidate, vhost cutover, rollback, external verification, and update registration. Use linux-webstack for stack setup.
license: MIT
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Site Deployment

## Distro support

Two-family skill. Static/PHP/Node deployment is largely portable; the
differences are how an Apache vhost is enabled, the web-server user, the
firewall, and — on the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma,
Oracle) — **SELinux labeling of the docroot**.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Enable Apache vhost | `a2ensite` (symlink) + reload | drop `*.conf` in `/etc/httpd/conf.d/` + reload |
| Web server user:group | `www-data:www-data` | `apache:apache` |
| Default docroot | `/var/www/html` | `/var/www/html` (same) |
| Reload web server | `systemctl reload apache2` / `nginx` | `systemctl reload httpd` / `nginx` |
| Open firewall | `ufw allow 80,443/tcp` | `firewall-cmd --permanent --add-service={http,https}; --reload` |
| **Docroot under SELinux** | n/a | label `httpd_sys_content_t` + `restorecon`; uploads `httpd_sys_rw_content_t` |

**RHEL deploy gotcha:** after copying a site into a custom docroot, set the
SELinux context or it serves 403s despite correct unix permissions:
`sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/example(/.*)?" && sudo restorecon -Rv /var/www/example`.
See [`../../04-web-and-mail-services/linux-webstack/references/httpd-reference.md`](../../04-web-and-mail-services/linux-webstack/references/httpd-reference.md)
and [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md).
In `sk-*` scripts use `svc_name`, `web_conf_dir`, `web_reload`, `firewall_allow`
from `common.sh`. Plan: [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

<!-- dual-compat-start -->
## Use when

- Releasing one named website from an approved repository revision to an existing host.
- Preparing a versioned release, site-specific vhost, cutover, and rollback for that release.
- Verifying external site health and registering the approved repository update procedure after release.

## Do not use when

- The server itself is not yet provisioned; use `linux-server-provisioning`.
- The task is generic web stack debugging rather than a new deployment; use `linux-webstack`.
- The task is certificate issue/renewal for an existing service outside a named site release; use `linux-firewall-ssl`.

## Required inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Domain, repository/revision, site type, build command, runtime, and document root | Release request and repository | required | Stop before cloning or generating a vhost. |
| Existing stack topology, web user, ports, SELinux state, and DNS readiness | Target host and DNS owner | required | Return a preflight report only. |
| Release window, secrets source, health check, rollback revision, and cutover authority | Service owner | required for production deployment | Build/stage only; do not publish. |

## Workflow

1. Collect deployment inputs up front: domain, site type, repo, and build needs.
2. Follow the eight deployment steps in order.
3. Validate web server config and TLS before making the site live.
4. Verify the final site response and repo registration state after deployment.
5. Stop if the release revision, secrets source, DNS/TLS ownership, health check, rollback target, or cutover authority is unresolved.
6. Recover a failed cutover by restoring the prior release symlink/config, validating and reloading the web service, then proving the prior external health check.

## Quality standards

- Deployment should leave the site reachable, renewable, and maintainable.
- Nginx validation and repo-registration steps are mandatory.
- Final verification must prove both HTTP behavior and operational update path.

## Anti-patterns

- Reloading without Nginx/Apache syntax validation. Fix: block reload on any config-test failure.
- Building directly in the live document root. Fix: build a versioned release and switch only after validation.
- Copying secrets into the repository or web root. Fix: use the authorised runtime secret source outside served paths.
- Ignoring SELinux labels on RHEL. Fix: define persistent `semanage fcontext` rules and restore contexts.
- Declaring success from a local `200` alone. Fix: test DNS, TLS, redirects, assets, backend health, and the external URL; register the update path.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Versioned site release and vhost | Service owner | Approved revision is served from the family-correct path with valid config and permissions/labels. |
| TLS and cutover record | Operations | DNS resolves, certificate matches/renews, HTTP redirects as intended, and rollback revision is available. |
| Deployment evidence | Maintainer | External health/assets/backend checks pass and the repository update mechanism is registered. |

## References

- [`references/deployment-checklist.md`](references/deployment-checklist.md)
- [`references/nginx-templates.md`](references/nginx-templates.md)
- [`references/apache-backend.md`](references/apache-backend.md)
- [`../../04-web-and-mail-services/linux-webstack/references/httpd-reference.md`](../../04-web-and-mail-services/linux-webstack/references/httpd-reference.md) — httpd conf.d model (RHEL family)
- [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux docroot labeling (RHEL family)
- [`../../07-security-and-hardening/linux-firewall-ssl/SKILL.md`](../../07-security-and-hardening/linux-firewall-ssl/SKILL.md) — firewall changes and certificate issue/renewal authority
- [`../../05-services-and-virtualization/linux-service-management/SKILL.md`](../../05-services-and-virtualization/linux-service-management/SKILL.md) — generic systemd actions and service-health evidence
- [`../../10-automation-and-scripting/linux-repo-sync/SKILL.md`](../../10-automation-and-scripting/linux-repo-sync/SKILL.md) — repository registration, update permissions, and conflict recovery
- [Apache `apachectl` reference](https://httpd.apache.org/docs/2.4/programs/apachectl.html) — config-test behavior; checked 2026-09-26
- [Debian `a2ensite(8)` reference](https://manpages.debian.org/testing/apache2/a2ensite.8.en.html) — Debian available/enabled site layout; checked 2026-09-26
- [Ubuntu Apache2 configuration guide](https://ubuntu.com/server/docs/how-to/web-services/configure-apache2-settings/) — Ubuntu vhost configuration and `a2ensite`; checked 2026-09-26
- [Ubuntu Nginx configuration guide](https://ubuntu.com/server/docs/how-to/web-services/configure-nginx/) — Ubuntu package site layout; checked 2026-09-26
- [Red Hat Enterprise Linux 9 Apache guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/deploying_web_servers_and_reverse_proxies/setting-apache-http-server_deploying-web-servers-and-reverse-proxies) — version-scoped `httpd` configuration paths and syntax check; checked 2026-09-26
- [Red Hat Enterprise Linux 9 web-server guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/deploying_web_servers_and_reverse_proxies/index) — version-scoped NGINX and Apache configuration; checked 2026-09-26
- [NGINX command-line parameters](https://nginx.org/en/docs/switches.html) — `-t` syntax and referenced-file checks; checked 2026-09-26
- [Certbot command reference](https://eff-certbot.readthedocs.io/en/stable/man/certbot.html) — plugin, issue, renew, and dry-run boundaries; checked 2026-09-26

## Evidence Produced

| Artefact | Acceptance condition |
|---|---|
| Deployment evidence | Includes revision/build output, config tests, release ownership/context, TLS and external checks, update registration, rollback target, and logs. |

## Capability contract

Read/search access to repository and host is required. Building in staging may be authorised separately. Production file changes, web reloads, certificate issuance, DNS/cutover, or public exposure require explicit authority. Destructive cleanup waits until rollback retention expires.

## Degraded mode

Fallback when DNS, certificate issuance, external probing, or production authority is unavailable: stop at the narrowest validated stage and mark cutover gates `not assessed`. A successful local build is not a deployed site.

## Decision rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Static build | Serve immutable release directly through Nginx | Unneeded backend complexity. |
| PHP/hybrid application | Use approved Apache/PHP-FPM backend pattern | Executing PHP incorrectly or exposing source. |
| Failed health after cutover | Restore prior config/release, then diagnose | Prolonged outage during investigation. |

## Worked example

For an Astro site on AlmaLinux, build the pinned revision into a versioned release, label it `httpd_sys_content_t`, install a reviewed Nginx vhost, pass `nginx -t`, switch the release, issue/verify TLS after DNS is ready, test the external page and assets, and record rollback plus update registration.

<!-- dual-compat-end -->

This skill is self-contained. Every step below works with only the tools
that ship with the Debian/Ubuntu and RHEL families (see Distro support above
for the per-family command differences). The `sk-*` scripts listed in the Scripts
manifest are an **optional fast path** that wraps the same steps — install
them if they make your life easier, but they are never required.

Ask these questions first:

1. **Domain name?** (e.g. example.com)
2. **Site type?**
   - **A** — Astro/static (Nginx serves `/dist/` directly)
   - **B** — PHP app (Nginx → Apache port 8080)
   - **C** — Astro + PHP hybrid (static front + PHP backend)
3. **Repo URL?**
4. **Node.js API needed?** (separate systemd service)

---

## Staged deployment sequence

These stages are a gated workflow, not commands to paste unchanged into a live
host. Keep the existing production release available until the candidate has
passed validation and its rollback path is known.

1. **Confirm authority and baseline.** Pin the approved repository revision,
   domain, document root, DNS state, runtime, release owner, change window,
   external health check, and rollback revision. Snapshot the existing vhost,
   service state, and current release before editing.
2. **Prepare a versioned candidate.** Check out the approved revision into a
   new release directory outside the live document root. Use the designated
   unprivileged build/deploy account and the repository's lockfile and
   documented build procedure. Never run dependency installation or project
   build scripts as root. Keep secrets outside the repository and served tree.
3. **Review the candidate.** Confirm that the build output, ownership, runtime
   secret references, and required application files are present. Do not
   overwrite the current release or delete retained rollback material.
4. **Prepare the vhost in the host's configured include path.** Use the
   appropriate pattern in [`references/nginx-templates.md`](references/nginx-templates.md).
   Its path labels are examples; do not assume that the target package loads
   `sites-available`. The Apache backend template in
   [`references/apache-backend.md`](references/apache-backend.md) is for
   Debian/Ubuntu; on RHEL-family hosts use the family-specific
   [`linux-webstack` httpd guidance](../linux-webstack/references/httpd-reference.md)
   and verify the PHP-FPM socket/service on the target.
   For Apache on Debian/Ubuntu, place the candidate under
   `/etc/apache2/sites-available/` and enable it through `a2ensite` only after
   review. For RHEL-family Apache, use the configured `/etc/httpd/conf.d/`
   include path and the `httpd` service; this path is documented for RHEL 9,
   while Rocky/Alma/CentOS behavior must be checked on the target release.
   Nginx package layouts vary, so inspect the host's configured include path
   instead of assuming `sites-available` exists.
5. **Validate before activation.** Run `nginx -t` for Nginx and the installed
   Apache frontend's syntax check (`apache2ctl configtest` on Debian/Ubuntu,
   `apachectl configtest` on RHEL 9). Check the resulting virtual-host mapping
   and confirm the candidate will not expose a backend or management port.
   Stop on any failed check or unexplained diff.
6. **Complete TLS and firewall work through their owner.** Check DNS, challenge
   reachability, certificate names/expiry, and intended exposure. Use
   [`linux-firewall-ssl`](../../07-security-and-hardening/linux-firewall-ssl/SKILL.md)
   for certificate or firewall actions. Certificate issuance, web-server
   installation by a Certbot plugin, and firewall changes are privileged
   mutations; approve each action and revalidate any configuration the tool
   changes. A local build or successful syntax check is not proof that TLS or
   public reachability works.
7. **Cut over and verify.** Only after explicit cutover authority, activate the
   reviewed vhost and switch the site-specific release pointer. Reload only
   the affected service after its syntax test passes. Verify the external
   hostname, TLS name/chain, redirect behavior, required assets, application
   health, logs, and update path. If a check fails, restore the saved vhost and
   release pointer, validate them, then verify the prior external health check.
8. **Register the update path.** Add the repository to the authorized update
   mechanism as required by the engine's new-repository policy. Follow
   [`linux-repo-sync`](../../10-automation-and-scripting/linux-repo-sync/SKILL.md)
   for exact permissions and recovery. Do not edit system update scripts or
   run an update until the change owner authorizes it; test the registered
   revision/build procedure outside the live release first.

For the shared Nginx/Apache/PHP-FPM configuration, route to
[`linux-webstack`](../linux-webstack/SKILL.md). For service mutation and generic
systemd recovery, route to
[`linux-service-management`](../../05-services-and-virtualization/linux-service-management/SKILL.md).
These references preserve distinct task entrypoints; they do not grant
additional host authority.

---

## Verify

```bash
curl -sI https://<domain> | grep -E "HTTP/|Server:"
sudo certbot certificates | grep -A3 "<domain>"
```

For Node.js API service setup, see `linux-webstack`.
Full Nginx/Apache config templates: `references/nginx-templates.md`

---

## Optional fast path (when sk-* scripts are installed)

If the optional `linux-site-deployment` scripts are installed, inspect each
script's current source and dry-run behavior before use. The manifest below is
an inventory, not proof that a script implements the staged sequence above or
is safe for a particular host.

| Site type | Fast path |
|---|---|
| A — Astro / static | `sudo sk-astro-deploy --domain <d> --repo <url>` |
| A — static only | `sudo sk-static-site-deploy --domain <d> --repo <url>` |
| B — PHP | `sudo sk-php-site-deploy --domain <d> --repo <url>` |
| C — Astro + PHP hybrid | `sudo sk-astro-deploy --hybrid --domain <d> --repo <url>` |

Helper scripts for individual steps: `sk-nginx-new-site`,
`sk-apache-new-site`, `sk-nginx-test-reload`, `sk-apache-test-reload`,
`sk-cert-status`. All are optional wrappers around the manual commands
above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-site-deployment
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-update-all-repos | scripts/sk-update-all-repos.sh | yes | Pull all registered repos on this server; interactive menu + `--all`/`--repo` flags. |
| sk-nginx-new-site | scripts/sk-nginx-new-site.sh | no | Generate a new Nginx vhost from template, issue cert via certbot, reload. |
| sk-apache-new-site | scripts/sk-apache-new-site.sh | no | Generate an Apache vhost on port 8080, `a2ensite`, `configtest`, reload. |
| sk-astro-deploy | scripts/sk-astro-deploy.sh | no | Clone an Astro site, install deps, build, set up Nginx vhost + SSL, register in `update-all-repos`. |
| sk-php-site-deploy | scripts/sk-php-site-deploy.sh | no | Clone a PHP site, set ownership, configure vhost, SSL, register in `update-all-repos`. |
| sk-static-site-deploy | scripts/sk-static-site-deploy.sh | no | Clone a static site, configure vhost, SSL, register in `update-all-repos`. |
