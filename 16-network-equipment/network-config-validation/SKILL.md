---
name: network-config-validation
description: Use when screening IOS-style candidate configuration for destructive commands, duplicate addresses, stale references, or management-plane exposure. For Linux host security reviews use linux-server-hardening.
license: MIT
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
  origin: Adapted from ECC (github.com, ECC-main/skills/network-config-validation/SKILL.md), community-origin skill, imported 2026-09-20 as part of the LNX-2 network-equipment cluster. Confirmed no equivalent existed anywhere in this engine before import (this engine's 03-networking-and-dns coverage is host-level only).
---

# Network Config Validation

## Distro support

**Not applicable** — this skill validates router/switch (IOS-style)
configuration text, not a Linux distribution's package or service state.
There is no Debian/Ubuntu-vs-RHEL-family split to state. The example Python
in this skill (standard library `re`, `ipaddress`, `collections`) runs
identically on either family if you choose to run it as a script on a Linux
control host; see
[`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md)
for that host's own conventions if you wrap this into a `sk-*`-style tool.

This skill is exempt from `scripts/tests/check-distro-matrix.sh` by naming
convention (it does not match the `linux-*` glob), deliberately, for the same
reason as its sibling skills in this category.

<!-- dual-compat-start -->
## Use When

- Reviewing Cisco IOS or IOS-XE style snippets before deployment.
- Auditing generated config from scripts or templates.
- Looking for dangerous commands, duplicate IP addresses, or subnet
  overlaps.
- Checking whether ACLs, route-maps, prefix-lists, or line policies are
  referenced but not defined.
- Building lightweight pre-flight scripts for network automation.

## Do Not Use When

- Linux host hardening review (SSH config, sysctl, SELinux/AppArmor, package
  CVEs) — use
  [`linux-server-hardening`](../../07-security-and-hardening/linux-server-hardening/SKILL.md).
- Reading a config by eye without a scripted gate — use
  [`cisco-ios-patterns`](../cisco-ios-patterns/SKILL.md) directly.
- Executing the guarded push itself — use
  [`netmiko-ssh-automation`](../netmiko-ssh-automation/SKILL.md), with this
  skill as its pre-flight gate.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---:|---|
| Exact candidate configuration and source | Change owner or generator | Yes | Stop; a partial snippet cannot establish whole-config references or overlap. |
| Device family/model and intended change | Change request | Yes for syntax-specific review | Return only general screening limits and mark platform fit not assessed. |
| Affected interfaces, ACLs, route-maps, and management paths | Current config and change owner | Required for reference checks | Mark the missing checks not assessed; do not infer definitions. |
| Rollback and operator review path | Change record | Required before deployment | Keep output as pre-flight findings; do not approve or execute a push. |

## Workflow

Treat config validation as layered evidence, not as a complete parser. Regex
checks are useful for pre-flight warnings, but final approval still needs a
network engineer to review intent, platform syntax, and rollback steps.

Validate in this order:

1. Destructive commands.
2. Credential and management-plane exposure.
3. Duplicate addresses and overlapping subnets.
4. Stale references to ACLs, route-maps, prefix-lists, and interfaces.
5. Operational hygiene such as NTP, timestamps, remote logging, and banners.

Stop when the input is incomplete, syntax is unsupported, or a dangerous
pattern is found. Recover by preserving the exact candidate and returning
findings for network-engineer review; never apply a partial fix automatically.

## Quality Standards

- Treat regex findings as screening evidence, not as a complete device parser.
- Preserve line numbers and the exact matched command in every blocking finding.
- Distinguish blocking risks from best-practice warnings outside the change scope.
- Require human review of intent, platform syntax, and rollback before deployment.
- Keep credentials and sensitive topology out of shared reports.

## Dangerous Command Detection

```python
import re

DANGEROUS_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\breload\b", re.I), "reload causes downtime"),
    (re.compile(r"\berase\s+(startup|nvram|flash)", re.I), "erases persistent storage"),
    (re.compile(r"\bformat\b", re.I), "formats a device filesystem"),
    (re.compile(r"\bno\s+router\s+(bgp|ospf|eigrp)\b", re.I), "removes a routing process"),
    (re.compile(r"\bno\s+interface\s+\S+", re.I), "removes interface configuration"),
    (re.compile(r"\baaa\s+new-model\b", re.I), "changes authentication behavior"),
    (re.compile(r"\bcrypto\s+key\s+(zeroize|generate)\b", re.I), "changes device SSH keys"),
]

def find_dangerous_commands(lines: list[str]) -> list[dict[str, str | int]]:
    findings = []
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        for pattern, reason in DANGEROUS_PATTERNS:
            if pattern.search(stripped):
                findings.append({
                    "line": line_number,
                    "command": stripped,
                    "reason": reason,
                })
    return findings
```

This is the router/switch analogue of this engine's own
`hooks/destructive-bash-gate.js` — a mechanical pattern gate that catches the
class of command a change should never run silently, applied to config text
instead of shell commands.

## Duplicate IPs And Subnet Overlaps

```python
import ipaddress
import re
from collections import Counter

IP_ADDRESS_RE = re.compile(
    r"^\s*ip address\s+"
    r"(?P<ip>\d{1,3}(?:\.\d{1,3}){3})\s+"
    r"(?P<mask>\d{1,3}(?:\.\d{1,3}){3})\b",
    re.I | re.M,
)

def extract_interfaces(config: str) -> list[dict[str, str]]:
    results = []
    current = None
    for line in config.splitlines():
        if line.startswith("interface "):
            current = line.split(maxsplit=1)[1]
            continue
        match = IP_ADDRESS_RE.match(line)
        if current and match:
            ip = match.group("ip")
            mask = match.group("mask")
            network = ipaddress.ip_interface(f"{ip}/{mask}").network
            results.append({"interface": current, "ip": ip, "network": str(network)})
    return results

def find_duplicate_ips(config: str) -> list[str]:
    ips = [entry["ip"] for entry in extract_interfaces(config)]
    counts = Counter(ips)
    return sorted(ip for ip, count in counts.items() if count > 1)

def find_subnet_overlaps(config: str) -> list[tuple[str, str]]:
    networks = [ipaddress.ip_network(entry["network"]) for entry in extract_interfaces(config)]
    overlaps = []
    for index, left in enumerate(networks):
        for right in networks[index + 1:]:
            if left.overlaps(right):
                overlaps.append((str(left), str(right)))
    return overlaps
```

## Management-Plane Checks

Parse VTY blocks by section so access-class checks do not spill across
unrelated lines.

```python
import re

def iter_blocks(config: str, starts_with: str) -> list[str]:
    blocks = []
    current: list[str] = []
    for line in config.splitlines():
        if line.startswith(starts_with):
            if current:
                blocks.append("\n".join(current))
            current = [line]
            continue
        if current:
            if line and not line.startswith(" "):
                blocks.append("\n".join(current))
                current = []
            else:
                current.append(line)
    if current:
        blocks.append("\n".join(current))
    return blocks

def check_vty_blocks(config: str) -> list[str]:
    issues = []
    for block in iter_blocks(config, "line vty"):
        if re.search(r"transport\s+input\s+.*telnet", block, re.I):
            issues.append("VTY allows Telnet; require SSH only.")
        if not re.search(r"\baccess-class\s+\S+\s+in\b", block, re.I):
            issues.append("VTY block has no inbound access-class source restriction.")
        if not re.search(r"\bexec-timeout\s+\d+\s+\d+\b", block, re.I):
            issues.append("VTY block has no explicit exec-timeout.")
    return issues
```

## Security Hygiene Checks

```python
SECURITY_PATTERNS = [
    (re.compile(r"\bsnmp-server community\s+(public|private)\b", re.I),
     "default SNMP community configured"),
    (re.compile(r"\bsnmp-server community\s+\S+", re.I),
     "SNMPv2 community string configured; prefer SNMPv3 authPriv"),
    (re.compile(r"\bip ssh version 1\b", re.I),
     "SSH version 1 enabled"),
    (re.compile(r"\benable password\b", re.I),
     "enable password is present; use enable secret"),
    (re.compile(r"\busername\s+\S+\s+password\b", re.I),
     "local username uses password instead of secret"),
]

BEST_PRACTICE_PATTERNS = [
    (re.compile(r"\bntp server\b", re.I), "NTP server"),
    (re.compile(r"\bservice timestamps\b", re.I), "log timestamps"),
    (re.compile(r"\blogging\s+\S+", re.I), "logging destination or buffer"),
    (re.compile(r"\bsnmp-server group\s+\S+\s+v3\s+priv\b", re.I), "SNMPv3 authPriv group"),
    (re.compile(r"\bbanner\s+(login|motd)\b", re.I), "login banner"),
]

def check_security(config: str) -> list[str]:
    return [message for pattern, message in SECURITY_PATTERNS if pattern.search(config)]

def check_missing_hygiene(config: str) -> list[str]:
    return [
        f"Missing {description}"
        for pattern, description in BEST_PRACTICE_PATTERNS
        if not pattern.search(config)
    ]
```

## Worked Example

### Change-Window Preflight

1. Run dangerous-command checks on the exact snippet to be pasted.
2. Run duplicate IP and subnet overlap checks against the full candidate
   config.
3. Confirm every referenced ACL, route-map, and prefix-list exists.
4. Confirm rollback commands and out-of-band access before any
   management-plane change.

### Automation Preflight

Use validation as a blocking gate before Netmiko, NAPALM, Ansible, or vendor
API automation pushes a generated config. Fail closed on dangerous commands
and credentials. Warn on best-practice gaps that are outside the change
scope.

## Anti-Patterns

- Treating regex validation as a device parser. Fix: label it as pre-flight evidence and require platform-aware human review.
- Applying generated config without a dry-run diff. Fix: preserve and review the exact candidate diff before deployment.
- Recommending SNMPv2 community strings as a monitoring requirement. Fix: report the observed pattern as a finding and request a security review.
- Checking VTY blocks with regex that can accidentally span unrelated sections. Fix: parse each block boundary and retain the matching excerpt.
- Testing firewall behavior by disabling ACLs instead of reading counters/logs. Fix: inspect counters and logs from an approved test source.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Pre-flight findings | Network engineer or change owner | Each finding has a line, matched command, risk, and review action. |
| Screening summary | Deployment reviewer | Blockers, out-of-scope warnings, and checks not assessed are distinct. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Input | Candidate identifier and digest or exact source path | Reviewer can identify the precise configuration screened. |
| Findings | Pattern, line number, and matched text | A reviewer can reproduce and challenge each match. |
| Limits | Unsupported syntax and missing context list | No parser or missing-context gap is reported as a pass. |

## Capability Contract

Read and parse supplied configuration only. This skill does not connect to a
device, fetch credentials, alter a firewall/ACL, or deploy configuration.
Network access, mutation, and production changes require explicit operator
authorization in a separate approved workflow.

## Degraded Mode

If the candidate is partial, device syntax is unknown, or references are
missing, report only the checks completed and mark the remaining checks not
assessed. Regex success is never a safety or deployment certification.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| A destructive command matches | Block the candidate and cite the line | Avoids reload, erase, or routing removal without review. |
| Management-plane restriction is absent or unclear | Escalate for network-engineer review | Avoids exposing device access or locking out administrators. |
| Address overlap or stale reference is found | Return exact locations for correction and re-screening | Avoids conflicting addressing or dangling policy references. |
| Only out-of-scope hygiene warnings remain | Label them as warnings and preserve the change owner decision | Avoids implying a full parser or widening the change scope. |

## References

- [`cisco-ios-patterns`](../cisco-ios-patterns/SKILL.md) — the config
  vocabulary and change-window discipline this skill validates against.
- [`netmiko-ssh-automation`](../netmiko-ssh-automation/SKILL.md) — the
  automation path this skill gates before a guarded push.
- [`linux-troubleshooting`](../../09-troubleshooting-and-recovery/linux-troubleshooting/SKILL.md) —
  read-only OSI-layer diagnosis when a config passes validation but the
  symptom persists.

<!-- dual-compat-end -->
