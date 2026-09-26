---
name: netmiko-ssh-automation
description: Use when automating an explicit router/switch inventory with Netmiko, collecting device CLI output, or parsing show commands. For Linux host automation use linux-config-management.
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

- Collecting CLI output from explicitly named routers and switches.
- Building a small audit script for interface, routing, or config evidence.
- Adding per-device timeouts and exception handling to device CLI sessions.
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
| Explicit device inventory and device type | Operator-reviewed inventory | Yes | Stop; do not discover targets from a CIDR range or guess a device type. |
| Named read-only commands and collection purpose | Audit or change request | Yes for collection | Ask for the evidence question before connecting. |
| Credential source and timeout values | Environment, vault, or secure prompt; script settings | Yes for a live run | Do not connect; mark live collection not assessed. |
| Change flag, approved window, reviewer, and rollback | Change record | Required for config writes | Keep the run read-only and return a candidate plan. |

## Workflow

1. Confirm the explicit inventory, device type, requested commands, credential
   source, and concurrency limit.
2. Connect with read-only commands first; record raw output and each device's
   success or failure separately.
3. Parse only supported output and retain the raw text beside parsed results.
4. Route candidate configuration through
   [`network-config-validation`](../network-config-validation/SKILL.md), then
   require the explicit operator flag, approved window, peer review, and
   rollback before a write.
5. Compare before/after state and verify behavior; treat saving as a separate
   approved step.

Stop on an unknown device, unreviewed inventory, authentication failure, or
missing rollback. Recover by closing the connection, preserving the per-device
error, and returning to read-only review; do not retry against broader targets.

## Quality Standards

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

- Hardcoding passwords, enable secrets, or private keys in source. Fix: load them from a vault, environment, or secure prompt and keep them out of logs.
- Sending config commands as the default code path. Fix: make read-only collection the default and require a separate explicit write flag.
- Running automation against a CIDR range instead of a reviewed inventory. Fix: enumerate the approved devices and cap concurrency.
- Logging full running configs to shared systems without sanitization. Fix: capture only needed sections and redact secrets and topology.
- Treating parser success as proof that device state is correct. Fix: retain raw output and verify the relevant state and behavior.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Per-device collection record | Network operator or auditor | Each device is identified; command, raw output, status, and error class are preserved. |
| Parsed result | Reviewer | Parser output is traceable to its raw command output and is not treated as device-state proof. |
| Config-change record | Change owner | Candidate, dry-run state, approval, rollback, and before/after checks are explicit. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Collection | Per-device command log | Target, command, timestamp, exit/error state, and raw output are recorded with secrets redacted. |
| Parsing | Raw and structured output pair | Reviewer can inspect parser mismatches without reconnecting. |
| Change | Before/after state and approval record | Write authorization, validation, rollback, and behavior check are recorded. |

## Capability Contract

Read/search and explicitly scoped network access are required for live
collection. Do not scan beyond the approved inventory. Configuration writes
require explicit operator authority, a separate change window, a peer review,
and a rollback plan. Saving remains a distinct approved action.

## Degraded Mode

If Netmiko, credentials, a supported parser, network access, or the device is
unavailable, return the narrowest read-only plan and mark live results not
assessed. Keep errors per device and do not present missing output as a clean
configuration.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Device inventory and credentials are explicit | Collect only the named devices | Avoids broad, unauthorised network access. |
| Authentication or connection fails | Record that device's error and stop its run | Avoids unsafe retries or false coverage claims. |
| Parser returns unstructured text | Preserve raw output and flag manual review | Avoids treating a parser miss as an empty or safe result. |
| Config change lacks approval or rollback | Do not set the write flag | Avoids an unreviewed device mutation or unrecoverable access loss. |

## Worked Example

For a one-device `show version` request, confirm the device appears in the
reviewed inventory, load credentials from the configured secure source, set
connection/read timeouts, and retain the raw result. If authentication fails,
record that device as failed and do not expand the target list.

## References

- [`cisco-ios-patterns`](../cisco-ios-patterns/SKILL.md) — the manual
  show/config vocabulary this automation wraps.
- [`network-config-validation`](../network-config-validation/SKILL.md) — the
  pre-flight gate for any config this skill's guarded path would push.
- [`linux-secrets`](../../02-users-access-and-secrets/linux-secrets/SKILL.md) —
  where `NETMIKO_USERNAME`/`NETMIKO_PASSWORD`/`NETMIKO_ENABLE_SECRET` should
  come from on the control host, instead of hardcoding.

<!-- dual-compat-end -->
