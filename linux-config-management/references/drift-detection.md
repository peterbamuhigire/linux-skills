# Drift Detection for Ubuntu and Debian Servers

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

*Linux System Administration for the 2020s* (Hitchcock, 2022) warns
about the snowflake server: a host that has drifted so far from any
documented state that "no one in the organization knows what the
system does or how to rebuild it." Drift is how a well-provisioned
server turns into a snowflake. This reference is about catching drift
early, classifying it, and deciding — fast — whether to accept the
drift into the playbook or revert it.

## Table of contents

1. What drift is and why it happens
2. Four places to measure drift
3. Alerting patterns
4. Remediation workflow
5. The two-way door test
6. Example: etckeeper on Debian and Ubuntu
7. Example: nightly Ansible drift cron
8. Example: weekly self-check playbook with email
9. Sources

---

## 1. What drift is and why it happens

Drift is the delta between **declared state** (what your playbook
says should be true) and **actual state** (what the server is right
now). Hitchcock puts the goal plainly: an automation platform should
"constantly check the systems they manage for its current state to
see if anything has been changed. When state change is detected, the
configuration is updated to match the desired state." Ansible runs on
demand rather than continuously, so you need to schedule the check
yourself.

Drift sources, ranked by how often they actually bite:

- **Manual SSH edits** — someone `nano`s a config file during an
  incident and never codifies it. The book calls this the number one
  path to snowflakes.
- **Package upgrades replacing config files** — `apt` prompts with
  "configuration file changed, keep or replace?" and accepts the
  maintainer's new version under unattended-upgrades.
- **Services writing state under `/etc`** — `cloud-init`, `netplan`
  generators, `systemd-resolved`, `fail2ban` all drop files you did
  not put there.
- **Runaway cron jobs** — a script you forgot about mutates `/etc`
  or `/opt` on a schedule.
- **Installed-then-removed packages** — `dpkg` leaves `.dpkg-dist`
  and `.dpkg-old` files scattered.
- **Developers SSHing to "just try something"** — the hardest to
  detect, because the drift looks exactly like legitimate admin work.

Drift is a **bug**. Either the playbook is incomplete (the admin's
fault) or the server was edited behind Ansible's back (the operator's
fault). Both are bugs.

---

## 2. Four places to measure drift

No single technique catches everything. Stack at least two.

### 2a. Git-tracked `/etc/` via etckeeper

`etckeeper` turns `/etc` into a git repo, auto-commits before and
after every `apt` operation, and lets a nightly cron commit anything
else that changed:

```bash
sudo apt install -y etckeeper
sudo etckeeper init
sudo etckeeper commit "initial state"
```

From then on:

```bash
sudo etckeeper unclean          # exits non-zero if /etc has changes
sudo git -C /etc log --oneline  # history of every change
sudo git -C /etc diff HEAD~1    # what just changed
```

This is the ground truth you want. It has no opinion on *why* the file
changed — it just records that it did.

A `/etc/.gitignore` (etckeeper writes one for you; augment it) avoids
recording noise:

```gitignore
# high-churn files that are not really config
*.dpkg-new
*.dpkg-old
*.dpkg-dist
*.ucf-new
*.ucf-old
*.ucf-dist

# secrets
shadow
shadow-
gshadow
gshadow-

# generated or runtime state
/mtab
/resolv.conf
/ssh/ssh_host_*
/ssl/private/*
/blkid.tab
/adjtime
```

### 2b. Ansible `--check --diff` on a schedule

Even with etckeeper, you want to ask the stronger question: *does the
actual state still match the playbook?* Run the playbook in check mode:

```bash
ansible-playbook -i 'localhost,' -c local \
  /etc/ansible/playbooks/site.yml \
  --check --diff
```

Zero changes means the server still matches the playbook. Anything
else is drift that Ansible would fix on a real run. Capture the output
and alert on non-zero diffs — example in section 7.

This catches drift *relative to your declared state*, which is a more
useful signal than "something under /etc changed" because it ignores
files you never claimed to manage.

### 2c. File hash baseline via AIDE

AIDE takes a cryptographic hash of every file in a set of paths,
stores the database, and later compares the live filesystem against
that snapshot. It is the security-side tool — it catches drift you
care about for tamper-detection reasons (binaries, libraries, cron
dirs). The `linux-intrusion-detection` skill owns AIDE configuration;
this skill just points at it. A nightly AIDE run that emails any
deviation gives you a third, independent sensor.

### 2d. Package state with `dpkg` and `apt-mark`

Drift is not only files. "Someone installed `tcpdump` on the web
server" is drift too. Baseline the package set:

```bash
dpkg --get-selections > /var/lib/drift/packages.baseline
apt-mark showmanual > /var/lib/drift/manual.baseline
```

And check nightly:

```bash
diff /var/lib/drift/packages.baseline <(dpkg --get-selections)
diff /var/lib/drift/manual.baseline  <(apt-mark showmanual)
```

Wire this into the same alerting path as the file drift check.

---

## 3. Alerting patterns

Drift alerts should hit the same path as your other ops alerts — email,
Slack webhook, Alertmanager, whichever the `linux-observability` skill
configured. A useful classification:

| Severity | What triggers it | Who pages |
|---|---|---|
| **Critical** | Drift in `/etc/ssh/`, `/etc/sudoers*`, `/etc/pam.d/`, `/etc/shadow` metadata, UFW rules, `iptables`-save output | On-call operator — now |
| **High** | Drift in any file Ansible manages (non-zero `--check --diff`) | Email the operator, review next morning |
| **Informational** | Drift in high-churn files (log configs, timestamp files) you decided to track anyway | Weekly digest |

The way to implement tiers is to run **two** checks:

1. A narrow critical check — a short list of paths, run hourly.
2. A broad high check — the full Ansible playbook in `--check`, run
   nightly.

The critical check should be cheap. Something like:

```bash
sudo git -C /etc diff --quiet HEAD -- \
    ssh/sshd_config \
    sudoers sudoers.d \
    pam.d \
    ufw
```

Exit code 1 means one of those files has an uncommitted change —
wake someone up.

---

## 4. Remediation workflow

You just got the alert. Two paths, and only two:

```
drift detected
     │
     ▼
 investigate
     │
     ├──► legitimate change      ──►  update the playbook, commit, re-run
     │    (accept the drift)
     │
     └──► unauthorized change    ──►  re-run the playbook to revert,
          (revert the drift)          open an incident ticket
```

The investigation has to answer three questions:

1. **Who touched it?** `auth.log`, `sudo.log`, shell history, and
   `last` will tell you the session. If it was an Ansible run on a
   different control node, the logs will show the `become` session
   with `ansible-*` in the command.
2. **What changed?** `git diff` in `/etc/.git` (etckeeper) or the
   Ansible check-mode diff.
3. **Is it safe to revert?** See section 5.

If the change is legitimate — say, you hand-edited `sshd_config` to
enable a new subsystem during an outage — update the playbook to
declare the same thing, then re-run. The server is now green: the
playbook and reality agree again.

If the change is unauthorized, re-run the playbook without `--check`.
Ansible puts the file back. Then file an incident: how did the
attacker or operator make the change, and how do you prevent it?

---

## 5. The two-way door test

Amazon calls reversible decisions "two-way doors." Apply that here:

> **Can you safely revert this change by re-running the playbook?**

If yes: revert is a two-way door. If you made the wrong call, the
operator will notice and update the playbook. Low risk, act fast.

If no: revert is a one-way door. Re-running the playbook would delete
data, drop connections mid-transaction, or leave the system
unreachable. **Stop.** Get a human in the loop. Examples of one-way
doors:

- Ansible would remove `/etc/ssh/sshd_config` entirely because the
  template is missing on the control node.
- Ansible would reinstall `postgresql` from scratch because a
  `state: present` gap somewhere triggers a removal.
- The firewall play would deny the port you are currently SSH'd into.

The practical rule: **always** run `--check --diff` before running
for real when the drift report arrives. The diff tells you whether
the revert is a one-way door.

---

## 6. Example: etckeeper on Debian and Ubuntu

Set-up, idempotent to run twice:

```bash
sudo apt install -y etckeeper
[ -d /etc/.git ] || sudo etckeeper init
sudo etckeeper commit "baseline $(date +%F)"
```

`etckeeper.conf` defaults are fine on Ubuntu — auto-commit on apt and
a daily `cron.daily` commit. Verify with:

```bash
sudo systemctl list-timers | grep etckeeper
ls /etc/cron.daily/etckeeper
cat /etc/etckeeper/etckeeper.conf
```

Extend `/etc/.gitignore` with the block from section 2a. After editing
the ignore file, commit it so etckeeper stops tracking those paths:

```bash
sudo etckeeper commit "tighten .gitignore"
```

Day-to-day checks:

```bash
# any uncommitted change in /etc?
sudo etckeeper unclean && echo "drift!" || echo "clean"

# what changed since yesterday?
sudo git -C /etc log --since="1 day ago" --stat
```

The `sk-etc-track` helper wraps these commands so operators do not
have to remember them.

---

## 7. Example: nightly Ansible drift cron

Install this via a playbook (see `ansible-patterns.md` section 16c
for the Ansible way). What the cron job actually runs:

```cron
# /etc/cron.d/ansible-drift
# Nightly drift check against the declared playbook state.
17 3 * * * root /usr/local/sbin/run-drift-check
```

`/usr/local/sbin/run-drift-check` is a thin wrapper around Ansible in
check mode. It must:

- Run the playbook with `--check --diff`.
- Capture the full output to a dated log file.
- Exit non-zero if the playbook reports any `changed` tasks (drift).
- Email the diff to the operator on non-zero exit.

The wrapper itself is shell and belongs in the skill's `scripts/`
directory, not this reference. What matters here is the **contract**:
zero exit means the server matches declared state; non-zero means
drift and the payload is the diff.

Rotate logs with logrotate:

```
/var/log/drift/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
```

---

## 8. Example: weekly self-check playbook with email

A playbook that runs *itself* in check mode, captures the diff, and
emails the result. Useful when you do not have a metrics stack yet
and want a single-file solution.

```yaml
---
- name: Weekly self drift check
  hosts: localhost
  connection: local
  become: true
  gather_facts: true

  vars:
    drift_report: /var/log/drift/weekly-{{ ansible_date_time.date }}.log
    drift_email: ops@example.com

  tasks:
    - name: Ensure log directory exists
      ansible.builtin.file:
        path: /var/log/drift
        state: directory
        owner: root
        group: root
        mode: "0750"

    - name: Run the real playbook in check mode
      ansible.builtin.command: >
        ansible-playbook
        -i 'localhost,' -c local
        /etc/ansible/playbooks/site.yml
        --check --diff
      register: drift_run
      changed_when: false
      failed_when: false
      check_mode: false

    - name: Save the check-mode output
      ansible.builtin.copy:
        dest: "{{ drift_report }}"
        content: |
          Drift report — {{ inventory_hostname }} — {{ ansible_date_time.iso8601 }}
          Exit code: {{ drift_run.rc }}

          === STDOUT ===
          {{ drift_run.stdout }}

          === STDERR ===
          {{ drift_run.stderr }}
        owner: root
        group: root
        mode: "0640"

    - name: Detect drift
      ansible.builtin.set_fact:
        drift_found: "{{ 'changed=' in drift_run.stdout and 'changed=0' not in drift_run.stdout }}"

    - name: Email the drift report
      community.general.mail:
        host: localhost
        port: 25
        to: "{{ drift_email }}"
        subject: "[DRIFT] {{ inventory_hostname }} — {{ ansible_date_time.date }}"
        body: |
          Ansible check-mode run detected drift on {{ inventory_hostname }}.

          Review the attached log and either update the playbook or
          re-run it without --check to revert.

          Report: {{ drift_report }}
        attach:
          - "{{ drift_report }}"
      when: drift_found | bool
```

Schedule it weekly:

```yaml
- name: Schedule the self drift check
  ansible.builtin.cron:
    name: "weekly self drift check"
    weekday: "1"
    minute: "30"
    hour: "4"
    user: root
    job: "/usr/bin/ansible-playbook -i 'localhost,' -c local /etc/ansible/playbooks/drift-self-check.yml"
```

Notice how the drift-detection playbook itself is subject to the
drift-detection playbook — turtles all the way down is the point.
If someone disables the cron job, the next scheduled run will not
happen, and the `--check --diff` nightly run (section 7) will flag
the missing cron entry as drift. Two independent sensors watching
each other.

---

## Sources

- Hitchcock, Kenneth. *Linux System Administration for the 2020s*.
  Apress, 2022. Chapter 3 ("Estate Management") on snowflakes and
  configuration drift; Chapter 5 ("Automation — State Management").
- `etckeeper` manual pages and `/etc/etckeeper/etckeeper.conf`.
- AIDE — see the `linux-intrusion-detection` skill.
- `ansible.builtin.command`, `ansible.builtin.cron`, `community.general.mail`.
