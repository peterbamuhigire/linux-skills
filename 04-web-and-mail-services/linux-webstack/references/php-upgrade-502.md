# Diagnose 502 after a PHP upgrade

Parent skill: [linux-webstack](../SKILL.md). Audience: on-call operator.
Do not restart a guessed PHP unit. Begin read-only; mutation needs the affected
site, maintenance authority, known-good release/config and recovery access.

1. Record the first failure time, upgrade transaction and affected URL. Capture
   one request's status/body and correlate its timestamp with Nginx and PHP-FPM
   logs. Redact cookies, credentials and customer data. Establish whether every
   site or only one pool is affected.
2. Inspect the effective Nginx configuration with `nginx -T` privately; it can
   contain sensitive settings. Identify the exact `fastcgi_pass` socket or TCP
   endpoint, server block, document root and SCRIPT_FILENAME. Discover the
   installed/active FPM unit and pool configuration instead of assuming php8.3.
   Debian typically has versioned FPM units; RHEL-family examples commonly use
   php-fpm. Confirm the target's actual names.
3. Compare the configured endpoint with listening sockets (`ss -lntp` or
   `ss -lxnp`), pool `listen` setting, service status and time-bounded logs.
   Inspect only the selected service with `systemctl status` and `journalctl -u`.
   Do not infer listener readiness from an active service alone.
4. Branch on the observed error:
   - **Missing/refused socket or port:** determine whether the upgrade changed
     the pool listener or stopped the old service. Compare package/config history.
     Fix the evidenced endpoint or restore the compatible prior runtime; avoid
     running two conflicting pools unintentionally.
   - **Permission denied:** check path traversal, socket owner/group/mode and
     worker identity. On SELinux hosts inspect AVC denials and labels; on
     AppArmor hosts inspect profile denials. Do not chmod777, disable MAC or
     add broad network access as a diagnostic shortcut.
   - **Timeout:** inspect pool saturation, slow requests, database latency and
     resource limits before increasing timeouts. A timeout increase can hide
     an application failure.
   - **Invalid FastCGI/application error:** verify SCRIPT_FILENAME, root,
     PHP extensions and application compatibility with the new runtime. Restore
     a compatible release/runtime pair if validation fails.
5. Define one change with before/after diff and rollback. Preserve the previous
   vhost, pool config and compatible runtime image/package provenance. Pass
   `nginx -t` and the installed FPM binary's configuration test before a reload.
   Stop on invalid configuration. Reload only the affected component.
6. Verify the original URL's response body, not merely HTTP200, plus the intended
   external path, error logs, service/listener and neighbouring sites. Repeat the
   check without another mutation to confirm stability over the agreed window.
7. On failure, restore the known-good vhost/pool and compatible runtime together,
   validate configuration, start/reload the selected units and repeat request/log
   checks. A vhost rollback to a socket whose old pool no longer exists is not
   recovery. Do not blindly downgrade a runtime after incompatible app changes.

Evidence: exact upstream before/after, observed error, chosen branch, package
and config provenance, tests/exit status, response-body witness, elapsed time,
rollback result and residual risk. Without the host/logs this is a diagnosis
plan; label the cause and recovery outcome NOT_ASSESSED.

The disposable [502 lab](../../../tests/labs/web_502.sh) exercises listener
migration, an observed502, correction, a rejected invalid configuration and
actual rollback. It simulates an upgrade's listener change; it does not test a
real package upgrade, systemd, SELinux or application-version compatibility.
Run only inside an explicitly selected disposable container with dependencies
installed; the script refuses ordinary host execution.

Sources checked 2026-10-29: [Nginx FastCGI module](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
and [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php).
These define endpoint/pool configuration; the diagnostic order above is an
operational synthesis. Recheck on target runtime/configuration changes.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
