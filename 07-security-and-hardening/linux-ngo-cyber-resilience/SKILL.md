---
name: linux-ngo-cyber-resilience
description: Use when designing or reviewing practical Linux security and incident resilience for NGOs, civil-society organisations, or small mission-led teams; use linux-server-hardening for host controls and linux-disaster-recovery for backup restoration.
metadata:
  portable: true
  compatible_with:
  - claude-code
  - codex
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux NGO Cyber Resilience

Adapt security to the mission, people, data, budget, and threat exposure of a
civil-society organisation. This route coordinates host controls, identity,
communications, evidence, and recovery; it does not claim that a Linux host
alone secures the organisation.

<!-- dual-compat-start -->
## Distro support

| Family | Support posture |
|---|---|
| Debian/Ubuntu | Primary examples; verify package and service names on the target release |
| RHEL/Fedora/Rocky/Alma | Supported with family-specific package, SELinux, and service checks |
| Other Linux | Apply the control intent and document the unverified command translation |

## Use When

- An NGO needs a proportionate cyber-resilience baseline across Linux hosts and staff workflows.
- A team needs to prepare for phishing, ransomware, spyware, CEO fraud, or information manipulation.
- A security plan must connect prevention, detection, response, recovery, and board accountability.
- A donor, partner, or incident review requires evidence of controls without pretending that policy equals operation.

## Do Not Use When

- The task is one host hardening change; use `linux-server-hardening`.
- The task is backup design or restore execution; use `linux-disaster-recovery`.
- The task needs attribution or legal conclusions; preserve evidence and route to the appropriate authority.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Mission, people, systems, data, and dependency map | Programme and technology owners | yes | Build a qualified priority map and mark unknowns |
| Threat and incident history | Incident owner and trusted partners | conditional | Use a conservative threat route and record the gap |
| Host, identity, backup, and communications evidence | Administrators and service owners | yes | Separate designed from operating controls; mark NOT ASSESSED |
| Budget, skills, and partner constraints | Board or change owner | conditional | Produce a staged plan with explicit dependencies |

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Mission-aware cyber-resilience assessment | Board and incident owner | Prioritises harm, dependencies, owners, evidence, and residual risk |
| Linux control checklist | Administrators and service owners | Each selected control has evidence, exception, recovery action, and test |
| Incident response and recovery handoff | Incident owner and communications lead | Preservation, containment, trusted communication, recovery, and learning steps are explicit |

## Quality Standards

- Protect people, affected communities, and mission data, not only servers.
- Treat accounts, domains, email, endpoints, and third parties as attack surfaces.
- Use least privilege, MFA where available, patching, tested backups, logging, and safe recovery.
- Preserve incident evidence and avoid destructive cleanup before deciding what must be retained.
- Mark missing monitoring, partner support, or recovery proof as `NOT ASSESSED`.
<!-- dual-compat-end -->

## Decision Rules

| Finding | Action | Failure or risk avoided |
|---|---|---|
| A control reduces a likely, high-harm path and fits available capacity | Prioritise it and assign an evidence owner | Spending effort without reducing material mission harm |
| A control exists only in policy | Rate design separately and schedule an operating test | Mistaking written intent for protection |
| A suspected account or domain impersonation is active | Contain safely, preserve evidence, verify trusted channels, and notify the incident owner | Further fraud, unsafe communication, or lost evidence |
| Ransomware or destructive access is suspected | Isolate affected systems, preserve evidence, activate recovery, and do not reconnect from an unverified state | Reinfection and irreversible evidence loss |
| A small NGO cannot operate a control alone | Use a trusted collective, managed provider, or partner and record the dependency | An unowned control failing silently |

## Workflow

1. **Empower:** assign board-level accountability, staff reporting routes, a
   named incident owner, and a small set of mission-critical priorities.
2. **Enable:** secure budget, training, trusted technical help, domain/email
   protection, and a recovery relationship before an incident.
3. **Identify:** map assets, identities, data, dependencies, exposed services,
   likely actors, phishing paths, and harm to people or programmes.
4. **Protect:** apply host hardening, patching, MFA, least privilege, secret
   handling, encryption, safe admin access, tested backups, and staff practice.
5. **Detect:** centralise useful logs, monitor authentication and privileged
   changes, establish reporting for suspicious messages, and retain time-linked
   evidence.
6. **Respond and recover:** isolate, preserve, communicate through trusted
   channels, reset and restore in a controlled order, validate integrity, and
   conduct a no-blame learning review.
7. Record residual risk, owner, due date, dependency, evidence, and the next
    exercise. Re-test after staff, systems, or threat conditions change. Stop
    the route when evidence, authority, or a safe recovery path is missing.

## Anti-patterns

- Buying a tool without assigning an operator. Fix: name the owner, daily action, evidence, and fallback.
- Treating awareness training as the whole security plan. Fix: pair behaviour controls with identity, host, backup, and response controls.
- Wiping a compromised host before preserving evidence. Fix: contain safely and follow the incident evidence route.
- Restoring backups without testing integrity or credentials. Fix: use a staged restore, validation checks, and credential rotation.
- Publishing incident details before confirming affected people and trusted channels. Fix: coordinate facts, safety, and communications.
- Copying enterprise controls that the NGO cannot operate. Fix: choose a smaller control set with real evidence and partner support.

## Read next

- `linux-server-hardening` for host-level configuration.
- `linux-access-control` and `linux-secrets` for identity and secret controls.
- `linux-intrusion-detection` and `linux-log-management` for detection evidence.
- `linux-disaster-recovery` for backup and restoration.
- `linux-troubleshooting` for bounded diagnosis and recovery.

## References

- [NGO cyber-resilience cycle](references/ngo-cyber-resilience-cycle.md)

## Capability Contract

Read and search are required. Execution is limited to approved validation or
administration scope; this skill never authorises destructive response actions by
itself.

## Degraded Mode

If host evidence, incident facts, or recovery proof is unavailable, produce a
prioritised plan, preserve the gap, and mark the affected control `NOT ASSESSED`.

## Evidence Produced

| Artefact | Acceptance condition |
|---|---|
| Control register | Each priority control has an owner, evidence, exception, and recovery action |
| Incident handoff | Containment, evidence preservation, communication, recovery, and learning steps are named |

## Worked Example

An NGO with a shared Linux file server and suspected phishing begins by naming the
programme owner, preserving the suspicious message and authentication logs,
checking recovery access, and isolating only affected accounts or hosts. It then
enforces MFA and least privilege where feasible, tests a clean staged restore,
communicates through a verified channel, and records residual risk rather than
claiming the incident is closed because a password was reset.
