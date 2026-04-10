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

This skill owns **first-boot provisioning from YAML** — cloud-init user-data
on cloud images and Ubuntu's autoinstall flow on the installer. It is the
mechanism that takes a blank Ubuntu image and turns it into a server ready
for `sk-provision-fresh` to finish.

It does **not** own:

- **Interactive provisioning after first boot** — that's
  `linux-server-provisioning`.
- **Cloud provider APIs** (creating the VM in the first place) — out of
  scope.
- **Configuration management over time** — that's `linux-config-management`.

Informed by the Canonical *Ubuntu Server Guide* (cloud-init, autoinstall
chapters).

---

## When to use

- Writing a `user-data` YAML for a cloud image (AWS, DigitalOcean, Hetzner).
- Writing an Ubuntu `autoinstall` config for a new installer ISO.
- Validating user-data before feeding it to a cloud provider.
- Debugging why a first-boot didn't install packages or create users.
- Extracting errors from `/var/log/cloud-init*.log` on a provisioned host.

## When NOT to use

- Setting up a server that's already been provisioned and just needs day-2
  changes — use `linux-config-management` (Ansible) for ongoing work.
- Running manual steps on an existing server — use the relevant sk-* script
  directly.

---

## Standing rules

1. **Validate every user-data file before using it.** `sk-cloud-init-validate`
   runs the schema check and a dry render. A broken user-data silently
   ignores modules and you end up with an under-configured server.
2. **Never put secrets in plain-text user-data.** cloud-init caches it
   under `/var/lib/cloud/` where it can be read later. Use vaulted values
   or post-boot pulls from a secret store.
3. **`runcmd` is last resort.** Prefer first-class modules (`users`,
   `packages`, `write_files`, `ssh_authorized_keys`) where possible. They
   are idempotent and log cleanly.
4. **Always install `linux-skills` in `runcmd`.** The very last step of
   every provisioning user-data should clone the repo into
   `~/.claude/skills/` and run `install-skills-bin core`. Templates live in
   `references/user-data-templates/`.
5. **Debug with `/var/log/cloud-init.log` and
   `/var/log/cloud-init-output.log`.** `sk-cloud-init-debug` aggregates and
   classifies them.
6. **Autoinstall uses a different schema** than runtime user-data. Don't
   cross them over — the installer's cloud-init runs in a restricted
   environment.

---

## Typical workflows

### "Validate this user-data before I deploy 10 servers with it"

```bash
sk-cloud-init-validate --file ./user-data.yaml
```

Runs `cloud-init schema --config-file`, then renders the module list, flags
deprecated modules, and checks that `runcmd` commands have absolute paths.

### "Why didn't my first-boot install nginx?"

```bash
sudo sk-cloud-init-debug
```

Reads `/var/log/cloud-init.log` and `/var/log/cloud-init-output.log`,
classifies errors, shows which modules failed and why, and prints the
full `runcmd` exit codes.

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-cloud-init
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-cloud-init-validate | scripts/sk-cloud-init-validate.sh | no | Validate cloud-init user-data YAML against the schema and render a dry summary of modules. |
| sk-cloud-init-debug | scripts/sk-cloud-init-debug.sh | no | Extract errors from cloud-init logs, classify by module, show runcmd exit codes and boot timeline. |

---

## See also

- `linux-server-provisioning` — `sk-provision-fresh` for interactive
  post-boot setup.
- `linux-virtualization` — cloud-init used to launch LXD containers.
- `linux-config-management` — for day-2 config changes.
