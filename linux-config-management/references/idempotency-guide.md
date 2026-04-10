# Idempotency Guide for Ansible on Ubuntu and Debian

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

*Linux System Administration for the 2020s* (Hitchcock, 2022) states
the rule without qualification: "The number one thing that all
automation should be adhering to is ensuring that the code written is
idempotent. This effectively means that the code will only make a
change if the state does not match the required state from the
automation platform." Hitchcock even prescribes the self-check every
engineer should mutter while writing a task: *"Is my code
idempotent?"* This guide turns that question into a repeatable test.

## Table of contents

1. Why idempotency is non-negotiable
2. The idempotency test
3. Six common ways to break idempotency (and the fix for each)
4. The detect-act-verify pattern
5. `check_mode: no` and `changed_when: false`
6. Testing idempotency in CI
7. Worked example: converting a bash step to an idempotent task
8. Sources

---

## 1. Why idempotency is non-negotiable

An idempotent task describes a **state**, not a **sequence of actions**.
Running it once or a thousand times leaves the system in the same
place. That property is what lets you:

- Re-run a playbook safely after an aborted run, without worrying
  about what half-finished.
- Use `--check --diff` as a reliable drift detector (see
  `drift-detection.md`).
- Treat a server as **cattle** rather than a **pet** — if it dies,
  rebuild it by re-running the same playbook and trust that the
  result will be bit-for-bit equivalent.
- Let a second operator pick up a running change without having to
  reason about which tasks already happened.

When a task is not idempotent, every re-run is a coin flip. You lose
the check-mode drift detector. You lose confidence in rebuilds. You
are back to pet servers dressed up as automation.

Hitchcock's concrete example: updating a package. If the package is
already at the desired version, the task must do nothing. If it were
to reinstall blindly, the service restart handler would fire, causing
"a tiny outage" for no reason. Idempotency is not only about
correctness — it is about avoiding pointless change.

---

## 2. The idempotency test

The test is mechanical. Run the playbook twice in a row:

```bash
ansible-playbook -i 'localhost,' -c local playbooks/site.yml
ansible-playbook -i 'localhost,' -c local playbooks/site.yml
```

Read the second run's `PLAY RECAP`:

```
PLAY RECAP *********************************************
localhost : ok=23 changed=0 unreachable=0 failed=0 skipped=1
```

`changed=0` is the only acceptable result. Anything else means at
least one task is lying about state and you have a bug. Before
moving on, fix the task that reported `changed` on the second run.

A stronger version of the test runs the second pass in check mode:

```bash
ansible-playbook site.yml
ansible-playbook site.yml --check --diff
```

If the second run shows a diff, your playbook would churn the file
every time — classic non-idempotency.

---

## 3. Six common ways to break idempotency (and the fix)

### 3a. `command` or `shell` without `creates:` or `changed_when:`

The worst offender. Every `command` task reports `changed=true` on
every run unless you tell it otherwise.

**Wrong:**

```yaml
- name: Generate dhparam
  ansible.builtin.shell: openssl dhparam -out /etc/ssl/dhparam.pem 2048
```

**Right:**

```yaml
- name: Generate dhparam
  ansible.builtin.command: openssl dhparam -out /etc/ssl/dhparam.pem 2048
  args:
    creates: /etc/ssl/dhparam.pem
```

For read-only commands, set `changed_when: false`:

```yaml
- name: Read SELinux state
  ansible.builtin.command: getenforce
  register: selinux_state
  changed_when: false
```

For commands whose output determines change:

```yaml
- name: Reload sysctl only if settings differ
  ansible.builtin.command: sysctl -p /etc/sysctl.d/99-hardening.conf
  register: sysctl_out
  changed_when: sysctl_out.stdout_lines | length > 0
```

### 3b. `lineinfile` with an unanchored regex

`lineinfile` replaces *the last line matching the regex*. If the
regex matches nothing, it *appends*. On the second run it matches the
line it just inserted — fine. But if the regex is loose, it may match
*comments* or *unrelated lines*, silently rewriting them every run.

**Wrong:**

```yaml
- name: Set MaxAuthTries
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: 'MaxAuthTries'
    line: "MaxAuthTries 3"
```

The regex matches both `MaxAuthTries 6` and `# MaxAuthTries 6`. The
task edits one, then the other, alternating.

**Right:**

```yaml
- name: Set MaxAuthTries
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^\s*#?\s*MaxAuthTries\b'
    line: "MaxAuthTries 3"
    state: present
    validate: "/usr/sbin/sshd -t -f %s"
```

Even better: for files with more than a handful of settings, use
`ansible.builtin.template` and manage the whole file. `lineinfile` is
for surgical edits, not for maintaining config.

### 3c. `copy` or `template` with content that changes every run

If your template includes a timestamp, a UUID, a hostname-derived
random value, or anything non-deterministic, the rendered content
differs each run and the file is always `changed`.

**Wrong:**

```jinja
# Generated at {{ ansible_date_time.iso8601 }}
server_id = {{ 9999999 | random }}
```

**Right:**

```jinja
# {{ ansible_managed }}
server_id = {{ inventory_hostname | hash('md5') | truncate(8, True, '') }}
```

Use deterministic inputs: inventory vars, facts, hashes of stable
strings. Leave timestamps for comments that do not affect the
rendered output — and even then, understand you are giving up
idempotency on that file.

### 3d. Package `state: latest`

`state: latest` tells Ansible to run `apt-get install <pkg>` every
time, and apt may upgrade. On a system with a cron apt-update, the
task can report `changed` every single night as minor versions land.

**Wrong:**

```yaml
- name: Always latest nginx
  ansible.builtin.apt:
    name: nginx
    state: latest
```

**Right:**

```yaml
- name: Present nginx at baseline version
  ansible.builtin.apt:
    name: nginx
    state: present
```

If you genuinely want to track upstream, pin a version range with
`name: nginx=1.24.*` and accept the bump on purpose. Never let
`state: latest` hide version drift.

### 3e. Unconditional service restarts

**Wrong:**

```yaml
- name: Restart nginx
  ansible.builtin.systemd_service:
    name: nginx
    state: restarted
```

`state: restarted` fires on every run. Use handlers and notify from
the tasks that actually changed something:

**Right:**

```yaml
- name: Deploy nginx config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: reload nginx

handlers:
  - name: reload nginx
    ansible.builtin.systemd_service:
      name: nginx
      state: reloaded
```

Use `state: reloaded` rather than `restarted` when the daemon
supports it — it avoids dropping connections.

### 3f. Shell redirects writing files from inside `shell:`

**Wrong:**

```yaml
- name: Save timezone
  ansible.builtin.shell: date +%Z > /etc/timezone.current
```

Every run overwrites the file, and every run reports `changed`.

**Right:**

```yaml
- name: Read current timezone
  ansible.builtin.command: date +%Z
  register: current_tz
  changed_when: false

- name: Save timezone
  ansible.builtin.copy:
    dest: /etc/timezone.current
    content: "{{ current_tz.stdout }}\n"
    owner: root
    group: root
    mode: "0644"
```

`copy` with `content:` compares, writes only on difference, and
reports `changed` accurately.

---

## 4. The detect-act-verify pattern

Every non-trivial piece of automation follows the same three beats:

1. **Detect** — read the current state without modifying anything.
2. **Act** — only if detect shows a gap, apply the change.
3. **Verify** — confirm the desired state now holds.

Most `ansible.builtin` modules do all three internally. When you fall
back to `command`, you have to implement them yourself:

```yaml
# Detect
- name: Read current UFW default incoming policy
  ansible.builtin.command: ufw status verbose
  register: ufw_status
  changed_when: false

# Act (only when needed)
- name: Set UFW default incoming deny
  community.general.ufw:
    direction: incoming
    policy: deny
  when: "'Default: deny (incoming)' not in ufw_status.stdout"

# Verify
- name: Confirm UFW default is deny
  ansible.builtin.command: ufw status verbose
  register: ufw_verify
  changed_when: false
  failed_when: "'Default: deny (incoming)' not in ufw_verify.stdout"
```

When you write a task that does not fit this shape, stop and ask
whether the native module would have done all three for you.

---

## 5. `check_mode: no` and `changed_when: false`

Two escape hatches exist for tasks that either cannot run in check
mode or are always read-only:

```yaml
- name: Compute nginx config hash (always runs)
  ansible.builtin.command: sha256sum /etc/nginx/nginx.conf
  register: nginx_hash
  check_mode: false     # still runs during --check
  changed_when: false   # never reports changed
```

Use these surgically:

- `check_mode: false` — only on tasks that gather information needed
  by later tasks. If you sprinkle it, `--check` stops being a safe
  dry run.
- `changed_when: false` — on anything that only reads state (get,
  list, show, status, query).

Similarly, `diff: false` on a task suppresses the diff display (for
example, on a template that contains a large binary blob that would
drown the output).

---

## 6. Testing idempotency in CI

In CI (GitHub Actions, GitLab CI, Jenkins), run the playbook **twice**
and fail the build if the second run is not 0-changed.

```yaml
# .github/workflows/idempotency.yml — sketch
- name: First run
  run: ansible-playbook -i 'localhost,' -c local playbooks/site.yml

- name: Second run (must be 0-changed)
  run: |
    ansible-playbook -i 'localhost,' -c local playbooks/site.yml \
      | tee /tmp/second.log
    if ! grep -q 'changed=0' /tmp/second.log; then
      echo "Playbook is not idempotent — second run reported changes"
      exit 1
    fi
```

Also run `ansible-lint` for static checks — it catches several of
the patterns in section 3 before they hit CI:

```bash
ansible-lint playbooks/site.yml
```

The linter flags `state: latest`, shell-without-creates, hard-coded
secrets, and tab indentation, among others. Treat lint warnings as
errors in CI.

---

## 7. Worked example: converting a bash step to an idempotent task

Start with a bash snippet that onboards a new system user:

```bash
#!/bin/bash
useradd -m -s /bin/bash deploy
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
echo "ssh-ed25519 AAAA...peter" > /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
usermod -aG sudo deploy
```

Problems, run-after-run:

- `useradd` fails the second time with "user already exists".
- The `echo >` overwrites `authorized_keys` whether or not it changed.
- `usermod -aG sudo` is safe, but returns success every time — no
  visibility into *whether* the membership changed.

The idempotent Ansible equivalent:

```yaml
- name: Create deploy user
  ansible.builtin.user:
    name: deploy
    shell: /bin/bash
    create_home: true
    groups: sudo
    append: true
    state: present

- name: Install deploy authorized key
  ansible.posix.authorized_key:
    user: deploy
    key: "{{ lookup('file', 'files/deploy.pub') }}"
    state: present
    exclusive: false

- name: Lock down .ssh
  ansible.builtin.file:
    path: /home/deploy/.ssh
    state: directory
    owner: deploy
    group: deploy
    mode: "0700"
```

Now:

- `user` module checks whether the account exists before creating.
- `authorized_key` parses the file, compares entries, and adds only
  what is missing.
- `file` with `state: directory` sets the mode and ownership
  **only** if they differ.

Run it twice — the second run reports `changed=0` and the `PLAY
RECAP` is clean. The job is now safe to run from cron every hour if
you want, which is the whole point.

---

## Sources

- Hitchcock, Kenneth. *Linux System Administration for the 2020s*.
  Apress, 2022. Chapter 5 ("Automation — Idempotent Code" and
  "State Management"); the running argument across Chapters 3 and 5
  that shell scripts "by default do not really work well as an
  idempotent scripting language."
- Ansible community documentation — `ansible.builtin.user`,
  `ansible.builtin.lineinfile`, `ansible.builtin.command`,
  `ansible.posix.authorized_key`.
- `ansible-lint` rules — `no-changed-when`, `package-latest`,
  `no-handler`, `risky-shell-pipe`.
