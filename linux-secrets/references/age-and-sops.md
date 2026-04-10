# Age and Sops

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

`age` and `sops` together solve the problem of keeping configuration
secrets in version control **without** storing them in plain text.
*Linux System Administration for the 2020s* is unambiguous: automation
only works if the state it consumes is reproducible, and state that
lives in an operator's head or a shared spreadsheet is neither
reproducible nor auditable. Encrypted config files in git are the
modern answer — every change is diffable, every reviewer sees the
metadata, only the right recipients can read the values, and the
decryption key lives under the operator's physical control rather than
in a URL-accessible cloud vault.

`age` is the file encryption primitive. `sops` wraps it in
config-file-awareness — meaning it encrypts the **values** inside a
YAML/JSON/ENV file while leaving the keys and structure in the clear,
so diffs are still readable. Use `age` alone for blobs (tarballs, PEM
bundles, binary backups). Use `sops` for structured config that humans
and CI pipelines both read.

Neither tool protects against a compromised running process or a
compromised root account. They protect against leaks at rest: a stolen
laptop, a cloned repo, a misconfigured S3 bucket. Know the threat model
before you trust the tool.

## Table of contents

1. Age overview and installation
2. Key generation and storage
3. Encrypting and decrypting files with age
4. Multiple recipients and SSH keys as recipients
5. Hardware keys via age-plugin-yubikey
6. Sops overview and why it wraps age
7. Installing sops
8. The .sops.yaml rules file
9. Encrypting a YAML/JSON/ENV file
10. Editing encrypted files in place
11. Decrypting for CI consumption
12. Rotating the master key with sops updatekeys
13. Ansible integration
14. Systemd LoadCredentialEncrypted integration
15. Docker secrets integration
16. Threat model: what age and sops do not cover
17. Worked example: encrypted database.env for docker-compose

---

## 1. Age overview and installation

`age` (pronounced like the Japanese 上げ) is a modern file encryption
tool by Filippo Valsorda. It replaces the role `gpg` played for small
files with a key format that is one line long, command-line ergonomics
that fit on one screen, and no PGP baggage.

```bash
# Ubuntu 22.04 and newer ship age in the default repos
sudo apt-get update && sudo apt-get install -y age

age --version
```

For older Ubuntu releases, fetch the static binary from the upstream
release page and drop it into `/usr/local/bin`. Do not use the
`golang-go`-built-from-source approach for a production host — you end
up maintaining a Go toolchain you did not ask for.

## 2. Key generation and storage

Generate a keypair. The public key (`age1...`) is what you share with
anyone who needs to encrypt **to** you. The private key lives in a
file that must be mode 0600.

```bash
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/keys.txt
chmod 600 ~/.config/age/keys.txt

# Show the public key for sharing
grep "public key" ~/.config/age/keys.txt
# -> # public key: age1q9x7...etc
```

Back the key up the same way you back up an SSH private key — offline,
encrypted, in a place only you can reach. A lost `keys.txt` means
every file encrypted to that recipient is permanently unreadable.
Treat it as the highest-value credential on the box.

Server-held keys live at `/etc/age/keys.txt` owned by root mode 0600,
typically with a symlink or environment variable pointing automation
there:

```bash
sudo install -d -m 0700 -o root -g root /etc/age
sudo age-keygen -o /etc/age/keys.txt
sudo chmod 600 /etc/age/keys.txt
```

## 3. Encrypting and decrypting files with age

Encrypt a file to a single recipient. The `-r` flag takes a public
key; `-o` sets the output file.

```bash
# Encrypt
age -r age1q9x7...etc -o backup.tar.gz.age backup.tar.gz

# Decrypt using the private key
age -d -i ~/.config/age/keys.txt backup.tar.gz.age > backup.tar.gz
```

A few things worth knowing:

- age is **binary-out by default**. Pass `-a` (`--armor`) for base64
  ASCII output if you need to paste it into chat or a ticket.
- age happily reads from stdin and writes to stdout; pipe it with
  `tar`, `mysqldump`, or `curl` directly.
- There is no passphrase prompt unless you generate a scrypt-based
  recipient (`age -p`). For automation, always use keypairs, not
  passphrases.

## 4. Multiple recipients and SSH keys as recipients

A file can be encrypted to several recipients at once. Any one of them
can decrypt it. This is how you give two operators access without
sharing a private key.

```bash
age -r age1q9x7...aliceKey \
    -r age1z2a4...bobKey \
    -o secrets.env.age secrets.env
```

`age` also accepts SSH public keys directly as recipients, which means
you can encrypt to an operator using a key they already have on
GitHub:

```bash
# Fetch a GitHub user's ssh keys and encrypt to them
curl -sSf https://github.com/alice.keys > /tmp/alice.keys
age -R /tmp/alice.keys -o secrets.env.age secrets.env
```

Supported SSH types: `ssh-rsa` and `ssh-ed25519`. Do not use
`ssh-rsa` — stick to `ssh-ed25519` for anything new.

## 5. Hardware keys via age-plugin-yubikey

For high-value keys (the backup encryption key, the root age identity
for your fleet), use a YubiKey so the private key never touches disk.

```bash
# Install the plugin
cargo install age-plugin-yubikey   # or pre-built release binary

# Generate a new identity on the YubiKey
age-plugin-yubikey --generate
# prompts for PIN, produces an identity file that points at the hardware
```

The identity file is not the key — it is a pointer. Losing it is
recoverable by re-running `age-plugin-yubikey --identity`. Losing the
YubiKey itself is not recoverable, which is why you enrol two and keep
one offline.

## 6. Sops overview and why it wraps age

Plain `age` encrypts an entire file as an opaque blob. That is fine
for a tarball. It is **bad** for a config file that a reviewer needs
to diff, because every change produces a full ciphertext rewrite and
the review becomes "trust me".

`sops` (Secrets OPerationS, originally from Mozilla, now maintained at
getsops.io) fixes this. It parses the structure of a
YAML/JSON/ENV/INI file, leaves keys and non-sensitive scalars in the
clear, and encrypts only the values. The result:

- `git diff` on an encrypted file shows which **key** changed without
  revealing what it changed to.
- Reviewers can see that "the `database.password` field was rotated"
  without reading the new password.
- The file is still legal YAML/JSON, so any tool that parses YAML can
  at least introspect the shape.

Sops delegates the actual cryptography to a backend. Supported
backends include age, PGP, AWS KMS, GCP KMS, Azure Key Vault, and
HashiCorp Vault. For self-managed Linux servers, **age is the right
default** — no cloud API calls, no IAM policies, no egress fees.

## 7. Installing sops

```bash
# Fetch the current release from getsops/sops
SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest \
    | grep tag_name | cut -d '"' -f 4 | sed 's/^v//')
curl -sSfL -o /tmp/sops.deb \
    "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops_${SOPS_VERSION}_amd64.deb"
sudo dpkg -i /tmp/sops.deb

sops --version
```

## 8. The .sops.yaml rules file

At the root of any repo that uses sops, create `.sops.yaml`. This
tells sops which recipients get which files — so an operator does
not have to remember a long `--age` flag on every command.

```yaml
# .sops.yaml — at repo root
creation_rules:
  # Production config: encrypted to production age key + ops team
  - path_regex: ^config/prod/.*\.(yaml|env)$
    age: >-
      age1prod000000000000000000000000000000000000000000000000,
      age1alice000000000000000000000000000000000000000000000000,
      age1bob00000000000000000000000000000000000000000000000000

  # Staging: staging key + wider team
  - path_regex: ^config/stage/.*\.(yaml|env)$
    age: >-
      age1stage00000000000000000000000000000000000000000000000,
      age1alice000000000000000000000000000000000000000000000000,
      age1bob00000000000000000000000000000000000000000000000000,
      age1carol000000000000000000000000000000000000000000000000

  # Everything else (dev): single shared dev key
  - path_regex: .*
    age: age1dev00000000000000000000000000000000000000000000000000
```

First matching rule wins. Put the most specific paths first.

## 9. Encrypting a YAML/JSON/ENV file

With `.sops.yaml` in place, encryption is a single command. Sops reads
the file format from the extension.

```bash
# Create the plain file, encrypt in place
cat > config/prod/database.yaml <<'EOF'
database:
  host: db.internal.example.com
  port: 5432
  user: myapp
  password: correcthorsebatterystaple
  tls: true
EOF

sops --encrypt --in-place config/prod/database.yaml

# Inspect: keys in the clear, values encrypted, metadata at the bottom
cat config/prod/database.yaml
```

The result looks roughly like:

```yaml
database:
    host: ENC[AES256_GCM,data:abc...,tag:...]
    port: ENC[AES256_GCM,data:xyz...,tag:...]
    user: ENC[AES256_GCM,data:def...,tag:...]
    password: ENC[AES256_GCM,data:ghi...,tag:...]
    tls: ENC[AES256_GCM,data:jkl...,tag:...]
sops:
    age:
        - recipient: age1prod...
          enc: |
              -----BEGIN AGE ENCRYPTED FILE-----
              ...
    lastmodified: "2026-04-10T10:00:00Z"
    mac: ENC[...]
    version: 3.9.1
```

Structure visible, values protected, MAC over the whole file so
tampering is detected. Commit this to git without fear.

For `.env` files, sops uses a simpler format:

```bash
sops --encrypt --in-place config/prod/app.env
```

## 10. Editing encrypted files in place

Never decrypt-to-disk, edit, re-encrypt. That leaves a plain-text
window where a sync tool, editor swap file, or process dump can grab
the secret. Use `sops` as its own editor:

```bash
# Opens $EDITOR on a decrypted view, re-encrypts on save
EDITOR=vim sops config/prod/database.yaml
```

Sops spawns the editor on a tmpfs-backed temporary file, watches for
changes, and re-encrypts on close. If the editor crashes the temp file
is deleted. This is the only correct way to edit sops files.

## 11. Decrypting for CI consumption

A CI job or an application at startup needs the plain values. Decrypt
to stdout and pipe:

```bash
# One-shot decrypt to stdout
sops --decrypt config/prod/database.yaml

# Extract a single value
sops --decrypt --extract '["database"]["password"]' config/prod/database.yaml

# Materialise as env vars into the current shell
set -a && source <(sops --decrypt --output-type dotenv config/prod/app.env) && set +a
```

For the CI case, the age private key is typically injected as a
pipeline secret into `SOPS_AGE_KEY` or written to
`$SOPS_AGE_KEY_FILE`. Do **not** check the key into the pipeline
config itself.

## 12. Rotating the master key with sops updatekeys

When an operator leaves or a key is rotated on its schedule, edit
`.sops.yaml` to add/remove recipients, then re-key every affected
file:

```bash
# Edit .sops.yaml to update the recipient list
${EDITOR:-vim} .sops.yaml

# Re-encrypt the data key for every file that matches the new rules
sops updatekeys config/prod/database.yaml
sops updatekeys config/prod/app.env

# Or, across the whole tree
git ls-files | grep -E 'config/(prod|stage)/.*\.(yaml|env)$' \
    | xargs -I{} sops updatekeys -y {}
```

`updatekeys` touches **only** the encrypted data key header — it does
not re-encrypt the data itself, so the diff is small and commits are
cheap. This matters: rotation must be routine, and routine actions
have to be cheap or they get skipped.

Commit the re-keyed files, tag the commit, and update the rotation
log (see `rotation-playbook.md`).

## 13. Ansible integration

Two paths. Pick one and stick to it.

**Option A — `community.sops` collection.** Ansible decrypts
sops-managed vars at playbook run time.

```bash
ansible-galaxy collection install community.sops
```

```yaml
# playbook.yml
- hosts: webservers
  tasks:
    - name: Load encrypted vars
      community.sops.load_vars:
        file: "config/prod/database.yaml"
      no_log: true

    - name: Write the database config
      ansible.builtin.template:
        src: database.conf.j2
        dest: /etc/myapp/database.conf
        mode: "0600"
        owner: myapp
      no_log: true
```

**Option B — `ansible-vault`.** Native, no extra tooling, but does not
integrate with sops-managed files. Use it when you are already
committed to Ansible and do not want another encryption tool in the
mix. Vault files are encrypted as whole blobs, which loses the
diffability advantage.

```bash
ansible-vault create group_vars/prod/secrets.yml
ansible-vault edit group_vars/prod/secrets.yml
ansible-playbook playbook.yml --ask-vault-pass
```

In a mixed environment, prefer sops+age: the same encrypted files are
consumable by Ansible, CI, and a hand-run `sops -d` without
per-tool conversion.

## 14. Systemd LoadCredentialEncrypted integration

Modern systemd (v250+) can ingest an encrypted credential into a unit
without the operator ever decrypting it to disk. Age is not a direct
backend, but the pattern combines well with `sops -d` at service
start:

```ini
# /etc/systemd/system/myapp.service
[Service]
ExecStartPre=/usr/bin/sops --decrypt --output /run/credentials/myapp/db.env /etc/myapp/db.env.sops
EnvironmentFile=/run/credentials/myapp/db.env
ExecStart=/usr/bin/myapp
PrivateTmp=yes
RuntimeDirectory=credentials/myapp
RuntimeDirectoryMode=0700
```

The decrypted file lives on `/run` (tmpfs), is owned mode 0700 by the
service, and is cleared at shutdown. Coupled with
`DynamicUser=yes` or a dedicated system user, this keeps the plain
value out of the persistent filesystem entirely.

For a pure systemd-native path, use `systemd-creds` with a
TPM-sealed key, and let sops+age be the git-side transport while
`systemd-creds` is the runtime store.

## 15. Docker secrets integration

Docker Swarm has a first-class `secrets` feature; docker-compose has a
`secrets:` block that maps into `/run/secrets/<name>` inside the
container. Use sops to produce those files at deploy time, not to
bake them into the image.

```yaml
# compose.yaml
services:
  app:
    image: myapp:latest
    secrets:
      - db_password
secrets:
  db_password:
    file: ./secrets/db_password.txt   # produced by `sops -d` at deploy
```

A wrapper at deploy time:

```bash
mkdir -p secrets
sops --decrypt --extract '["database"]["password"]' config/prod/database.yaml \
    > secrets/db_password.txt
chmod 600 secrets/db_password.txt
docker compose up -d
shred -u secrets/db_password.txt   # remove immediately after compose reads it
```

Never commit the decrypted file. Add `secrets/` to `.gitignore` and
your secret scanner's allowlist (so the scanner doesn't trip on its
own allowlist pattern).

## 16. Threat model: what age and sops do not cover

Be explicit about what you bought:

- **Protected**: leaked repo, stolen laptop, misconfigured S3 bucket,
  old backup tapes, CI log that accidentally prints the file contents.
- **Not protected**: root compromise on a host where the age key
  lives; memory scraping of a process that has decrypted the value;
  a compromised CI pipeline secret store; a rogue operator with
  legitimate recipient access.
- **Not an access control system**: sops tells you "these recipients
  can decrypt this file", not "this user is allowed to read this
  secret right now". There is no revocation of a past decryption,
  only prevention of future ones.
- **Not a rotation system**: sops updates ciphertext, but you still
  have to actually rotate the underlying credentials on the provider
  and redeploy consumers. See `rotation-playbook.md`.

When the threat model demands runtime protection (memory scraping,
root compromise), step up to a HSM-backed vault or a TPM-sealed
credential. Sops + age is the self-managed sweet spot: strong at
rest, honest about runtime.

## 17. Worked example: encrypted database.env for docker-compose

Putting it all together. A docker-compose stack needs a MySQL root
password and an app user password. Both must live in git, neither
can be plain text, and a rotation needs to be a one-commit affair.

**Step 1 — create the plain env file locally, never commit it.**

```bash
cat > config/prod/database.env <<'EOF'
MYSQL_ROOT_PASSWORD=changeme_root
MYSQL_APP_PASSWORD=changeme_app
EOF
```

**Step 2 — add a `.sops.yaml` rule and encrypt.**

```yaml
# .sops.yaml
creation_rules:
  - path_regex: ^config/prod/.*\.env$
    age: age1prod000...,age1alice000...,age1bob000...
```

```bash
sops --encrypt --in-place config/prod/database.env
git add .sops.yaml config/prod/database.env
git commit -m "secrets: add prod database env (sops+age)"
```

**Step 3 — `compose.yaml` loads secrets at runtime via a wrapper.**

```yaml
services:
  db:
    image: mysql:8
    env_file: /run/app-secrets/database.env
    volumes:
      - db_data:/var/lib/mysql
volumes:
  db_data:
```

**Step 4 — deploy wrapper decrypts into tmpfs, brings stack up, wipes.**

```bash
sudo install -d -m 0700 /run/app-secrets
sudo sops --decrypt --output /run/app-secrets/database.env \
    config/prod/database.env
sudo docker compose --file compose.yaml up -d
sudo shred -u /run/app-secrets/database.env
```

**Step 5 — rotation is a sops edit and a redeploy.**

```bash
EDITOR=vim sops config/prod/database.env    # change the passwords
git commit -am "secrets: rotate prod database passwords"
# ssh to prod, run the deploy wrapper, verify the app can still connect
```

This is the pattern the book means when it talks about "automation
over maintenance": the secret lives in git under encryption, the
deploy wrapper is the single point of truth for how it reaches the
process, rotation is a one-line change followed by a
deploy+verification, and the audit trail is the git log itself.

## Sources

- *Linux System Administration for the 2020s: The Modern Sysadmin
  Leaving Behind the Culture of Build and Maintain* — Kenneth
  Hitchcock (Apress). Chapters on Automation, Security ("Encrypt
  Network Communications"), and State Management.
- `age` specification and tool — https://github.com/FiloSottile/age
  and https://filippo.io/age
- `sops` documentation — https://getsops.io
- `age-plugin-yubikey` — https://github.com/str4d/age-plugin-yubikey
- `community.sops` Ansible collection —
  https://github.com/ansible-collections/community.sops
- systemd `LoadCredentialEncrypted=` — systemd.exec(5) manual.
- Docker compose secrets — https://docs.docker.com/compose/use-secrets/
