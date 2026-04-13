# Skill Domain Analysis

## Foundation

### Included

- `linux-sysadmin`
- `linux-bash-scripting`

### Strengths

- clear routing model
- strong execution contract
- good separation of routing, knowledge, and script policy

### Weaknesses

- the foundation is more mature as policy than as proven execution
- bootstrap tooling is less disciplined than the core engine contract

### Gaps

- missing `sk-new-script` and `sk-lint`
- incomplete Linux-side proof of the foundation
- limited CI enforcement

### Improvements

- finish the missing foundation scripts
- enforce the script contract in CI
- align bootstrap tooling with engine standards

## Security

### Included

- `linux-security-analysis`
- `linux-server-hardening`
- `linux-access-control`
- `linux-firewall-ssl`
- `linux-intrusion-detection`
- `linux-secrets`

### Strengths

- broad and realistic security coverage
- clean separation between audit and remediation
- strong host-level hardening and access-control guidance

### Weaknesses

- many high-value security automations are still planned
- limited compliance-style reporting

### Gaps

- unimplemented hardening scripts
- unimplemented AppArmor and secret-rotation tooling
- limited formal baseline reporting

### Improvements

- complete the planned security scripts
- add rollback tests for hardening
- add compliance-oriented output modes

## Operations

### Included

- provisioning
- cloud-init
- deployment
- service management
- web stack
- packages
- disk/storage
- monitoring
- log management

### Strengths

- this is the most immediately useful part of the repo
- the workflows mirror real Ubuntu/Debian operations work
- the manual layer is strong enough for real operator use

### Weaknesses

- automation coverage is still thin relative to domain breadth
- deployment and service operations still depend heavily on planned scripts

### Gaps

- missing tier-1 service, health, and audit scripts
- limited deployment rollback automation
- no CI/CD operations skill

### Improvements

- finish the tier-1 and tier-2 operations scripts
- add deployment verification and rollback patterns
- add a release-operations / CI-CD domain

## Networking

### Included

- `linux-network-admin`
- `linux-dns-server`
- `linux-mail-server`

### Strengths

- good separation between host networking, DNS service, and mail operations
- realistic production-facing scope

### Weaknesses

- script support is entirely planned here
- less depth than the strongest operations and security domains

### Gaps

- no implemented net status, DNS check, or mail diagnostic scripts
- limited HA, VPN, and load-balancer guidance

### Improvements

- implement the networking tier-3 scripts earlier than planned
- add more change-safe network rollback patterns
- consider a future edge/load-balancer skill

## Containers & Automation

### Included

- `linux-virtualization`
- `linux-config-management`
- `linux-observability`

### Strengths

- shows ambition beyond basic host administration
- config management is conceptually strong
- observability guidance is practical

### Weaknesses

- execution maturity is still mostly conceptual
- observability is stronger on instrumentation than on alerting or SLO practice

### Gaps

- no implemented drift, exporter, or log-forwarding scripts
- no Terraform, GitOps, or Kubernetes layer

### Improvements

- prioritize config-management and observability scripts after tier-1
- add IaC and CI/CD capabilities
- deepen observability toward dashboards and alerting

## Recovery

### Included

- `linux-troubleshooting`
- `linux-disaster-recovery`

### Strengths

- symptom-first troubleshooting model
- restore guidance emphasizes backup selection and verification

### Weaknesses

- restore automation is still mostly planned
- troubleshooting would benefit from richer signature-driven diagnosis

### Gaps

- no implemented restore-wizard and verification scripts beyond MySQL backup
- no formal recovery-drill evidence

### Improvements

- implement and test restore tooling with real fixtures
- add documented recovery drills and timing results
- add more error-signature references

## Domain Conclusion

The domain architecture is one of the repository's strongest assets. The weakness is not the domain
breakdown. The weakness is uneven execution maturity across those domains.
