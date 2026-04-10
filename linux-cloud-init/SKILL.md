---
name: linux-cloud-init
description: Design, validate, and debug cloud-init user-data and Ubuntu autoinstall configurations. Use when bootstrapping fresh servers from YAML — first-boot package installs, user creation, SSH keys, network config, and custom runcmd blocks.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux cloud-init

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool (`cloud-init`, `journalctl`, `yamllint`). The `sk-*`
scripts in the **Optional fast path** section are convenience wrappers —
never required.

This skill owns **first-boot provisioning from YAML** — cloud-init
user-data on cloud images, and Ubuntu's autoinstall flow on the
installer. It is the mechanism that takes a blank Ubuntu image and turns
it into a server ready for `linux-server-provisioning` to finish.

It does **not** own:

- **Interactive post-boot setup** — `linux-server-provisioning`.
- **Cloud provider APIs** (creating the VM in the first place) — out of
  scope.
- **Ongoing configuration management** — `linux-config-management`.

Informed by the Canonical *Ubuntu Server Guide* (cloud-init, autoinstall
chapters).

---

## When to use

- Writing a `user-data` YAML for a cloud image.
- Writing an Ubuntu `autoinstall` config for a new installer ISO.
- Validating user-data before feeding it to a cloud provider.
- Debugging why a first-boot didn't install packages or create users.
- Extracting errors from `/var/log/cloud-init*.log` on a provisioned host.

## When NOT to use

- Day-2 config changes — use `linux-config-management` (Ansible).
- Manual post-boot steps — run the relevant `linux-*` skill directly.

---

## Standing rules

1. **Validate every user-data file before using it.** A broken
   user-data silently ignores modules — you end up with an
   under-configured server.
2. **Never put secrets in plain-text user-data.** cloud-init caches it
   under `/var/lib/cloud/` where it can be read later. Use vaulted
   values or post-boot pulls from a secret store.
3. **`runcmd` is last resort.** Prefer first-class modules (`users`,
   `packages`, `write_files`, `ssh_authorized_keys`) where possible.
   They log cleanly and are idempotent-friendly.
4. **The very last `runcmd` step in every production server user-data
   should install linux-skills.** Templates live in the references.
5. **Debug with the logs.** `/var/log/cloud-init.log` has the module
   trace; `/var/log/cloud-init-output.log` has stdout/stderr of
   `runcmd`.
6. **Autoinstall is a different schema than runtime user-data.** Don't
   cross them over. Autoinstall's cloud-init runs in a restricted
   installer environment.

---

## Quick reference — manual commands

### Validate a user-data file

```bash
# Built-in schema check (requires cloud-init installed)
cloud-init schema --config-file user-data.yaml

# With verbose output
cloud-init schema --config-file user-data.yaml --strict

# YAML syntax check first (basic)
yamllint user-data.yaml
```

### Inspect cloud-init state on a running server

```bash
# Overall status
cloud-init status --long

# How long each stage took
cloud-init analyze show
cloud-init analyze blame                    # slowest modules
cloud-init analyze dump                     # full event stream

# What datasource was used?
cloud-init query --format '{{ ds.platform }} / {{ ds.region }}'

# All the collected facts (ds metadata + user-data + vendor-data)
cloud-init query --all
```

### Debug a failed run

```bash
# Main log — module start/end, failures, tracebacks
sudo less /var/log/cloud-init.log

# runcmd output
sudo less /var/log/cloud-init-output.log

# Filter for errors only
sudo grep -iE "error|fail|traceback" /var/log/cloud-init.log

# See which modules ran at each stage
sudo grep "Running module" /var/log/cloud-init.log

# Reset cloud-init and re-run (for testing in a disposable VM)
sudo cloud-init clean --logs --seeds
sudo reboot
```

### Autoinstall debugging (during install)

```bash
# Installer has its own logs (on the target system during install)
sudo less /var/log/installer/cloud-init.log
sudo less /var/log/installer/curtin-install.log
sudo less /var/log/installer/subiquity-server-debug.log

# After install, look for autoinstall-specific failures
sudo journalctl -u cloud-init -u cloud-config -u cloud-final
```

Full user-data reference (every common module with 5 worked examples,
module ordering, idempotency, secrets note, datasource detection) — see
[`references/user-data-reference.md`](references/user-data-reference.md).

Full autoinstall reference (schema, storage layouts, LVM, ZFS,
autoinstall ISO build, serving over HTTP for PXE, 3 complete autoinstall
examples) — see
[`references/autoinstall-reference.md`](references/autoinstall-reference.md).

Full debugging guide (log layout, status decoding, re-run workflow) —
see [`references/debugging.md`](references/debugging.md).

---

## Typical workflows

### Workflow: "Validate this user-data before I deploy 10 servers with it"

```bash
# 1. YAML sanity
yamllint user-data.yaml

# 2. cloud-init schema validation
cloud-init schema --config-file user-data.yaml --strict

# 3. Visual review of the modules it will run
grep -E '^[a-z_]+:' user-data.yaml

# 4. Check that runcmd uses absolute paths
grep -A20 '^runcmd:' user-data.yaml

# 5. Boot one in a disposable cloud VM or LXD container
lxc launch ubuntu:24.04 test --config=user.user-data="$(cat user-data.yaml)"
lxc exec test -- cloud-init status --wait
lxc exec test -- cloud-init status --long
lxc delete test --force
```

### Workflow: "Why didn't my first-boot install nginx?"

```bash
sudo cloud-init status --long                     # overall result
sudo grep -A2 "packages" /var/log/cloud-init.log  # what package list was seen
sudo grep -iE "error|fail" /var/log/cloud-init-output.log | head -20

# Common causes:
#   - packages: - nginx   (YAML dash indentation wrong)
#   - package_update: false   (apt index is stale)
#   - package_upgrade: true + slow mirror = timeout
#   - apt sources unreachable
```

### Workflow: "Bootstrap linux-skills via cloud-init"

Put this as the final `runcmd` block in your production user-data:

```yaml
#cloud-config
users:
  - name: administrator
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... admin@example
packages:
  - git
  - curl
  - unattended-upgrades
runcmd:
  - sudo -u administrator bash -lc 'git clone https://github.com/<org>/linux-skills.git ~/.claude/skills'
  - sudo bash /home/administrator/.claude/skills/scripts/setup-claude-code.sh
  # Once install-skills-bin is available:
  # - sudo /usr/local/bin/install-skills-bin core
```

Full templates for a web server, Docker host, LXD guest, and database
server in [`references/user-data-reference.md`](references/user-data-reference.md).

### Workflow: "Build an autoinstall ISO"

```bash
# Write the autoinstall user-data (see references/autoinstall-reference.md)
# and a meta-data file (can be empty):
mkdir /tmp/autoinstall
cat > /tmp/autoinstall/user-data <<'EOF'
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: web01
    username: administrator
    password: '$6$...'     # crypt(3) hash
  ssh:
    install-server: true
    authorized-keys:
      - ssh-ed25519 AAAA...
  # ... rest of the autoinstall config
EOF

touch /tmp/autoinstall/meta-data

# Validate
cloud-init schema --config-file /tmp/autoinstall/user-data

# Serve over HTTP (trivial option)
cd /tmp/autoinstall && python3 -m http.server 3003
# Boot the installer with ds=nocloud-net;s=http://your-server:3003/
```

---

## Troubleshooting / gotchas

- **Indentation errors pass YAML parse but break cloud-init.** `yamllint`
  doesn't enforce cloud-init semantics. Use
  `cloud-init schema --config-file` as the real validator.
- **`runcmd` with a relative path fails silently.** Always use absolute
  paths: `/usr/bin/apt-get`, not `apt-get`. cloud-init's PATH is
  minimal at runcmd time.
- **Modules run once per instance-id.** Re-running a playbook requires
  `sudo cloud-init clean` (deletes state) + reboot. Without that,
  cloud-init thinks it's already done.
- **Long `package_upgrade: true` on a slow mirror times out.** The
  install appears to hang, then continue without the upgraded packages.
  Use `package_upgrade: false` for user-data where speed matters; run
  `unattended-upgrades` after boot instead.
- **Autoinstall storage config is unforgiving.** A typo in the `storage`
  section produces an install that hangs at partitioning. Validate with
  `cloud-init schema` and test in a VM before shipping the ISO.
- **`write_files` default encoding is text, not base64.** For binary
  files set `encoding: b64` explicitly.
- **`users:` module replaces the default user completely** unless you
  include `- default` as the first entry.

---

## References

- [`references/user-data-reference.md`](references/user-data-reference.md) —
  full user-data reference: every module with examples, 5 complete
  worked templates, idempotency and secrets notes.
- [`references/autoinstall-reference.md`](references/autoinstall-reference.md) —
  full autoinstall schema, storage, network, 3 complete examples.
- [`references/debugging.md`](references/debugging.md) — cloud-init
  logs, status decoding, re-run workflow, autoinstall debug.
- Book: *Ubuntu Server Guide* (Canonical) — cloud-init, autoinstall.
- Upstream: https://cloudinit.readthedocs.io/

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-cloud-init` installs:

| Task | Fast-path script |
|---|---|
| Validate user-data YAML + dry render of modules | `sudo sk-cloud-init-validate --file <path>` |
| Extract errors from cloud-init logs with module timeline | `sudo sk-cloud-init-debug` |

These are optional wrappers around `cloud-init schema`, `cloud-init
status`, and `cloud-init analyze`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-cloud-init
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-cloud-init-validate | scripts/sk-cloud-init-validate.sh | no | Validate cloud-init user-data YAML against the schema and render a dry summary of modules. |
| sk-cloud-init-debug | scripts/sk-cloud-init-debug.sh | no | Extract errors from cloud-init logs, classify by module, show runcmd exit codes and boot timeline. |
