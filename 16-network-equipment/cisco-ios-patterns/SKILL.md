---
name: cisco-ios-patterns
description: Use when reading or reviewing Cisco IOS/IOS-XE configuration, selecting read-only show commands, or planning and verifying bounded router or switch configuration work. Not for Linux host networking, bulk SSH automation, or config preflight parsing; route those to linux-network-admin, netmiko-ssh-automation, or network-config-validation.
license: MIT
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
  origin: Adapted from ECC (github.com, ECC-main/skills/cisco-ios-patterns/SKILL.md), community-origin skill, imported 2026-09-20 as part of the LNX-2 network-equipment cluster.
---

# Cisco IOS Patterns

## Distro support

**Not applicable — this skill is scoped to network-appliance operating
systems (Cisco IOS / IOS-XE), not a Linux distribution.** The engine's
Debian/Ubuntu-vs-RHEL-family distro-support matrix has no meaning here: there
is no `apt`/`dnf` split on a router. Where this skill's content depends on the
*host* running automation against IOS devices (e.g. a Netmiko/Ansible
control node), that host-side dependency is covered by
[`netmiko-ssh-automation`](../netmiko-ssh-automation/SKILL.md), which itself
runs on either Linux family — see that skill's Python/pip prerequisites
rather than a package-manager matrix here.

This skill is exempt from `scripts/tests/check-distro-matrix.sh` by naming
convention (it does not match the `linux-*` glob the invariant checks), which
is deliberate: the directory name signals a non-Linux-distro scope rather than
an oversight.

<!-- dual-compat-start -->
## Use When

- Reviewing IOS or IOS-XE configuration before a planned maintenance window.
- Choosing read-only `show` commands for troubleshooting a router or switch.
- Checking ACL wildcard masks and interface direction.
- Explaining global, interface, routing process, and line configuration modes.
- Verifying that a change landed in running config and was saved intentionally.

## Do Not Use When

- Linux host networking (netplan, NetworkManager, `ip`/`ss`/`resolvectl`) —
  use [`linux-network-admin`](../../03-networking-and-dns/linux-network-admin/SKILL.md).
- Scripting bulk changes across many devices — use
  [`netmiko-ssh-automation`](../netmiko-ssh-automation/SKILL.md).
- Pre-flight regex validation of a config snippet before it is pasted or
  pushed — use [`network-config-validation`](../network-config-validation/SKILL.md).

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---:|---|
| Device family, model, and software context | Operator or device inventory | yes | Stop before selecting commands or syntax; mark the target `NOT_ASSESSED`. |
| Relevant configuration and observed state | Sanitised device output | yes | Restrict the response to read-only collection planning. |
| Change request, rollback path, and maintenance window | Approved change record | for mutation | Do not recommend applying or saving a change. |

## Workflow

Treat IOS examples as patterns, not paste-ready production changes. Confirm
the platform, interface names, current config, rollback path, and
out-of-band access before making changes on a real device.

Prefer this workflow:

1. Capture current state with read-only commands.
2. Review the exact candidate config.
3. Confirm management access cannot be locked out.
4. Apply the smallest change in a maintenance window.
5. Re-read state, compare to the baseline, then save only after validation.

Stop if the target syntax, management path, or rollback is unknown. Recover by
returning to read-only collection and obtaining the missing operator evidence.
Verify each change with before/after device state and a behavior check that
matches the change; save only after approval and successful verification.

## Mode Reference

```text
Router> enable
Router# show running-config
Router# configure terminal
Router(config)# interface GigabitEthernet0/1
Router(config-if)# description UPLINK-TO-CORE
Router(config-if)# no shutdown
Router(config-if)# exit
Router(config)# end
Router# show running-config interface GigabitEthernet0/1
```

`running-config` is active memory. `startup-config` is what survives reload.
Do not save a change just because a command was accepted; validate behavior
first, then use `copy running-config startup-config` only after the change is
approved.

## Read-Only Collection

```text
show version
show inventory
show processes cpu sorted
show memory statistics
show logging
show running-config | section line vty
show running-config | section interface
show running-config | section router bgp
show ip interface brief
show interfaces
show interfaces status
show vlan brief
show mac address-table
show spanning-tree
show ip route
show ip protocols
show ip access-lists
show route-map
show ip prefix-list
```

Collect the specific section you need instead of dumping full config into a
ticket when the config may contain secrets, customer names, or private
topology.

## Wildcard Masks

IOS ACL and many routing statements use wildcard masks, not subnet masks.

```text
Subnet mask       Wildcard mask
255.255.255.255   0.0.0.0
255.255.255.252   0.0.0.3
255.255.255.0     0.0.0.255
255.255.0.0       0.0.255.255
```

Review wildcard masks before deployment. A subnet mask accidentally used as a
wildcard can match far more traffic than intended.

```text
ip access-list extended WEB-IN
  10 permit tcp 192.0.2.0 0.0.0.255 any eq 443
  999 deny ip any any log
```

Every ACL has an implicit deny at the end. Add an explicit logged deny when
the operational goal includes observing misses, and confirm logging volume
is safe.

## ACL Placement Review

Before applying an ACL to an interface, answer these questions:

- Which traffic direction is being filtered, `in` or `out`?
- Is management traffic sourced from a known jump host or management subnet?
- Is there an explicit permit for required routing, DNS, NTP, monitoring, or
  application traffic?
- Are hit counters available from a safe test source?
- Is there a rollback command and an active console or out-of-band path?

Do not test reachability by removing firewall or ACL protections. Read
counters, logs, and route state first.

## Interface Hygiene

```text
interface GigabitEthernet0/1
 description UPLINK-TO-CORE
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
 switchport trunk native vlan 999
 no shutdown
```

Use clear descriptions, explicit switchport mode, and documented native
VLANs. On routed interfaces, confirm the mask, peer addressing, and routing
process before assuming link state means forwarding is correct.

## Change-Window Verification

Use before/after checks that match the actual change.

```text
show running-config | section interface GigabitEthernet0/1
show interfaces GigabitEthernet0/1
show logging | include GigabitEthernet0/1|changed state|line protocol
show ip route <prefix>
show ip access-lists <name>
```

For routing changes, also capture neighbor state and route tables before and
after the change. For ACL changes, compare hit counters from a planned test
source rather than relying on a generic ping.

This before/after-evidence discipline is the same discipline
[`linux-network-admin`](../../03-networking-and-dns/linux-network-admin/SKILL.md)
applies to Netplan/NetworkManager changes on Linux hosts — capture state,
apply the smallest change, re-verify, only then persist.

## Quality Standards

- Keep read-only diagnostics separate from configuration changes.
- Match syntax to the confirmed device family and release context.
- Capture a sanitised before-state, candidate diff, rollback, and after-state for a change.
- Treat command acceptance as insufficient evidence that the intended behavior works.

## Anti-Patterns

- Applying generated config without a device-specific diff. Fix: compare the candidate with the confirmed running state.
- Saving before post-change checks pass. Fix: verify behavior and approval before persisting startup configuration.
- Using a subnet mask where IOS expects a wildcard mask. Fix: check each ACL mask against the intended address range.
- Applying an ACL in the wrong interface direction. Fix: record ingress or egress intent before proposing the attachment.
- Troubleshooting by disabling ACLs, route policies, or authentication. Fix: inspect counters, logs, and route state first.
- Sharing an unsanitised configuration. Fix: redact credentials, customer names, and private topology before analysis.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Read-only command plan or bounded candidate review | Network operator | Target and purpose are explicit; sensitive output is minimised. |
| Change verification checklist | Change owner | Before/after checks, rollback, approval, and save decision are recorded. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Correctness | Sanitised device state and candidate diff | The reviewed commands match the target and requested change. |
| Change safety | Rollback and post-change observations | Management reachability and intended behavior are checked before save. |

## Capability Contract

Read and review are the default. Device access, configuration changes, saving
state, and production testing require explicit operator authority and a valid
change window. This skill does not execute commands or certify device behavior.

## Degraded Mode

Without a target device, configuration, or rollback evidence, provide only a
qualified read-only plan and mark device-specific validation `NOT_ASSESSED`.
Do not turn illustrative IOS examples into production instructions.

## Decision Rules

| Condition | Action | Wrong-choice failure |
|---|---|---|
| Target family and current state are known | Select read-only checks or review a bounded diff | Unmatched syntax can mislead or disrupt the device. |
| Management access or rollback is unconfirmed | Stop before mutation and request evidence | A remote change can lock out the operator. |
| Post-change behavior is not verified | Do not save the configuration | A syntactically accepted change may still break traffic. |

## Worked Example

For an approved interface-description change, first capture the interface's
running configuration and operational state, review the exact description
diff, and confirm console or out-of-band access. After the maintenance-window
change, compare the interface configuration and link state, inspect relevant
logs, and save only when the checks match the approved request. If the before
state or rollback is missing, stop at the read-only review.

## See Also

- [`netmiko-ssh-automation`](../netmiko-ssh-automation/SKILL.md) — scripted,
  bounded SSH collection and guarded config changes against IOS devices.
- [`network-config-validation`](../network-config-validation/SKILL.md) —
  pre-deployment regex checks for dangerous commands, duplicate/overlapping
  addresses, and management-plane exposure.
- [`linux-network-admin`](../../03-networking-and-dns/linux-network-admin/SKILL.md) —
  the Linux-host equivalent of this skill's diagnostics discipline.
- [`linux-troubleshooting`](../../09-troubleshooting-and-recovery/linux-troubleshooting/SKILL.md) —
  read-only OSI-layer diagnostic workflow, extended to cover router/switch
  evidence collection alongside host-level evidence.
## References

- [`linux-network-admin`](../../03-networking-and-dns/linux-network-admin/SKILL.md) — host networking boundary and before/after evidence pattern.
- [`netmiko-ssh-automation`](../netmiko-ssh-automation/SKILL.md) — bounded automation handoff.
- [`network-config-validation`](../network-config-validation/SKILL.md) — static preflight handoff.
<!-- dual-compat-end -->
