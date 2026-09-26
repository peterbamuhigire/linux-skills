---
name: cisco-ios-patterns
description: Use when reviewing Cisco IOS/IOS-XE configuration for a named router or switch, choosing read-only show commands, or checking a scheduled device maintenance window. For Linux host networking use linux-network-admin.
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

- Reviewing IOS or IOS-XE configuration for a named router or switch.
- Choosing read-only `show` commands for troubleshooting a router or switch.
- Checking ACL wildcard masks and interface direction.
- Explaining global, interface, routing process, and line configuration modes.
- Verifying that running-config reflects reviewed intent after checks pass.

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
| Device family/model and IOS/IOS-XE version | Operator or supplied inventory | Yes for syntax-specific review | Keep advice generic and mark platform compatibility not assessed. |
| Task and affected interface, ACL, or routing object | Change request | Yes | Ask for the intended outcome; do not infer the target. |
| Relevant current configuration and planned commands | Operator-supplied excerpt | Required for change review | Limit output to a read-only checklist; do not approve a change. |
| Rollback and out-of-band access details | Change owner | Required before any live change | Stop before mutation and identify the missing recovery condition. |

## Workflow

Treat IOS examples as patterns, not paste-ready production changes. Confirm
the platform, interface names, current config, rollback path, and
out-of-band access before making changes on a real device.

Use this ordered review:

1. Capture current state with read-only commands.
2. Review the exact candidate config.
3. Confirm management access cannot be locked out.
4. Apply the smallest change in a maintenance window.
5. Re-read state, compare to the baseline, then save only after validation.

Stop if the device model, affected object, change authority, or recovery path is
unknown. Recover to read-only inspection and mark the unverified decision as
not assessed; never guess a command to keep the change moving.

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

- Treat examples as review patterns, not paste-ready production configuration.
- Check wildcard masks, ACL direction, management reachability, and the exact
  affected interface or routing object.
- Collect only the configuration sections needed for the decision and redact
  secrets, customer names, and private topology from shared evidence.
- Require a human network engineer to approve intent and syntax before a live
  change; verify behavior before saving running configuration.

## Anti-Patterns

- Applying a generated config without a device-specific diff. Fix: compare the exact candidate with the affected running-config section first.
- Saving configuration before post-change checks pass. Fix: verify state and behavior, then save only after approval.
- Using a subnet mask where IOS expects a wildcard mask. Fix: check the mask form against the specific command and intended range.
- Applying an ACL to the wrong interface direction. Fix: identify ingress/egress direction and required management flows before review.
- Troubleshooting by disabling ACLs, route policies, or authentication. Fix: inspect counters, logs, and route state using a planned test source.
- Pasting full configs into public tools without sanitizing secrets and topology. Fix: share only the minimum redacted section needed for review.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Read-only diagnostic plan or change-review findings | Network operator | Each command targets the stated device object and avoids unnecessary full-config collection. |
| Before/after verification checklist | Change owner | Checks match the change and include rollback and save criteria. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Baseline | Relevant show output or redacted config excerpt | Device/model, collection time, and command scope are recorded. |
| Change verification | Before/after commands and reviewed diff | The operator can compare state and behavior before saving. |
| Recovery | Rollback command and access route | Recovery does not depend on the access path being changed. |

## Capability Contract

Read and inspect supplied configuration are required. This skill does not access
devices or apply commands. A live operator must have explicit change authority,
an approved window, and a tested recovery route before mutation.

## Degraded Mode

When the platform/version, relevant configuration, or access evidence is
missing, return a narrow read-only checklist and mark syntax or behavior
compatibility not assessed. Do not treat a command being accepted as proof that
the intended behavior works.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Device model and current excerpt are known | Review only the affected syntax and state | Avoids applying generic advice to the wrong platform/object. |
| ACL direction, wildcard, or required flows are unclear | Stop and request network-engineer review | Avoids blocking required or management traffic. |
| Recovery and out-of-band access are unavailable | Keep work read-only and defer the change | Avoids locking out the operator during a network change. |
| Behavior checks pass and the change owner approves | Save only under the approved procedure | Avoids persisting an unverified running configuration. |

## Worked Example

For an inbound `WEB-IN` ACL review, inspect the relevant interface and ACL
sections, confirm the direction and wildcard form, and check the planned test
source against the intended rule. If management access or rollback is unknown,
stop at the review checklist; do not apply or save commands.

## References

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

<!-- dual-compat-end -->
