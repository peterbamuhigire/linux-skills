# Debugging cloud-init and autoinstall

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

When a first-boot does not do what you expect, the answer is always in
the logs. cloud-init is verbose and well-instrumented; the trick is
knowing which log to read and what to grep for. This reference
documents every log location, the built-in diagnostic commands, the
common failure signatures, and how to force a clean re-run for
iterative testing. Autoinstall-specific debugging (the installer
environment) is covered at the end.

## Table of contents

- [Log locations](#log-locations)
- [`cloud-init status`](#cloud-init-status)
- [`cloud-init analyze`](#cloud-init-analyze)
- [`cloud-init schema`](#cloud-init-schema)
- [`cloud-init query`](#cloud-init-query)
- [Forcing a clean re-run](#forcing-a-clean-re-run)
- [Common failure signatures](#common-failure-signatures)
- [Tracking down which module failed](#tracking-down-which-module-failed)
- [`runcmd` exit codes](#runcmd-exit-codes)
- [Autoinstall-specific debugging](#autoinstall-specific-debugging)
- [Sources](#sources)

## Log locations

cloud-init splits its output across several files. Read them in this
order:

| File | What's in it |
|---|---|
| `/var/log/cloud-init.log` | Full cloud-init trace (every module, every stage, every decision). Verbose. This is the one you `grep ERROR` first. |
| `/var/log/cloud-init-output.log` | Stdout and stderr of `bootcmd`, `runcmd`, and scripts. This is where you see `apt-get` output and the output of your own commands. |
| `/run/cloud-init/status.json` | Machine-readable status of the current run. `cloud-init status --long` reads this. |
| `/run/cloud-init/result.json` | Final result of the completed run (errors, datasource). |
| `/run/cloud-init/instance-data.json` | Rendered metadata — the variables Jinja templates had access to. |
| `/var/lib/cloud/instance/user-data.txt` | The **effective** user-data as received (not what you wrote — what cloud-init saw after merging, decoding, etc). |
| `/var/lib/cloud/instance/cloud-config.txt` | The parsed `#cloud-config` document. If this is empty or missing, the header was wrong. |
| `/var/lib/cloud/instance/scripts/runcmd` | The shell script that `runcmd` was compiled to. You can re-execute it by hand. |
| `/var/lib/cloud/data/result.json` | Historical result for the current instance id. |

Key rule: **`cloud-init.log` tells you what cloud-init did;
`cloud-init-output.log` tells you what your commands said back.**

## `cloud-init status`

First command to run on a "did cloud-init even finish?" question:

```bash
cloud-init status --long
```

Output:

```text
status: done
time: Thu, 10 Apr 2026 06:14:22 +0000
detail:
DataSourceNoCloud [seed=/var/lib/cloud/seed/nocloud-net][dsmode=net]
```

Possible statuses:

- `not run` — cloud-init hasn't started. Check the services
  (`systemctl status cloud-init-local cloud-init cloud-config cloud-final`).
- `running` — still going. Wait, or tail `/var/log/cloud-init.log`.
- `done` — finished. Whether successfully is another matter — check
  `result.json` for errors.
- `error` — at least one module reported a fatal. Details are under
  `detail:`.
- `disabled` — cloud-init is disabled (`/etc/cloud/cloud-init.disabled`
  exists or the kernel cmdline has `cloud-init=disabled`).

To wait for completion in a script:

```bash
cloud-init status --wait && echo "cloud-init finished"
```

Exits non-zero if the final status is `error`.

## `cloud-init analyze`

Timing and blame for slow boots. Three subcommands:

```bash
cloud-init analyze show      # timeline of every stage and module
cloud-init analyze blame     # sorted by time taken, slowest first
cloud-init analyze dump      # raw JSON for feeding into other tools
```

`analyze blame` is the killer feature when a server takes 7 minutes to
come up. Output looks like:

```text
-- Boot Record 01 --
     00.01700s (modules-config/config-apt-configure)
     00.02100s (modules-config/config-ssh)
     03.54000s (modules-config/config-package-update-upgrade-install)
     12.08200s (modules-final/config-runcmd)
     00.00200s (modules-final/config-final-message)
```

If `runcmd` dominates, start trimming it. If `package-update-upgrade`
dominates, consider a pre-baked image.

## `cloud-init schema`

Offline validator. Run **before** you deploy:

```bash
cloud-init schema --config-file user-data.yaml
```

Pass output:

```text
Valid cloud-config: user-data.yaml
```

Fail output points at the exact key and line:

```text
Cloud config schema errors:
  users.1.sudo: 'ALL=(ALL) NOPASSWD ALL' is not of type 'string', 'array'
```

Use this in CI before handing user-data to a cloud provider — a broken
file silently ignores modules and you end up with an under-configured
server.

For a running instance, you can validate what it actually received:

```bash
sudo cloud-init schema --system
```

## `cloud-init query`

Query rendered metadata and user-data on the running instance. Handy
for confirming what cloud-init parsed:

```bash
cloud-init query userdata              # print the raw user-data
cloud-init query --format '{{ds.meta_data}}'
cloud-init query v1.cloud_name         # aws, digitalocean, lxd, ...
cloud-init query v1.instance_id        # the instance id driving idempotency
```

If `query userdata` comes back empty or wrong, your datasource is
broken — cloud-init never got the file.

## Forcing a clean re-run

cloud-init runs once per instance id. For iterative testing:

```bash
sudo cloud-init clean --logs --seed
sudo reboot
```

- `--logs` — also wipe `/var/log/cloud-init*.log` so you get a clean
  trace.
- `--seed` — also wipe cached NoCloud seed data.
- Without any flag, `clean` just removes `/var/lib/cloud/` so
  cloud-init re-runs on next boot with the same user-data.

**Do not run `clean` on production.** It will re-execute `runcmd`,
possibly re-install packages, possibly re-create users, and will
absolutely rewrite `/etc/hosts` and `/etc/hostname` if `manage_etc_hosts`
is set.

To re-run just one module without a full clean and reboot:

```bash
sudo cloud-init single --name cc_runcmd --frequency once
```

Useful module names: `cc_users_groups`, `cc_runcmd`, `cc_write_files`,
`cc_package_update_upgrade_install`, `cc_ssh_authkey_fingerprints`.

## Common failure signatures

Search `/var/log/cloud-init.log` for `ERROR`, `WARNING`, and
`Traceback`. Typical patterns:

### "No instance datasource found"

```text
WARNING: No local datasources found
ERROR: Datasource... None
```

cloud-init couldn't find its user-data. On a bare-metal or VM boot,
check that the NoCloud seed disk is attached and labelled `cidata`.
On a cloud VM, check that the metadata service is reachable
(`curl -v http://169.254.169.254/`).

### "Cloud config schema errors"

```text
WARNING: Invalid cloud-config provided:
Please run 'sudo cloud-init schema --system' to see the schema errors.
```

The user-data parsed as YAML but failed schema validation. Modules
may have been skipped. Run `cloud-init schema --system` for details.

### "ci-info: ... no-route"

The network never came up. Any runcmd that touches the internet will
fail. Check `/etc/netplan/` and `networkd` logs.

### "Permission denied" in runcmd

```text
/var/lib/cloud/instance/scripts/runcmd: line 4: /usr/local/bin/foo: Permission denied
```

`write_files` created the script with the wrong mode. Quote
`permissions: '0755'` — unquoted `0755` is decimal.

### "apt-get: command not found"

Almost always a bad PATH in a runcmd string. Use an exec-style list
(`[apt-get, install, -y, nginx]`) or absolute paths (`/usr/bin/apt-get`).

### "Failed to download" on apt update

```text
E: Failed to fetch http://archive.ubuntu.com/...
```

DNS or mirror problem. If you set `apt.primary.uri`, double-check the
URL. If `apt.geoip: true` is on but the geoip lookup timed out,
cloud-init falls back to the default — check `/var/log/cloud-init.log`
for `geoip`.

### "user X already exists"

On a re-run (after `cloud-init clean`) cloud-init may complain about
users that still exist. Harmless unless the user's groups or keys
differ from what the user-data says — cloud-init will update them.

## Tracking down which module failed

Every module logs with a consistent tag. To see the last handful of
modules that ran and their exit status:

```bash
grep 'finish:' /var/log/cloud-init.log | tail -30
```

Output looks like:

```text
finish: init-network/config-write-files: SUCCESS: running config-write-files
finish: init-network/config-users-groups: SUCCESS: running config-users-groups
finish: modules-config/config-apt-configure: SUCCESS: running config-apt-configure
finish: modules-config/config-package-update-upgrade-install: FAIL: running ...
```

The module name after the slash maps directly to a `cc_*.py` file in
`/usr/lib/python3/dist-packages/cloudinit/config/`. To read what that
module does:

```bash
less /usr/lib/python3/dist-packages/cloudinit/config/cc_runcmd.py
```

## `runcmd` exit codes

`runcmd` commands are compiled to a single shell script at
`/var/lib/cloud/instance/scripts/runcmd` and executed by the
`scripts-user` handler during the `final` stage. Their stdout/stderr
goes to `/var/log/cloud-init-output.log`.

Key facts:

- A non-zero exit **does not abort** cloud-init. Later commands keep
  running. Use `set -e` in heredoc blocks for fail-fast.
- The script is re-executable by hand — useful when you've manually
  installed missing prerequisites and want to finish the bootstrap:

```bash
sudo bash /var/lib/cloud/instance/scripts/runcmd
```

- To see per-command exit codes, wrap the runcmd body with `set -x`:

```yaml
runcmd:
  - |
    set -euxo pipefail
    systemctl enable --now nginx
    ufw --force enable
```

`set -x` prints every command and the PS4 prompt to
`cloud-init-output.log`; `set -e` makes the first failure abort the
script; `pipefail` makes a failure anywhere in a pipeline abort.

## Autoinstall-specific debugging

Autoinstall runs under subiquity inside the live-server installer
environment, which is a different beast from runtime cloud-init.

### Console

With `reporting.builtin.type: print` (the default), every stage logs
to `tty1` and to any configured serial console. On a VM, add
`console=ttyS0,115200` to the kernel command line to capture the
serial console with `virsh console` or the cloud provider's serial
viewer.

### Log files in the live session

While the installer is still running (or after it halts on error),
drop to a shell (`Help → Enter shell` from the TUI) and look at:

| File | What's in it |
|---|---|
| `/var/log/installer/autoinstall-user-data` | The effective autoinstall config after early-commands. This is what the installer actually used — diff it against what you wrote. |
| `/var/log/installer/subiquity-server.log` | The installer's own debug log. Tracebacks land here. |
| `/var/log/installer/subiquity-server-debug.log` | Even more verbose. |
| `/var/log/installer/curtin-install.log` | curtin's log — it does the actual disk partitioning, mkfs, bootloader install. Storage failures live here. |
| `/var/log/installer/curtin-install-cfg.yaml` | The curtin config that subiquity generated from your storage section. Useful when the "storage layout" you wrote doesn't match what curtin saw. |
| `/var/log/installer/syslog` | Full systemd+journal output of the installer environment. |
| `/var/log/installer/block-meta.log` | Disk probe results — which disks, sizes, serials, whether they matched your match specs. |

### After a successful install

A copy of the effective autoinstall config is written to the **installed
system** at `/var/log/installer/autoinstall-user-data`. This is the
one you want to save and iterate on — it has any defaults filled in
and every quirk resolved. Use it as the starting point for your next
install.

### early-commands failures

`early-commands` run before the installer validates the rest of the
config, so their failures are logged but the config is re-read
afterwards. If early-commands fail in a way that prevents the re-read,
the installer halts with a terse error on tty1 and you'll need
`subiquity-server.log` to see the traceback.

### late-commands failures

A non-zero exit from a `late-commands` entry aborts the install,
triggers `error-commands` (if set), and leaves the target at
`/target/` for inspection. `curtin in-target -- <cmd>` failures are
especially common — the chroot has no network unless you bind-mount
`/run/systemd/resolve/` in first.

### error-commands

These are your escape hatch. Always include an `error-commands` that
tars up `/var/log/installer/` and ships it somewhere — otherwise when
the installer halts you have one chance to read the logs before
reboot wipes them.

```yaml
error-commands:
  - tar czf /tmp/installer-logs.tgz /var/log/installer
  - curl -fsS -T /tmp/installer-logs.tgz http://logs.internal/
```

### Forcing the installer to pause

Add the kernel command line argument `autoinstall` to proceed without
confirmation, or **omit** it to force the installer to prompt before
writing to disk. The Ubuntu Server Guide is explicit about the reason:

> Even if a fully noninteractive autoinstall config is found, the
> server installer will ask for confirmation before writing to the
> disks unless autoinstall is present on the kernel command line.
> This is to make it harder to accidentally create a USB stick that
> will reformat a machine it is plugged into at boot.

When debugging, omit the `autoinstall` keyword on the kernel command
line so you get a chance to cancel before disks are touched.

## Sources

- Canonical, *Ubuntu Server Guide Documentation — Linux 20.04 LTS
  (Focal)*, 2020. "Automated Server Installs" chapter, specifically
  the "Error handling", "JSON Schema for autoinstall config", and
  "Providing the autoinstall config" sections, plus the cloud-init
  references throughout the Virtualization chapters.
- cloud-init upstream documentation referenced from the Ubuntu guide
  (`https://cloudinit.readthedocs.io/`) for the `analyze`, `schema`,
  `query`, and `clean` subcommand behaviour.
- `linux-cloud-init/SKILL.md` — standing rules on debug with
  `/var/log/cloud-init.log` and `/var/log/cloud-init-output.log`.
