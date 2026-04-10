# Secret Scanning

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Scanning for leaked credentials is not optional. Every repository, every
server home directory, every config tree under `/etc` is a candidate for
a secret leak the moment a tired operator pastes a token into the wrong
file. *Linux System Administration for the 2020s* makes the point
repeatedly: in a DevSecOps world, security gates must run **before**
artefacts flow downstream — a build that has committed a secret into git
history is already a live incident, not a draft. Pre-commit scanning is
the cheapest possible gate, and filesystem sweeps catch what the gate
missed.

Treat every secret finding as a production incident until proven
otherwise. The correct response order is **revoke, rotate, clean history**
— never the other way around. A secret that has touched a public remote
is compromised the instant the push completes, and no amount of
`git-filter-repo` heroics will un-leak it.

## Table of contents

1. Why pre-commit scanning is mandatory
2. Tool overview and when to use each
3. Installing the scanners on Ubuntu
4. Scanning a working tree
5. Scanning git history
6. Custom rules for project-specific patterns
7. Pre-commit hook integration
8. False positive suppression
9. When a secret is found — response order
10. Rewriting git history with git-filter-repo
11. Filesystem sweeps beyond repos
12. Scheduled scans via cron

---

## 1. Why pre-commit scanning is mandatory

A credential leaked to a private repo is an incident. A credential
leaked to a public repo is an incident **and** a data-protection
notification. The half-life of a leaked AWS key on GitHub is under five
minutes — bots are watching the events API. The only defensible
posture is to make it structurally impossible for a secret to reach
`origin`.

Three gates, in order:

1. **Editor / IDE** — local patterns, weakest gate.
2. **Pre-commit hook** — blocks `git commit` on the developer's own
   machine. This is the mandatory gate.
3. **CI pipeline** — catches repos that bypassed the hook (fresh clone,
   `--no-verify`, etc.).

The book's philosophy applies directly: automation removes the cognitive
load of remembering. A developer who has to decide whether to scan will
forget. A pre-commit hook that refuses to let the commit land does not
forget.

## 2. Tool overview and when to use each

| Tool | Strengths | Weaknesses | Use when |
|---|---|---|---|
| **trufflehog v3** | Verified secrets (live-checks the provider), 700+ detectors, scans git history, S3, GCS, Docker images | Verification makes network calls; slower | You want high-confidence findings and can tolerate network egress during scans |
| **gitleaks** | Fast, pure regex + entropy, offline, excellent git history support, ships a sensible default ruleset | No live verification, more false positives | CI gates that must stay offline; historical sweeps of a large monorepo |
| **detect-secrets** (Yelp) | Baseline-file workflow, Python-native, pre-commit integration first-class, plugin architecture | Regex-only detection, no git log scan | Pre-commit gates on Python-heavy projects where the baseline file pattern is already adopted |

Rule of thumb: **trufflehog for one-shot audits, gitleaks for CI,
detect-secrets for pre-commit baselines**. Running two tools at different
stages is sensible — they disagree on false positives and false negatives
in ways that complement each other.

## 3. Installing the scanners on Ubuntu

### trufflehog

The maintainers ship a static binary. Apt has nothing current.

```bash
# Fetch the latest release tarball and install to /usr/local/bin
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
    | sudo sh -s -- -b /usr/local/bin

trufflehog --version
```

### gitleaks

```bash
# Grab the latest release for linux amd64
GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
    | grep tag_name | cut -d '"' -f 4 | sed 's/^v//')
curl -sSfL \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | sudo tar -xz -C /usr/local/bin gitleaks

gitleaks version
```

### detect-secrets

```bash
# Installed via pipx so it is isolated from system python
sudo apt-get install -y pipx
pipx install detect-secrets

detect-secrets --version
```

## 4. Scanning a working tree

Scan a checked-out tree on disk. This catches files in the working copy
that have never been staged.

```bash
# trufflehog — filesystem scan, verified findings only
trufflehog filesystem /var/www/my-app \
    --only-verified \
    --fail

# gitleaks — no-git mode for a plain directory
gitleaks detect --source /var/www/my-app --no-git -v

# detect-secrets — produce a baseline for review
cd /var/www/my-app && detect-secrets scan > /tmp/baseline.json
```

`--only-verified` on trufflehog is important: the scanner actually
calls the provider's API to confirm the credential is live. A verified
finding is a confirmed incident, not a maybe.

`--fail` makes trufflehog exit non-zero on any finding, which is what
you want inside a pre-commit hook or pipeline stage.

## 5. Scanning git history

A secret that is gone from `HEAD` but still in history is still leaked.
Both trufflehog and gitleaks walk the full commit graph.

```bash
# trufflehog — walks all commits on all branches
trufflehog git file:///var/www/my-app \
    --only-verified \
    --since-commit HEAD~500

# gitleaks — default mode scans commit history
cd /var/www/my-app && gitleaks detect --source . --redact -v
```

`--redact` hides the actual secret value in gitleaks output, which is
safe to paste into a ticket or share in a code review channel. Do **not**
paste unredacted scanner output into chat — that is a second leak on top
of the first.

For a brand-new audit of a legacy repo, drop `--since-commit` so
trufflehog walks the whole history. Expect it to take minutes on a busy
repo. Run it once, save the output, then scan incrementally from then
on.

## 6. Custom rules for project-specific patterns

Off-the-shelf rules catch the big providers. They do not catch your
internal API token prefix, your customer ID format, or the licence keys
your product ships. Add custom rules.

### gitleaks custom config

Create `.gitleaks.toml` at the repo root. Example: an internal token
prefix of `lskp_` followed by 32 hex characters.

```toml
# .gitleaks.toml — extend the shipped rules, do not replace them
[extend]
useDefault = true

[[rules]]
id = "linux-skills-internal-token"
description = "Internal linux-skills platform token"
regex = '''lskp_[a-f0-9]{32}'''
tags = ["internal", "token"]

[[rules]]
id = "mysql-app-password-literal"
description = "MySQL application user password in a .env.example"
regex = '''(?i)mysql_password\s*=\s*['"]?[^'"\s]{8,}'''
path = '''\.env.*'''
```

Run with `gitleaks detect --config .gitleaks.toml`.

### trufflehog custom detectors

Trufflehog's v3 plugin model uses Go detectors, which is more work. For
simple regex rules, use the `--regex` flag with a rules file, or drop
the rule into gitleaks instead and run both tools.

## 7. Pre-commit hook integration

Use the [pre-commit](https://pre-commit.com) framework — it handles
install/update/isolation for any hook you throw at it.

```bash
sudo apt-get install -y python3-pip
pipx install pre-commit
cd /var/www/my-app
pre-commit install   # writes .git/hooks/pre-commit
```

`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks

  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']
        exclude: package-lock\.json|yarn\.lock
```

Initialise the detect-secrets baseline once:

```bash
detect-secrets scan > .secrets.baseline
git add .secrets.baseline
git commit -m "secrets: add detect-secrets baseline"
```

From this point on, every `git commit` runs both scanners. A new finding
fails the commit. The developer either removes the secret or, if it is
a confirmed false positive, audits the baseline (`detect-secrets audit
.secrets.baseline`) to mark it as reviewed.

## 8. False positive suppression

Three legitimate mechanisms, in order of preference:

1. **Baseline files** (`detect-secrets`): every false positive is
   reviewed once, annotated with who reviewed it and when, and committed
   to the repo. New findings still fail. This is the only
   suppression method that leaves an audit trail.
2. **Inline `gitleaks:allow`** comments: `# gitleaks:allow` on the same
   line tells gitleaks to skip this match. Use sparingly; a reviewer
   should push back on these in PR review.
3. **Path-based allowlists** in `.gitleaks.toml`:

   ```toml
   [allowlist]
   description = "Test fixtures with deliberate dummy keys"
   paths = [
       '''tests/fixtures/.*\.json''',
       '''docs/examples/fake-env\.txt''',
   ]
   ```

Do not suppress by regex-widening the rule. That silently kills
detection for real keys that happen to look similar.

## 9. When a secret is found — response order

The correct order is **revoke, rotate, clean**. Reverse it at your peril.

1. **Revoke the credential at the provider.** AWS IAM key? Deactivate
   it. Stripe key? Roll it. Database password? Change it on the DB
   server. The credential must be dead on the far side before you touch
   anything else. This is a minutes-level action.
2. **Rotate — deploy a new credential** to every consumer. Use the
   rotation playbook (see `rotation-playbook.md`) so there is no
   downtime window in which the old credential is dead but the new one
   is not yet deployed.
3. **Only then**, if the secret was in a public repo or if compliance
   requires it, clean git history. History cleaning is **never** the
   first step because it does not un-leak the credential — anyone who
   cloned the repo before the rewrite still has the old secret.
4. **Audit the blast radius**: provider logs, access logs, billing
   anomalies. Write the incident up. File a ticket. Note it in
   `/var/log/linux-skills/secret-rotations.log`.

The book's maintenance chapter is blunt about the same pattern: "build
automation that assumes things will break, and verify after every
change". Verification here means confirming the old credential is dead
and the new one works — not assuming.

## 10. Rewriting git history with git-filter-repo

Only after revocation. `git-filter-repo` is the modern replacement for
`git filter-branch` and is what the git project itself recommends.

```bash
sudo apt-get install -y git-filter-repo

# Inside a FRESH clone of the repo — filter-repo will refuse to run in
# a working copy with remote refs
git clone --mirror git@example.com:myorg/myapp.git myapp-scrub
cd myapp-scrub

# Replace every occurrence of the leaked literal with "***REVOKED***"
git filter-repo --replace-text <(echo 'lskp_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6==>***REVOKED***')

# Or nuke a whole file from history
git filter-repo --path config/secrets.yml --invert-paths

# Force-push to every remote (coordinate with the team — every clone is
# now divergent and must be re-cloned)
git push --force --all
git push --force --tags
```

Notify the team in the same channel where the leak was disclosed. Every
existing clone is now invalid and must be reset. Any CI caches must be
purged. Any mirror forks must be scrubbed in the same way. This is why
history rewriting is the **last** step, not the first.

## 11. Filesystem sweeps beyond repos

Secrets leak outside git too. A developer pastes a token into a
scratch file in `/tmp`, a deploy script echoes an env var to a log, a
backup dumps `/etc/mysql/` with world-readable perms. Scan the server.

```bash
# trufflehog against a filesystem path
sudo trufflehog filesystem /etc /home /var/www --only-verified

# Permission audit on known credential locations
sudo find /etc/mysql /etc/linux-skills /etc/letsencrypt/live \
    /root/.aws /root/.ssh \
    \( -type f \! -perm 600 -o -type f \! -user root \) \
    -print
```

The `find` expression returns any credential-bearing file that is
**not** mode 0600 owned by root. Any hit is a finding. Fix it (`chmod
600`, `chown`) and investigate how it got that way.

Extend the sweep to `/home/*/` only with the user's consent and a
documented business reason — shell dotfiles under `/home/jane/.aws/`
are their own audit scope, not yours by default.

## 12. Scheduled scans via cron

Weekly filesystem sweep, results written to a file that a separate
monitoring job watches.

```cron
# /etc/cron.d/linux-secrets-sweep
# Weekly trufflehog filesystem scan, Sundays at 03:17
17 3 * * 0  root  trufflehog filesystem /etc /home /var/www \
    --only-verified --json \
    > /var/log/linux-skills/trufflehog-$(date +\%F).json 2>&1
```

Rotate these logs through logrotate — they can get large. A finding in
a weekly sweep is the same incident severity as a finding in a
pre-commit hook: revoke, rotate, clean.

## Sources

- *Linux System Administration for the 2020s: The Modern Sysadmin
  Leaving Behind the Culture of Build and Maintain* — Kenneth Hitchcock
  (Apress). DevSecOps chapter: "security gates must run before
  artefacts flow downstream"; Maintenance chapter: "assume things will
  break, verify after every change".
- trufflehog v3 docs — https://github.com/trufflesecurity/trufflehog
- gitleaks docs — https://github.com/gitleaks/gitleaks
- detect-secrets (Yelp) — https://github.com/Yelp/detect-secrets
- pre-commit framework — https://pre-commit.com
- git-filter-repo — https://github.com/newren/git-filter-repo
- GitHub secret scanning research on leaked-key half-life (public data).
