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

## Use when

- Converting manual server state into repeatable Ansible or git-tracked configuration.
- Checking for configuration drift or validating idempotency.
- Establishing a safer operating model for `/etc` and other managed assets.

## Do not use when

- The task is a one-off emergency fix where full automation is unnecessary.
- The task is container or virtualization lifecycle work; use `linux-virtualization`.

## Required inputs

- The target host or config scope.
- Any playbooks, inventories, or `/etc` tracking repo involved.
- Whether the goal is adoption, drift detection, remediation, or idempotency review.

## Workflow

1. Establish the declared state source: playbooks, inventory, or tracked config.
2. Inspect the current live state and compare it to the declared baseline.
3. Run the matching workflow below for adoption, drift checks, or remediation.
4. Verify idempotency and capture what changed versus what remains unmanaged.

## Quality standards

- Prefer declarative, reviewable state over manual snowflake fixes.
- Make drift visible before changing production.
- Leave a clear path for repeatable re-application.

## Anti-patterns

- Using Ansible as a wrapper for ad-hoc shell without a declared target state.
- Applying changes without a dry-run or diff when one is available.
- Tracking config in git without excluding secrets or generated noise.

## Outputs

- A drift finding, remediation plan, or updated automation baseline.
- The commands or playbooks used to validate state.
- A verification result showing whether the system is now in lockstep.

## References

- [`references/ansible-patterns.md`](references/ansible-patterns.md)
- [`references/drift-detection.md`](references/drift-detection.md)
- [`references/idempotency-guide.md`](references/idempotency-guide.md)

**This skill is self-contained.** Every command below is a standard tool
(`ansible`, `ansible-playbook`, `git`, `etckeeper`, `dpkg`, `diff`). The
`sk-*` scripts in the **Optional fast path** section are convenience
wrappers — never required.

This skill owns the **modern sysadmin practice** of keeping a server's
actual state aligned with a declared state that lives in git. It
complements `linux-server-provisioning` (initial build) with ongoing
continuous alignment.

Informed by *Linux System Administration for the 2020s*: move from "pet
servers we hand-tune" to "cattle we rebuild from code." This skill
starts that journey without requiring a full immutable-infrastructure
rewrite.

It does **not** own:

- **Initial provisioning** — `linux-server-provisioning`.
- **First-boot from YAML** — `linux-cloud-init`.
- **Application deployment** — `linux-site-deployment`.

---

## When to use

- Adopting Ansible for a server that was hand-configured.
- Detecting configuration drift between declared state and actual state.
- Dry-running a playbook against localhost before committing.
- Tracking `/etc` in git for change auditing.
- Deciding "should we rebuild or patch this server?" (this skill is the
  answer).

## When NOT to use

- A one-off manual config change on a throwaway machine.
- Tasks owned by another skill (backups, firewall, deployment).

---

## Standing rules

1. **Every config change is recorded.** If it's not in a git-tracked
   playbook or a committed `/etc` snapshot, it didn't happen.
2. **Idempotency is the ultimate test.** Every Ansible task must be safe
   to run twice. Second run = zero changes.
3. **Drift is a first-class alert.** Run a drift check on weekly cron;
   any drift emails the operator. Unexpected drift means either the
   playbook is incomplete or someone edited the server directly — both
   are bugs.
4. **No manual edits on production.** If you SSH in and `nano`, you
   create a snowflake. Make the change in the playbook, test in
   staging, roll forward.
5. **Secrets never live in plain-text Ansible.** Use Ansible Vault or
   `sops` — see `linux-secrets`.
6. **Every playbook has a rollback plan.** At minimum, the previous git
   commit. For risky changes, a pre-run `/etc` snapshot.

---

## Quick reference — manual commands

### Install Ansible

```bash
# Preferred on Ubuntu: pipx (isolates pinned version)
sudo apt install pipx
pipx install --include-deps ansible
pipx ensurepath

# Alternative: apt (older version but packaged)
sudo apt install ansible

# Verify
ansible --version
```

### Local-only Ansible (managed host is localhost)

```bash
# Inventory-less run
ansible-playbook -c local -i 'localhost,' playbook.yml

# Or a minimal inventory file
cat > inventory.ini <<'EOF'
[local]
localhost ansible_connection=local
EOF

# Dry run with diff
ansible-playbook -i inventory.ini -c local playbook.yml --check --diff

# Real run
ansible-playbook -i inventory.ini -c local playbook.yml

# Idempotency test — run twice; second must show 0 changes
ansible-playbook -i inventory.ini -c local playbook.yml
ansible-playbook -i inventory.ini -c local playbook.yml   # MUST show "changed=0"
```

### Check mode tags and facts

```bash
# Run only tagged tasks
ansible-playbook playbook.yml --tags ssh --check --diff

# Skip specific tags
ansible-playbook playbook.yml --skip-tags slow --check

# Gather facts only (no changes)
ansible localhost -c local -m setup
ansible localhost -c local -m setup -a 'filter=ansible_distribution*'
```

### Tracking /etc in git (etckeeper)

```bash
sudo apt install etckeeper
# On install, etckeeper inits a git repo at /etc/.git and commits
sudo etckeeper vcs log | head
sudo etckeeper vcs status

# After a planned change
sudo etckeeper commit "hardening: set PermitRootLogin no"

# Show what changed between two points
sudo etckeeper vcs diff HEAD~5..HEAD
```

Manual git approach (without etckeeper):

```bash
sudo git -C /etc init
sudo git -C /etc add .
sudo git -C /etc commit -m "baseline snapshot $(date -Iseconds)"

# Later — see uncommitted drift
sudo git -C /etc status
sudo git -C /etc diff
```

### Comparing declared vs actual

```bash
# Package list drift
dpkg --get-selections > /tmp/pkgs-actual.txt
diff /root/declared-packages.txt /tmp/pkgs-actual.txt

# Config file drift — diff against a committed baseline
sudo git -C /etc diff HEAD -- ssh/sshd_config
sudo git -C /etc diff HEAD -- sysctl.conf sysctl.d/

# Ansible check mode as drift detection
ansible-playbook -i inventory.ini -c local site.yml --check --diff
# Any "changed: <n>" with n > 0 = drift
```

Full Ansible idioms (idempotent module usage, `creates:`/`removes:`,
`changed_when:`, handlers, roles, templates, Jinja2 filters, 3 complete
playbook examples for linux-skills bases) — see
[`references/ansible-patterns.md`](references/ansible-patterns.md).

Full drift detection strategy (etckeeper vs raw git, Ansible check mode,
AIDE integration, alerting, remediation workflow) — see
[`references/drift-detection.md`](references/drift-detection.md).

Full idempotency guide (common mistakes, how to fix them, two-run test,
CI enforcement) — see
[`references/idempotency-guide.md`](references/idempotency-guide.md).

---

## Typical workflows

### Workflow: Adopting Ansible on an existing server

```bash
# 1. Baseline /etc
sudo apt install etckeeper
sudo etckeeper init
sudo etckeeper commit "baseline for Ansible adoption"

# 2. Write the first playbook — pick something simple (SSH hardening,
#    sysctl, unattended-upgrades). Keep it idempotent.
mkdir -p ~/ansible/playbooks
nano ~/ansible/playbooks/ssh-hardening.yml

# 3. Dry run
ansible-playbook -c local -i 'localhost,' \
    ~/ansible/playbooks/ssh-hardening.yml --check --diff

# 4. If the diff matches intent, apply for real
ansible-playbook -c local -i 'localhost,' \
    ~/ansible/playbooks/ssh-hardening.yml

# 5. Run AGAIN to prove idempotency
ansible-playbook -c local -i 'localhost,' \
    ~/ansible/playbooks/ssh-hardening.yml
# Expected: "changed=0"

# 6. Commit to git and schedule drift check
cd ~/ansible && git init && git add . && git commit -m "initial"
```

### Workflow: Weekly drift check

```bash
# Via etckeeper
sudo etckeeper vcs status                     # anything uncommitted?
sudo etckeeper vcs diff                       # what's drifted

# Via Ansible check mode
ansible-playbook -c local -i 'localhost,' ~/ansible/site.yml \
    --check --diff --one-line | tee /tmp/drift.log

# If changed>0, investigate
grep "changed=" /tmp/drift.log
```

### Workflow: "Is my playbook idempotent?"

```bash
# First run: expect changes
ansible-playbook -c local -i 'localhost,' playbook.yml
# Output: "changed=7"

# Immediate second run: MUST be zero
ansible-playbook -c local -i 'localhost,' playbook.yml
# Output: "changed=0"

# If the second run shows changes, the playbook is buggy.
# Common causes: see references/idempotency-guide.md
```

### Workflow: Drift remediation

```bash
# 1. Drift detected on /etc/ssh/sshd_config
sudo git -C /etc diff HEAD -- ssh/sshd_config

# 2. Decide: is the drift legitimate?
#    - Yes → update the Ansible playbook to match new state, commit
#    - No  → re-run the playbook to restore, commit a note

# 3a. If legitimate, update playbook and re-test
vim ~/ansible/roles/ssh/tasks/main.yml
ansible-playbook -c local -i 'localhost,' ~/ansible/site.yml --check --diff

# 3b. If unwanted, restore from declared state
ansible-playbook -c local -i 'localhost,' ~/ansible/site.yml --tags ssh

# 4. Commit the resolution
sudo etckeeper commit "drift remediation: ssh config restored to baseline"
```

---

## Troubleshooting / gotchas

- **Playbook is "working" but second run shows changes.** Almost always
  one of: `shell:`/`command:` without `creates:` or `changed_when:`,
  `lineinfile` with a regex that matches multiple lines, `copy` with
  content that renders differently each time (timestamps). See
  `references/idempotency-guide.md`.
- **`ansible-playbook --check` doesn't catch everything.** Some modules
  (notably `command`/`shell`) are conservative in check mode. They
  report "would run" regardless of actual state. Use `creates:` /
  `removes:` for stronger check-mode accuracy.
- **`etckeeper` fails on a large commit.** The initial commit can be
  huge. If git complains, configure `http.postBuffer` or commit in
  stages.
- **`local_action` with `become: yes` prompts for a password.** Use
  `ansible_become_password` from Vault, or run the playbook with
  `--ask-become-pass`.
- **Ansible installed via `apt` is too old for a module you need.**
  Switch to `pipx install ansible` for the latest, or enable the
  Ansible PPA.
- **Handlers don't fire on a failed task.** If a task fails
  mid-playbook, its `notify:` handlers are skipped. Use `force_handlers:
  yes` in the play if you need them to run anyway.

---

## References

- [`references/ansible-patterns.md`](references/ansible-patterns.md) —
  full Ansible reference: idempotent modules, roles, templates, Jinja2,
  3 complete playbook examples.
- [`references/drift-detection.md`](references/drift-detection.md) —
  etckeeper, Ansible check mode, AIDE, cron-scheduled checks,
  remediation workflow.
- [`references/idempotency-guide.md`](references/idempotency-guide.md) —
  common idempotency mistakes, how to fix them, CI enforcement.
- Book: *Linux System Administration for the 2020s* — idempotency,
  drift, cattle not pets.
- Ansible docs: https://docs.ansible.com/

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-config-management` installs:

| Task | Fast-path script |
|---|---|
| Compare key configs/packages vs git-tracked state | `sudo sk-drift-check` |
| Run an Ansible playbook in check mode with clean summary | `sudo sk-ansible-dry-run --playbook <file>` |
| Initialize and verify /etc tracking, stage + commit | `sudo sk-etc-track [--commit]` |

These are optional wrappers around `ansible-playbook`, `etckeeper`, and
`git`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-config-management
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-drift-check | scripts/sk-drift-check.sh | no | Compare key config files and package list against git-tracked declared state; report drift with diffs. |
| sk-ansible-dry-run | scripts/sk-ansible-dry-run.sh | no | Run an Ansible playbook in `--check --diff` mode against localhost with a clean summary of would-be changes. |
| sk-etc-track | scripts/sk-etc-track.sh | no | Initialize git tracking for `/etc`, verify it's clean, optionally auto-stage + commit. |
