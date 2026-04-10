---
name: linux-config-management
description: Keep Ubuntu/Debian servers in lockstep with declared state using Ansible and git-tracked config. Use for drift detection, dry-running playbooks, snapshotting /etc, and shifting from pet-server management to reproducible automation.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Configuration Management

This skill owns the **modern sysadmin practice** of keeping a server's
actual state aligned with a declared state that lives in git. It complements
`linux-server-provisioning` (initial build) with ongoing continuous
alignment.

Informed by *Linux System Administration for the 2020s*: move from "pet
servers we hand-tune" to "cattle we rebuild from code." This skill starts
that journey without requiring a full immutable-infrastructure rewrite.

It does **not** own:

- **Initial provisioning** — that's `linux-server-provisioning`.
- **First-boot setup from YAML** — that's `linux-cloud-init`.
- **Application deployment** — that's `linux-site-deployment`.

---

## When to use

- Adopting Ansible for a server that was previously hand-configured.
- Detecting configuration drift between declared state and actual state.
- Dry-running a playbook against localhost before committing.
- Tracking `/etc` in git for change auditing.
- Debating "should we rebuild or patch this server?" (this skill is the
  answer).

## When NOT to use

- A one-off manual config change on a throwaway machine.
- Tasks that clearly belong to another skill (running a backup → DR, setting
  up UFW → firewall-ssl).

---

## Standing rules

1. **Every config change is recorded.** If it's not in a git-tracked
   playbook or a committed `/etc` snapshot, it didn't happen. `sk-etc-track`
   makes this a two-command habit.
2. **Idempotency is the ultimate test.** Every Ansible task must be safe
   to run twice. `sk-ansible-dry-run` calls `--check --diff` — a clean
   second run means the task is idempotent.
3. **Drift is a first-class alert.** Run `sk-drift-check` in cron weekly;
   any drift emails the operator. Unexpected drift means either the
   playbook is incomplete or someone edited the server directly — both
   are bugs.
4. **No manual edits on production.** If you SSH in and `nano`, you
   create a snowflake. Make the change in the playbook, test in staging,
   roll forward.
5. **Secrets never live in Ansible plain text.** Use Ansible Vault or
   `age`/`sops` — see `linux-secrets`.
6. **Every playbook has a rollback plan.** At minimum, the previous git
   commit. For risky changes, a pre-run `sk-config-snapshot` that can be
   restored.

---

## Typical workflows

### Adopting Ansible on an existing server

1. `sudo sk-etc-track --init` — create a git repo at `/etc/.git` and
   commit the current state.
2. Write the first playbook: whatever you can codify (ssh hardening,
   sysctl, unattended-upgrades, UFW). Keep it idempotent.
3. `sudo sk-ansible-dry-run --playbook site.yml` — see what it wants to
   change. If that's empty, your playbook matches reality.
4. Commit playbook to git.
5. Set `sk-drift-check` on weekly cron.

### Weekly drift check

```bash
sudo sk-drift-check
```

Compares key files (SSH, sysctl, firewall, crontabs, unattended-upgrades)
against the tracked state and reports anything that has moved.

### "Is my playbook idempotent?"

```bash
sudo sk-ansible-dry-run --playbook ssh-hardening.yml
# first run shows changes
sudo ansible-playbook ssh-hardening.yml
sudo sk-ansible-dry-run --playbook ssh-hardening.yml
# second run must show zero changes — if not, the playbook is buggy
```

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-config-management
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-drift-check | scripts/sk-drift-check.sh | no | Compare key config files and package list against git-tracked declared state; report drift with diffs. |
| sk-ansible-dry-run | scripts/sk-ansible-dry-run.sh | no | Run an Ansible playbook in `--check --diff` mode against localhost with a clean summary of would-be changes. |
| sk-etc-track | scripts/sk-etc-track.sh | no | Initialize git tracking for `/etc`, verify it's clean, optionally auto-stage + commit with a message. |

---

## See also

- `linux-server-provisioning` — for the initial build step.
- `linux-cloud-init` — for first-boot YAML.
- `linux-secrets` — for vaulted secrets used by playbooks.
- `linux-observability` — drift alerts plug into the same alerting path.
