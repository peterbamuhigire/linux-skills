---
name: netmiko-ssh-automation
description: Use when building or reviewing bounded Python/Netmiko SSH collection for a named network-device inventory, parsing command output, or planning a gated configuration push. Keep the default read-only; not for Linux host automation—use linux-config-management for host tasks.
license: MIT
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
  origin: Adapted from ECC (github.com, ECC-main/skills/netmiko-ssh-automation/SKILL.md), community-origin skill, imported 2026-09-20 as part of the LNX-2 network-equipment cluster.
---

# Netmiko SSH Automation

## Distro support

**Not applicable in the engine's Debian/Ubuntu-vs-RHEL-family sense** — the
*target* devices here are network appliances (Cisco IOS/IOS-XE and similar),
not a Linux distribution, so there is no package-manager matrix to state for
them. The *control host* running this Python automation can be either Linux
family; its only real requirement is a Python 3 interpreter and the
`netmiko` package (`pip install netmiko`), which behaves identically on
Debian/Ubuntu and RHEL-family hosts. If you need a distro matrix for
provisioning the control host itself, see
[`linux-server-provisioning`](../../01-provisioning-and-bootstrap/linux-server-provisioning/SKILL.md).

This skill is exempt from `scripts/tests/check-distro-matrix.sh` by naming
convention (it does not match the `linux-*` glob), signalling deliberately
that it targets network-equipment automation, not a Linux host.

<!-- dual-compat-start -->
## Use When

- Collecting `show` command output across routers, switches, or firewalls.
- Building a small audit script for interface, routing, or config evidence.
- Adding timeouts and exception handling to network SSH scripts.
- Parsing command output with TextFSM when a template exists.
- Reviewing automation before it touches production devices.

## Do Not Use When

- Automating Linux host configuration (users, packages, services) — use
  [`linux-config-management`](../../01-provisioning-and-bootstrap/linux-config-management/SKILL.md)
  or [`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md).
- Reviewing a raw IOS config snippet by eye — use
  [`cisco-ios-patterns`](../cisco-ios-patterns/SKILL.md).
- Pre-flight validation of a candidate config before pushing it — use
  [`network-config-validation`](../network-config-validation/SKILL.md) as the
  gate this skill's guarded-config path should run through.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---:|---|
| Explicit device inventory and approved commands | Operator or change record | yes | Stop; do not scan address ranges or infer a target set. |
| Credential source and access boundary | Vault, environment, or operator | yes | Do not request or embed secrets in code, logs, or arguments. |
| Change flag, peer review, maintenance window, and rollback | Approved change record | for config push | Keep the workflow read-only. |

## Workflow

1. Confirm the explicit inventory and the smallest required command set.
2. Collect read-only output with bounded timeouts and concurrency.
3. Preserve per-device errors and raw output when parsing is incomplete.
4. Review any candidate configuration and pass it through
   [`network-config-validation`](../network-config-validation/SKILL.md).
5. Require a separate approved change window and explicit operator flag before
   applying; verify the resulting state before a separate save decision.

Stop on an unknown inventory, missing credential boundary, or unreviewed
configuration change. Recover by returning to read-only collection and
recording the missing evidence. Verify device behavior and capture sanitised
before/after output; do not equate a successful SSH command with a successful
network change.

## Quality Standards

- Use a named, reviewed inventory; keep concurrency and timeouts bounded.
- Keep credentials out of source, command arguments, logs, and shared output.
- Report failures per device without hiding partial results.
- Preserve raw evidence when parser output may be incomplete.
- Keep applying and saving configuration behind separate approval checks.

## Safety Defaults

- Start with read-only `send_command()` collection.
- Keep inventory small and explicit; do not sweep whole address ranges.
- Use environment variables, a vault, or `getpass`; never hardcode
  credentials.
- Set connection and read timeouts.
- Limit concurrency so older devices are not overloaded.
- Require an explicit operator flag before `send_config_set()`.
- Do not call `save_config()` until the change has been verified and
  approved.

## Read-Only Connection Pattern

```python
import os
from getpass import getpass
from netmiko import ConnectHandler
from netmiko.exceptions import (
    NetmikoAuthenticationException,
    NetmikoTimeoutException,
    ReadTimeout,
)

device = {
    "device_type": "cisco_ios",
    "host": "192.0.2.10",
    "username": os.environ.get("NETMIKO_USERNAME") or input("Username: "),
    "password": os.environ.get("NETMIKO_PASSWORD") or getpass("Password: "),
    "secret": os.environ.get("NETMIKO_ENABLE_SECRET"),
    "conn_timeout": 10,
    "auth_timeout": 20,
    "banner_timeout": 15,
    "read_timeout_override": 30,
}

try:
    with ConnectHandler(**device) as conn:
        if device.get("secret") and not conn.check_enable_mode():
            conn.enable()
        output = conn.send_command("show ip interface brief", read_timeout=30)
        print(output)
except NetmikoAuthenticationException:
    print("Authentication failed")
except NetmikoTimeoutException:
    print("SSH connection timed out")
except ReadTimeout:
    print("Command read timed out")
```

Use placeholder addresses from documentation ranges in examples. Keep real
inventory in an ignored local file or a secrets-managed system.

## Batch Collection

```python
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

def collect_show(device: dict[str, Any], command: str) -> dict[str, Any]:
    host = device["host"]
    try:
        with ConnectHandler(**device) as conn:
            output = conn.send_command(command, read_timeout=45)
        return {"host": host, "ok": True, "output": output}
    except (NetmikoAuthenticationException, NetmikoTimeoutException, ReadTimeout) as exc:
        return {"host": host, "ok": False, "error": type(exc).__name__}

results = []
with ThreadPoolExecutor(max_workers=8) as pool:
    futures = [pool.submit(collect_show, device, "show version") for device in devices]
    for future in as_completed(futures):
        results.append(future.result())
```

Keep `max_workers` low unless the device estate and AAA systems are known to
handle higher connection volume.

## Structured Parsing

Netmiko can ask TextFSM, TTP, or Genie to parse supported command output.
Treat parser output as an optimization, not the only evidence path.

```python
with ConnectHandler(**device) as conn:
    parsed = conn.send_command(
        "show ip interface brief",
        use_textfsm=True,
        raise_parsing_error=False,
        read_timeout=30,
    )

if isinstance(parsed, str):
    print("No parser template matched; store raw output for review")
else:
    for row in parsed:
        print(row)
```

If parsing drives a blocking decision, keep the raw command output alongside
the parsed result so an operator can inspect mismatches.

## Guarded Config Pattern

```python
import os

commands = [
    "interface GigabitEthernet0/1",
    "description CHANGE-1234 UPLINK-TO-CORE",
]

apply_changes = os.environ.get("APPLY_NETWORK_CHANGES") == "1"

if not apply_changes:
    print("Dry run only. Candidate commands:")
    print("\n".join(commands))
else:
    with ConnectHandler(**device) as conn:
        conn.enable()
        before = conn.send_command("show running-config interface GigabitEthernet0/1")
        output = conn.send_config_set(commands)
        after = conn.send_command("show running-config interface GigabitEthernet0/1")
        print(before)
        print(output)
        print(after)
        print("Verify behavior before saving startup config.")
```

Saving the config is a separate approval step. In production, include a
rollback snippet and capture before/after evidence in the change record. Run
candidate `commands` through
[`network-config-validation`](../network-config-validation/SKILL.md)'s
dangerous-command and management-plane checks before setting
`APPLY_NETWORK_CHANGES=1`.

## Review Checklist

- Does the script identify an explicit inventory source?
- Are credentials absent from source, logs, and exception messages?
- Are `conn_timeout`, `auth_timeout`, and command `read_timeout` set?
- Are failures reported per device without stopping the whole batch?
- Does the script avoid broad scans and unbounded concurrency?
- Are config changes behind a dry-run or explicit operator flag?
- Is `save_config()` separate from the initial push and tied to
  verification?

## Anti-Patterns

- Hardcoding passwords, enable secrets, or private keys. Fix: use an approved secret source and redact output.
- Sending config commands by default. Fix: default to read-only collection and require an explicit operator flag.
- Scanning a CIDR instead of using reviewed inventory. Fix: enumerate only the authorised devices.
- Logging full configs without sanitisation. Fix: retain only relevant, redacted evidence.
- Treating parser success as proof of device state. Fix: preserve raw output and verify against device behavior.
- Saving immediately after a push. Fix: verify the change and obtain the separate save approval first.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Read-only collection script or review | Network operator | Targets, commands, timeouts, and secret source are explicit. |
| Per-device evidence and error summary | Change reviewer | Partial failures remain visible and output is sanitised. |
| Gated change plan | Change owner | Diff, approval, rollback, verification, and save decision are distinct. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Correctness | Raw command output plus parsed data | Parser gaps are visible and key observations can be checked. |
| Safety | Inventory, timeout, change, and rollback record | Execution scope and each approval boundary are traceable. |

## Capability Contract

Read and static code review are the default. Network access, device login,
configuration changes, and saving device state require explicit authority.
Never execute a proposed push as a test of the skill.

## Degraded Mode

Without Netmiko, credentials, a reachable lab, or target devices, review the
script statically and mark connection and behavior checks `NOT_ASSESSED`.
Do not claim a successful device run from syntax review alone.

## Decision Rules

| Condition | Action | Wrong-choice failure |
|---|---|---|
| Inventory and read-only command set are approved | Collect bounded evidence | Broad or ambiguous scope can overload devices or expose data. |
| Candidate config lacks review, change window, or rollback | Do not push | A partial change can disrupt service or strand access. |
| Parser result conflicts with raw output | Preserve both and escalate | Parsed data alone can hide a state mismatch. |

## Worked Example

For a request to collect interface status from three named lab switches, use
only the approved inventory, run the read-only command with bounded timeouts,
and report a row per device including failures. Preserve raw output for any
unparsed response. Since this is collection only, do not send configuration
commands or call `save_config()`. Without access to the lab, record the run as
`NOT_ASSESSED` rather than inventing results.

## See Also

- [`cisco-ios-patterns`](../cisco-ios-patterns/SKILL.md) — the manual
  show/config vocabulary this automation wraps.
- [`network-config-validation`](../network-config-validation/SKILL.md) — the
  pre-flight gate for any config this skill's guarded path would push.
- [`linux-secrets`](../../02-users-access-and-secrets/linux-secrets/SKILL.md) —
  where `NETMIKO_USERNAME`/`NETMIKO_PASSWORD`/`NETMIKO_ENABLE_SECRET` should
  come from on the control host, instead of hardcoding.
## References

- [`cisco-ios-patterns`](../cisco-ios-patterns/SKILL.md) — device command and change-review boundary.
- [`network-config-validation`](../network-config-validation/SKILL.md) — static candidate preflight.
- [`linux-secrets`](../../02-users-access-and-secrets/linux-secrets/SKILL.md) — control-host secret handling.
<!-- dual-compat-end -->
