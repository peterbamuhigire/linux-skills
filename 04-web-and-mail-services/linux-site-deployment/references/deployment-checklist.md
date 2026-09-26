# Staged site-release checklist

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Use this checklist with [`../SKILL.md`](../SKILL.md). It is a planning and evidence aid, not a tested command script. Execute only the operations authorised for the exact host and release. The Debian/Ubuntu and RHEL 9 path notes below are source-backed; other RHEL-family derivatives and locally changed package layouts need target-host confirmation.

## 1. Release request and authority

- [ ] Record the domain(s), repository, immutable revision, application/runtime, build procedure, document root, host release, service topology, and DNS owner.
- [ ] Identify the release owner, approved maintenance window, intended public exposure, external application-health check, and explicit cutover authority.
- [ ] Name the prior release and configuration to restore. Confirm that the recovery path does not rely on the listener or access route being changed.
- [ ] Identify the approved source for deploy credentials, runtime secrets, certificate material, and repository registration. Do not place secrets in a URL, command history, repository, web root, or shared evidence.
- [ ] Set each gate to `pass`, `fail`, or `not assessed`. Missing lab/host access is not a pass.

**Stop:** an unknown revision, host, domain owner, expected application response, approval, or recoverable prior state keeps the work at read-only planning.

## 2. Baseline and candidate

- [ ] Capture the current release pointer, relevant vhost files, service state, listeners, DNS/TLS observations, and application-health result.
- [ ] Keep the current release and a restorable configuration copy. Record paths, ownership, timestamps, and content hashes; exclude private-key bytes and credentials.
- [ ] Fetch the approved repository revision into a new versioned release directory outside the live document root.
- [ ] Build with the designated unprivileged release account, project lockfile, and project-documented procedure. Do not install dependencies or run project build scripts as root.
- [ ] Verify the candidate output, ownership/read permissions, secret references, and required application files before preparing a cutover.
- [ ] Do not delete the current release, modify another site's files, or recursively change ownership of the live tree to repair a candidate permission error.

Record the exact source revision, build command, account, environment, exit status, build log path, and candidate digest. Keep logs free of credentials.

## 3. Family-aware vhost preparation

Use the configuration bodies in [`nginx-templates.md`](nginx-templates.md) only after confirming that the selected pattern matches the application and target. A template's example path is not proof that the host includes that path.

| Component | Debian/Ubuntu evidence | RHEL 9 evidence | Required host check |
|---|---|---|---|
| Nginx | Ubuntu package guide documents `sites-available`/`sites-enabled`. | RHEL guide configures virtual hosts through `/etc/nginx/nginx.conf`. | Inspect the installed configuration's active include path; use only that path. |
| Apache | Ubuntu uses `/etc/apache2/sites-available/`; `a2ensite` creates the enabled-site link. | RHEL 9 `httpd` includes auxiliary files from `/etc/httpd/conf.d/`. | Confirm the actual service, include path, vhost order, listener, and target release. Do not use `a2ensite` on RHEL. |
| Config syntax | Nginx `-t`; Apache `apache2ctl configtest`. | Nginx `-t`; Apache `apachectl configtest`. | Check installed binary/config path; capture the exact output and exit status. |

For an Apache backend, [`apache-backend.md`](apache-backend.md) gives Debian/Ubuntu examples. It is not a RHEL vhost template. Use the RHEL-family guidance in [`../../linux-webstack/references/httpd-reference.md`](../../linux-webstack/references/httpd-reference.md) and confirm PHP-FPM/socket details on the target before preparing an equivalent candidate.

- [ ] Review a narrow diff of the candidate config, route, document root, proxy target, and listener exposure.
- [ ] Confirm the backend and management ports are not exposed unintentionally.
- [ ] Confirm persistent SELinux labels and required permissions for custom content paths; do not disable SELinux to make a deployment work.
- [ ] Keep firewall rules and certificate lifecycle under [`linux-firewall-ssl`](../../../07-security-and-hardening/linux-firewall-ssl/SKILL.md).

## 4. Preflight and cutover gate

- [ ] Confirm DNS points to the intended host and the ACME challenge path is reachable by the selected method.
- [ ] Record current certificate names, issuer/chain, validity, renewal method, and expiry. Do not copy or print private keys into evidence.
- [ ] Run Nginx and/or Apache syntax validation before enabling or reloading the candidate. A failed check blocks cutover.
- [ ] Check the requested ports and owning processes. Resolve unexplained collisions before changing a firewall or killing a process.
- [ ] Have the service owner approve the exact candidate diff, target services, planned reload/restart, verification probes, and rollback trigger.
- [ ] If a Certbot plugin changes web-server configuration, review that diff and rerun the owning server's syntax test before reloading.

**Stop:** failed syntax, missing DNS/TLS evidence, unexpected listeners, missing recovery, or missing authority blocks activation. A successful local build or daemon start does not establish external application health.

## 5. Verification and evidence

After the authorised cutover, verify the requested domain from outside the host and through the application path. Match the expected status/redirect and response content; do not treat a generic HTTP 200 as sufficient.

- [ ] Hostname resolves to the intended target.
- [ ] TLS hostname, validity, chain, and redirect behavior match the release request.
- [ ] Required assets and application routes return the expected content.
- [ ] A dynamic request reaches the correct backend and dependency path.
- [ ] The correct service is healthy, logs contain no new release-blocking errors, and the application probe passes.
- [ ] The repository update procedure identifies the approved revision/build action and uses the authorised `linux-repo-sync` workflow.
- [ ] Record commands, environment, timestamps, exit/status codes, outputs, config/release hashes, and any redaction. Preserve failures as failures.

Do not record a pass for a probe that was blocked, unavailable, or not run. Mark missing external, service, certificate, or application checks `not assessed`.

## 6. Failure and recovery

Trigger recovery on any failed required health check, syntax/activation error, unintended exposure, unexpected error increase, or confirmed mismatch with the approved revision.

1. Stop further writes, retries, and cleanup. Preserve diagnostics and the failed candidate.
2. Restore only the named site's prior vhost and release pointer from the recorded snapshot.
3. Validate the restored configuration before reloading only the owning service.
4. Repeat the prior external application-health check and inspect relevant service logs.
5. Record each restore command, exit status, restored hashes, and residual issue; leave unrelated sites, firewall policy, certificate state, and repository data unchanged unless a separately approved recovery requires them.

Do not automatically revoke a certificate or remove a repository/release as rollback. Retain the failed candidate and recovery evidence until the owner accepts the outcome and the rollback-retention period ends. Never use an unqualified recursive deletion as a generic cleanup step.

## 7. Source notes

- Debian `a2ensite(8)`: <https://manpages.debian.org/testing/apache2/a2ensite.8.en.html> — Debian testing layout; accessed 2026-09-26.
- Ubuntu Apache: <https://ubuntu.com/server/docs/how-to/web-services/configure-apache2-settings/> — Ubuntu vhost setup; accessed 2026-09-26.
- Ubuntu Nginx: <https://ubuntu.com/server/docs/how-to/web-services/configure-nginx/> — Ubuntu package site layout; accessed 2026-09-26.
- Red Hat RHEL 9 Apache: <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/deploying_web_servers_and_reverse_proxies/setting-apache-http-server_deploying-web-servers-and-reverse-proxies> — version-specific `httpd` paths and checks; accessed 2026-09-26.
- Red Hat RHEL 9 web servers: <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/deploying_web_servers_and_reverse_proxies/index> — version-specific Nginx/Apache procedure; accessed 2026-09-26.
- Apache `apachectl`: <https://httpd.apache.org/docs/2.4/programs/apachectl.html> — upstream syntax-test behavior; accessed 2026-09-26.
- Nginx command-line parameters: <https://nginx.org/en/docs/switches.html> — `-t` and reload behavior; accessed 2026-09-26.
- Certbot command reference: <https://eff-certbot.readthedocs.io/en/stable/man/certbot.html> — plugin and dry-run semantics; accessed 2026-09-26.

Publication dates are not stated on the living upstream pages; the source and scope are rechecked on the dates above. Recheck volatile instructions by 2026-10-03. These sources do not prove behavior on a particular host or in an ERPNext lab.
