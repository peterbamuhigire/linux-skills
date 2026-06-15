# Ansible Patterns for Ubuntu and Debian

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Ansible is the lever that turns a hand-tuned snowflake server into a
reproducible, git-tracked system. *Linux System Administration for the
2020s* (Hitchcock, 2022) frames it bluntly: "we no longer are Linux
sysadmins, we are now automation engineers." This reference distils the
patterns that hold up on Ubuntu 22.04 LTS and Debian 12 with modern
Ansible (2.15 and later, the `ansible-core` plus collections world).
Treat every snippet as something you can paste into a play and run.

## Table of contents

1. Installing Ansible on Ubuntu and Debian
2. The `ansible.cfg` you should ship
3. Inventory: INI versus YAML
4. Ansible Vault and where secrets live
5. Playbook anatomy: plays, tasks, handlers, blocks
6. The idempotent module catalogue
7. Avoiding `command` and `shell`
8. Roles and project layout
9. Running locally without SSH
10. Check mode and diff
11. Tags
12. Facts and fact caching
13. Handlers, `listen`, and ordering
14. Templates and Jinja2
15. Error handling: `rescue`, `always`, fatal errors
16. Three complete playbooks
17. Sources

---

## 1. Installing Ansible on Ubuntu and Debian

You have two real choices. Pick one consciously, then commit to it.

### Option A — apt (the book's recommendation)

```bash
sudo apt update
sudo apt install -y ansible
```

Hitchcock notes that "installing ansible through a package management
system is the recommended approach as this not only installs the ansible
binary but also prepares your linux system with all the other supporting
ansible configuration files." On Ubuntu 22.04 you get a recent enough
`ansible-core` for everyday work. `/etc/ansible/` is created for you,
along with sane defaults. The cost is version lag — distro packages
trail upstream by several months.

### Option B — pipx (the modern Python way)

```bash
sudo apt install -y pipx
pipx ensurepath
pipx install --include-deps ansible
```

`pipx` installs Ansible into an isolated venv per user, leaves system
Python alone, and lets you upgrade on your own schedule:

```bash
pipx upgrade ansible
```

Use pipx when you need a newer release than the distro ships, when
you want each operator's home directory to be self-contained, or when
the target host runs in a CI runner that you do not control.

> **Rule of thumb.** apt for production control nodes you treat as
> long-lived. pipx for laptops, ephemeral CI workers, and any host
> where you want pinned versions per project.

### Add the collections you need

`ansible-core` ships only `ansible.builtin`. Everything else is a
collection you install explicitly:

```bash
ansible-galaxy collection install community.general ansible.posix community.crypto
```

Pin them in `requirements.yml` so every operator gets the same set:

```yaml
---
collections:
  - name: community.general
    version: ">=8.0.0,<9.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
  - name: community.crypto
    version: ">=2.15.0"
```

Install with `ansible-galaxy collection install -r requirements.yml`.

---

## 2. The `ansible.cfg` you should ship

Drop this at the root of your playbook repo. Ansible reads
`./ansible.cfg` first, then `~/.ansible.cfg`, then `/etc/ansible/ansible.cfg`.
Project-local always wins, which is what you want.

```ini
[defaults]
inventory          = ./inventory/hosts.yml
roles_path         = ./roles
collections_path   = ./collections
host_key_checking  = True
forks              = 10
stdout_callback    = yaml
callbacks_enabled  = profile_tasks, timer
retry_files_enabled = False
interpreter_python = auto_silent
gathering          = smart
fact_caching       = jsonfile
fact_caching_connection = ./.ansible_facts
fact_caching_timeout = 7200

[ssh_connection]
pipelining         = True
control_path       = /tmp/ansible-%%h-%%p-%%r
ssh_args           = -o ControlMaster=auto -o ControlPersist=60s

[privilege_escalation]
become             = False
become_method      = sudo
become_user        = root
become_ask_pass    = False
```

Notable choices:

- `host_key_checking = True` — never silently trust a server. Pre-seed
  `~/.ssh/known_hosts` instead.
- `stdout_callback = yaml` makes diffs and errors readable.
- `pipelining = True` halves the number of SSH connections per task.
- `fact_caching = jsonfile` survives between runs so you can skip
  fact-gathering on quick re-runs.
- `become = False` at the file level — opt in per play with `become: true`.

---

## 3. Inventory: INI versus YAML

INI is what the book shows and what most tutorials use:

```ini
[webservers]
web1.example.com
web2.example.com

[database]
db1.example.com

[production:children]
webservers
database
```

YAML is structurally richer and the format you should standardise on
once your inventory has more than ten hosts:

```yaml
---
all:
  children:
    webservers:
      hosts:
        web1.example.com:
          ansible_user: deploy
        web2.example.com:
          ansible_user: deploy
      vars:
        nginx_worker_processes: 4
    database:
      hosts:
        db1.example.com:
      vars:
        postgres_version: 16
    production:
      children:
        webservers:
        database:
```

YAML lets you nest group vars, attach per-host overrides, and reference
the file from `group_vars/` and `host_vars/` directories without
duplication. Use `ansible-inventory --list -y` to render the merged view.

---

## 4. Ansible Vault and where secrets live

Plain-text secrets in a playbook are a bug. Use Vault:

```bash
ansible-vault create group_vars/production/vault.yml
ansible-vault edit  group_vars/production/vault.yml
ansible-vault rekey group_vars/production/vault.yml
```

Convention: prefix vaulted variables with `vault_`, then expose them
through a non-secret variable file:

```yaml
# group_vars/production/vars.yml
postgres_password: "{{ vault_postgres_password }}"
deploy_user_pubkey: "{{ vault_deploy_user_pubkey }}"
```

Run with `--ask-vault-pass` interactively, or `--vault-password-file
~/.vault_pass` in CI. Keep the password file out of git
(`.gitignore` it) and out of the repo's directory tree.

For multi-environment setups use vault IDs:

```bash
ansible-playbook site.yml \
  --vault-id dev@~/.vault_dev \
  --vault-id prod@~/.vault_prod
```

Anything truly sensitive — TLS private keys, SSH host keys, database
master passwords — belongs in Vault or in a dedicated secrets store
(`age`, `sops`, HashiCorp Vault). See the `linux-secrets` skill.

---

## 5. Playbook anatomy: plays, tasks, handlers, blocks

A playbook is a list of *plays*. A play targets hosts and runs *tasks*
in order. Tasks can notify *handlers*, which run once at the end of
the play. *Blocks* group tasks for shared error handling and
conditionals.

```yaml
---
- name: Harden SSH on web tier
  hosts: webservers
  become: true
  gather_facts: true

  vars:
    ssh_allowed_users:
      - deploy
      - peter

  pre_tasks:
    - name: Verify we are on Debian or Ubuntu
      ansible.builtin.assert:
        that: ansible_os_family == "Debian"

  tasks:
    - name: SSH config block
      block:
        - name: Deploy sshd_config
          ansible.builtin.template:
            src: sshd_config.j2
            dest: /etc/ssh/sshd_config
            owner: root
            group: root
            mode: "0644"
            validate: "/usr/sbin/sshd -t -f %s"
          notify: restart sshd
      rescue:
        - name: Roll back sshd_config from backup
          ansible.builtin.copy:
            src: /etc/ssh/sshd_config.bak
            dest: /etc/ssh/sshd_config
            remote_src: true

  handlers:
    - name: restart sshd
      ansible.builtin.systemd_service:
        name: ssh
        state: restarted
```

The `validate:` parameter is your safety net — Ansible writes the
template to a temp file and runs `sshd -t` against it before swapping
it in. A typo never reaches `/etc/ssh/sshd_config`.

---

## 6. The idempotent module catalogue

Stick to these. Every one of them is idempotent by design and uses the
fully-qualified `ansible.builtin` namespace to dodge collection
ambiguity.

```yaml
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Copy a static file
  ansible.builtin.copy:
    src: files/motd
    dest: /etc/motd
    owner: root
    group: root
    mode: "0644"

- name: Render a templated config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: "0644"
    validate: "nginx -t -c %s"
  notify: reload nginx

- name: Ensure a single setting in a file
  ansible.builtin.lineinfile:
    path: /etc/sysctl.d/99-hardening.conf
    regexp: '^net\.ipv4\.tcp_syncookies\s*='
    line: "net.ipv4.tcp_syncookies = 1"
    create: true
    owner: root
    group: root
    mode: "0644"

- name: Ensure a managed block in a file
  ansible.builtin.blockinfile:
    path: /etc/hosts
    marker: "# {mark} ANSIBLE MANAGED — internal hosts"
    block: |
      10.0.0.10 db1.internal
      10.0.0.11 cache1.internal

- name: Manage a service
  ansible.builtin.systemd_service:
    name: nginx
    state: started
    enabled: true
    daemon_reload: true

- name: Open a firewall port
  community.general.ufw:
    rule: allow
    port: "443"
    proto: tcp

- name: Schedule a cron job
  ansible.builtin.cron:
    name: "nightly drift check"
    minute: "17"
    hour: "3"
    user: root
    job: "/usr/local/bin/sk-drift-check >/var/log/drift-check.log 2>&1"

- name: Create a system user
  ansible.builtin.user:
    name: deploy
    shell: /bin/bash
    groups: sudo
    append: true
    create_home: true
    state: present

- name: Create a group
  ansible.builtin.group:
    name: webops
    state: present

- name: Set a directory's permissions
  ansible.builtin.file:
    path: /var/www/site
    state: directory
    owner: deploy
    group: www-data
    mode: "0755"
    recurse: false

- name: Mount a filesystem
  ansible.posix.mount:
    path: /var/backups
    src: UUID=1234-abcd
    fstype: ext4
    opts: defaults,noatime
    state: mounted
```

---

## 7. Avoiding `command` and `shell`

Hitchcock's *idempotency* mantra is the rule, and `command`/`shell`
are the most common way to break it. They run every time, mark the
task `changed`, and have no built-in concept of state. Reach for them
last, and when you do, **always** make them idempotent with one of:

- `creates:` — skip the task if a file already exists.
- `removes:` — skip the task if a file is already gone.
- `changed_when:` — derive `changed` from the command's output.
- `failed_when:` — derive `failed` from the command's output.

Bad:

```yaml
- name: Generate the SSH host key
  ansible.builtin.shell: ssh-keygen -A
```

Good:

```yaml
- name: Generate the SSH host keys
  ansible.builtin.command: ssh-keygen -A
  args:
    creates: /etc/ssh/ssh_host_ed25519_key
```

Read-only command:

```yaml
- name: Capture kernel version
  ansible.builtin.command: uname -r
  register: kernel_version
  changed_when: false
```

Conditional command with output parsing:

```yaml
- name: Check if AppArmor profile is enforcing
  ansible.builtin.command: aa-status --enabled
  register: apparmor_state
  changed_when: false
  failed_when: apparmor_state.rc not in [0, 1]
```

If you find yourself reaching for `shell:` more than twice in a
playbook, the right module probably exists in `community.general` or
`ansible.posix` — go look first.

---

## 8. Roles and project layout

The book describes the role layout precisely. Here it is, expanded
for current Ansible:

```
ansible/
├── ansible.cfg
├── requirements.yml
├── inventory/
│   ├── hosts.yml
│   ├── group_vars/
│   │   ├── all.yml
│   │   └── production/
│   │       ├── vars.yml
│   │       └── vault.yml
│   └── host_vars/
│       └── web1.example.com.yml
├── playbooks/
│   ├── site.yml
│   ├── ssh-hardening.yml
│   └── drift-check.yml
└── roles/
    └── ssh_hardening/
        ├── defaults/main.yml
        ├── vars/main.yml
        ├── tasks/main.yml
        ├── handlers/main.yml
        ├── templates/sshd_config.j2
        ├── files/banner
        ├── meta/main.yml
        └── README.md
```

Generate the skeleton with `ansible-galaxy role init ssh_hardening`.
Keep `defaults/main.yml` for values the operator may override and
`vars/main.yml` for values the role considers internal.

---

## 9. Running locally without SSH

Most of the linux-skills work happens *on the box itself*, not from a
control node. Two patterns achieve this:

```bash
ansible-playbook -i 'localhost,' -c local playbooks/ssh-hardening.yml
```

Or set it inside the play:

```yaml
- name: Local play
  hosts: localhost
  connection: local
  gather_facts: true
  become: true
  tasks: []
```

The `-i 'localhost,'` form (note the trailing comma) bypasses the
inventory file entirely — useful for one-shot scripts and for the
`sk-ansible-dry-run` helper this skill ships.

---

## 10. Check mode and diff

The whole `linux-config-management` workflow rests on this:

```bash
ansible-playbook playbooks/ssh-hardening.yml --check --diff
```

`--check` runs every task in dry-run mode. `--diff` shows the textual
difference for any file that *would* change. Together they tell you
exactly what the playbook is about to do without actually doing it.

Some tasks cannot run in check mode (they fail because earlier tasks
that *would* have run did not). Mark them as always-run:

```yaml
- name: Compute config hash
  ansible.builtin.command: sha256sum /etc/nginx/nginx.conf
  register: nginx_hash
  check_mode: false
  changed_when: false
```

Use `check_mode: false` sparingly — every escape hatch is a place where
the dry run lies to you.

---

## 11. Tags

Tags let you run a slice of a playbook. Apply them surgically:

```yaml
- name: Install packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - certbot
  tags: [packages, install]

- name: Configure UFW
  community.general.ufw:
    state: enabled
    policy: deny
  tags: [firewall, ufw]
```

```bash
ansible-playbook site.yml --tags firewall
ansible-playbook site.yml --skip-tags packages
```

Reserve a `never` tag for destructive tasks the operator must opt into:

```yaml
- name: Wipe the data directory
  ansible.builtin.file:
    path: /var/lib/app
    state: absent
  tags: [never, wipe]
```

---

## 12. Facts and fact caching

Ansible gathers facts at the start of every play unless you tell it
otherwise. On a hundred-host inventory this is slow. Three controls:

```yaml
- hosts: all
  gather_facts: false        # disable entirely
```

```yaml
- hosts: all
  gather_facts: true
  vars:
    ansible_facts_parts: ["network", "virtual"]   # subset
```

The `fact_caching = jsonfile` setting in `ansible.cfg` (see section 2)
persists facts to `./.ansible_facts/` between runs. Add a TTL with
`fact_caching_timeout`. For multi-operator setups use `redis` instead.

Reference facts in templates and conditionals:

```yaml
- name: Install only on Ubuntu 22.04
  ansible.builtin.apt:
    name: my-package
  when: ansible_distribution == "Ubuntu" and ansible_distribution_version == "22.04"
```

---

## 13. Handlers, `listen`, and ordering

Handlers run *once*, *at the end* of the play, *only* if notified.
That makes them the right place for service restarts:

```yaml
tasks:
  - name: Deploy nginx config
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: reload web

  - name: Deploy site file
    ansible.builtin.template:
      src: site.conf.j2
      dest: /etc/nginx/conf.d/site.conf
    notify: reload web

handlers:
  - name: reload web
    ansible.builtin.systemd_service:
      name: nginx
      state: reloaded
    listen: reload web
```

`listen:` lets multiple handlers respond to the same notification, and
lets you decouple the notify string from the handler's display name.
If you need a handler to run *now*, call `meta: flush_handlers`:

```yaml
- name: Flush handlers before continuing
  ansible.builtin.meta: flush_handlers
```

---

## 14. Templates and Jinja2

Templates are Jinja2 with Ansible's filter set on top. The book
example used `{{ }}` for variables; here is a richer template:

```jinja
# {{ ansible_managed }}
# /etc/nginx/nginx.conf — rendered by Ansible

user www-data;
worker_processes {{ ansible_processor_vcpus | default(2) }};
pid /run/nginx.pid;

events {
    worker_connections {{ nginx_worker_connections | default(1024) }};
}

http {
    server_tokens off;
    {% for upstream in nginx_upstreams | default([]) %}
    upstream {{ upstream.name }} {
        {% for server in upstream.servers %}
        server {{ server }};
        {% endfor %}
    }
    {% endfor %}

    # Literal Jinja that should not be rendered:
    {% raw %}
    log_format main '$remote_addr - $remote_user [$time_local]';
    {% endraw %}
}
```

`{{ ansible_managed }}` (set in `ansible.cfg` via `ansible_managed =
"Ansible managed — do not edit by hand"`) marks the file so a human
SSHing in knows not to edit it.

Useful filters:

- `| default(value)` — fallback if undefined.
- `| mandatory` — fail if undefined.
- `| to_nice_yaml` — render a structure as YAML.
- `| b64encode` / `| b64decode` — for binary blobs.
- `| password_hash('sha512')` — for `/etc/shadow` entries.

---

## 15. Error handling: `rescue`, `always`, fatal errors

Block-level error handling mirrors `try/except/finally`:

```yaml
- name: Deploy and validate
  block:
    - name: Render config
      ansible.builtin.template:
        src: app.conf.j2
        dest: /etc/app/app.conf

    - name: Reload app
      ansible.builtin.systemd_service:
        name: app
        state: reloaded

  rescue:
    - name: Restore previous config
      ansible.builtin.copy:
        src: /etc/app/app.conf.bak
        dest: /etc/app/app.conf
        remote_src: true

    - name: Re-reload app
      ansible.builtin.systemd_service:
        name: app
        state: reloaded

  always:
    - name: Capture status
      ansible.builtin.command: systemctl is-active app
      register: app_state
      changed_when: false
```

Other knobs:

- `ignore_errors: true` — keep going after a failure (use sparingly).
- `failed_when:` — define your own failure condition.
- `any_errors_fatal: true` (play-level) — abort the entire play across
  all hosts if any host fails. Use this for SSH hardening, where a
  half-applied change is worse than no change.

---

## 16. Three complete playbooks

### 16a. SSH hardening (matches `sk-harden-ssh`)

```yaml
---
- name: Harden SSH on Debian and Ubuntu
  hosts: all
  become: true
  any_errors_fatal: true
  gather_facts: true

  vars:
    ssh_port: 22
    ssh_allowed_users:
      - deploy
      - peter

  tasks:
    - name: Ensure openssh-server is installed
      ansible.builtin.apt:
        name: openssh-server
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Back up current sshd_config (once)
      ansible.builtin.copy:
        src: /etc/ssh/sshd_config
        dest: /etc/ssh/sshd_config.bak
        remote_src: true
        force: false

    - name: Render hardened sshd_config
      ansible.builtin.template:
        src: sshd_config.j2
        dest: /etc/ssh/sshd_config
        owner: root
        group: root
        mode: "0644"
        validate: "/usr/sbin/sshd -t -f %s"
      notify: restart sshd

    - name: Ensure SSH service is enabled and running
      ansible.builtin.systemd_service:
        name: ssh
        enabled: true
        state: started

  handlers:
    - name: restart sshd
      ansible.builtin.systemd_service:
        name: ssh
        state: restarted
```

`templates/sshd_config.j2` snippet:

```jinja
# {{ ansible_managed }}
Port {{ ssh_port }}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers {{ ssh_allowed_users | join(' ') }}
ClientAliveInterval 300
ClientAliveCountMax 2
```

### 16b. UFW baseline plus linux-skills install

```yaml
---
- name: Baseline firewall and pull linux-skills
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Install ufw and git
      ansible.builtin.apt:
        name:
          - ufw
          - git
        state: present
        update_cache: true

    - name: Default deny incoming
      community.general.ufw:
        direction: incoming
        policy: deny

    - name: Default allow outgoing
      community.general.ufw:
        direction: outgoing
        policy: allow

    - name: Allow SSH
      community.general.ufw:
        rule: allow
        name: OpenSSH

    - name: Enable UFW
      community.general.ufw:
        state: enabled

    - name: Clone linux-skills into ~/.claude/skills
      ansible.builtin.git:
        repo: https://github.com/peterbamuhigire/linux-skills.git
        dest: /root/.claude/skills
        version: main
        force: false
      register: skills_clone

    - name: Run the linux-skills setup script
      ansible.builtin.command: /root/.claude/skills/scripts/setup-claude-code.sh
      args:
        creates: /usr/local/bin/sk-drift-check
```

### 16c. Nightly drift detection cron

```yaml
---
- name: Install nightly drift check
  hosts: all
  become: true

  tasks:
    - name: Ensure log directory exists
      ansible.builtin.file:
        path: /var/log/drift
        state: directory
        owner: root
        group: root
        mode: "0750"

    - name: Drop the drift wrapper
      ansible.builtin.copy:
        dest: /usr/local/sbin/run-drift-check
        owner: root
        group: root
        mode: "0750"
        content: |
          #!/bin/sh
          # {{ ansible_managed }}
          set -eu
          /usr/bin/ansible-playbook \
            -i 'localhost,' -c local \
            /etc/ansible/playbooks/site.yml \
            --check --diff \
            > /var/log/drift/$(date +\%F).log 2>&1

    - name: Schedule the nightly drift check
      ansible.builtin.cron:
        name: "nightly ansible drift check"
        minute: "17"
        hour: "3"
        user: root
        job: "/usr/local/sbin/run-drift-check"

    - name: Rotate the drift logs
      ansible.builtin.copy:
        dest: /etc/logrotate.d/drift
        owner: root
        group: root
        mode: "0644"
        content: |
          /var/log/drift/*.log {
              weekly
              rotate 8
              compress
              missingok
              notifempty
          }
```

---

## Sources

- Hitchcock, Kenneth. *Linux System Administration for the 2020s: The
  Modern Sysadmin Leaving Behind the Culture of Build and Maintain*.
  Apress, 2022. Chapter 2 ("Ansible Introduction"), Chapter 5
  ("Automation"), and Chapter 3 ("Estate Management — Snowflakes").
- Ansible community documentation — `ansible.builtin` module index,
  `ansible-core` 2.15+ release notes.
- Ansible collections: `community.general`, `ansible.posix`,
  `community.crypto`.
