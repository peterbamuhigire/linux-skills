# NGO Cyber-Resilience Cycle

This reference is a self-contained operational synthesis prepared from Stéphane
Duguin, *Cybersecurity for NGOs: Attack Prevention and Threat Response*. It
adapts the source's civil-society emphasis to Linux operations without treating
the source as a substitute for a current standard, incident authority, or local
legal advice.

## Control register

| Stage | Linux and organisational evidence |
|---|---|
| Empower | Board owner, incident contact, mission priorities, staff reporting route |
| Enable | Budget, training, trusted technical partner, domain/email and recovery support |
| Identify | Asset, identity, data, exposure, dependency, threat, and affected-person map |
| Protect | Patching, MFA, least privilege, secure admin, secrets, encryption, backups |
| Detect | Authentication and privilege logs, endpoint alerts, suspicious-message reporting |
| Respond and recover | Isolation, evidence preservation, trusted communication, staged restore, integrity check, review |

## Minimum incident packet

Capture incident ID, first observed time, reporter, affected accounts and hosts,
current containment, preserved evidence, decisions and approvers, notifications,
recovery checkpoints, residual risk, and the learning action. Never store secrets
or unnecessary sensitive personal data in the packet.
