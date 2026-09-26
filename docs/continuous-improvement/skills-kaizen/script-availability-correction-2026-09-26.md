# Script availability correction ? preservation record (2026-09-26)

## Problem and value decision

At baseline Linux `main` `2eb6b51`, 95 active script-manifest rows referred to 27 available and 68 absent source paths; 10 absent rows were marked core. The installer could not provide absent wrappers, while skill fast-path tables and recovery/security procedures still told operators to invoke them. The affected user is an operator following a skill or installing its declared commands. This creates avoidable dead ends and, for security/provisioning and restore steps, ambiguity about what actually runs.

The smallest sufficient correction removes unavailable commands from active fast-path and manifest sections, replaces affected operational examples with native/manual procedures, and retains genuinely shipped helpers. Planned `[NEW]` wrapper contracts remain in `docs/engine-design/script-inventory.md`; no wrappers, dependencies, or privilege paths were added. The measurable acceptance threshold is zero active manifest source paths missing from the engine or owning skill directory, while retaining every source-backed manifest row. `--list` now shows 27/27 source-backed rows as available. Roll back this correction if a claimed helper source is restored and the owning skill contract is updated and verified together.

## Preservation and scope

The baseline checkout had nine user-owned policy files modified (`.codex/agents/*.toml`, `.codex/model-policy.{json,md}`, and `AGENTS.md`). They remain outside this correction and must not be staged with it. The design inventory and historical analysis/evaluation documents were retained; they describe planned work and prior findings rather than executable skill guidance. The only ownership clarification outside affected manifests is `linux-repo-sync`: its available updater belongs there and is no longer described as a site-deployment core installer.

Changes cover 22 active `SKILL.md` files, linked procedural references, the installer source-path test surface, and the LXD suite selector. The integration test now creates a temporary fixture for engine-root, skill-local, and missing paths; installer output is redirected to a temporary directory so it cannot delete or overwrite `/usr/local/bin/sk-*`. Production destination defaults remain unchanged.

## Verification

- Source census: 27 active manifest rows; 0 missing paths (engine root plus skill-local resolution).
- Installer `--list` under Git for Windows Bash: all 27 rows reported `available`; no installation performed.
- Bash syntax parse under Git for Windows Bash: installer and three changed shell scripts parsed successfully. This is a syntax check, not a Linux runtime test.
- Linux skill validator: 48 active, 48 compliant, zero failures.
- Routing smoke test: 30/30 passed; top-three precision 1.000.
- `git diff --check`: passed; Git reports existing LF-to-CRLF worktree conversion warnings.
- LXD installer integration and operational Linux checks: **NOT_ASSESSED** here; Peter will run the actual Linux tests on Linux. ShellCheck availability: **NOT_ASSESSED**.
- The `scripts/tests/run-test.sh tier1` selector now reports that no per-script tier1 test files are shipped instead of requesting nonexistent tests. The existing foundation suite remains available.

## File preservation hashes

Baseline hashes are SHA-256 of each tracked file at Linux HEAD `2eb6b51`; candidate hashes are SHA-256 of the current worktree file at this record. This table excludes the nine unrelated user policy files above.

| Path | Baseline SHA-256 | Candidate SHA-256 |
|---|---|---|
| `01-provisioning-and-bootstrap/linux-cloud-init/SKILL.md` | `50a237fa2d7b579d06d9066292c280f17e06c45c8a4a1cf2861cfdf68f862595` | `68c60fd0af3d033a281153f689ec41958bcb51ea89c2c4b4782a9623ed9709cb` |
| `01-provisioning-and-bootstrap/linux-cloud-init/references/user-data-reference.md` | `72b7996d742649b6835dc6330e8dfb041e5db14c0379798e9da463010e721ba1` | `a01bf2b334d6f67434a53bb34eb6cacb8379dbdf8a8920e62d19ef9974b416ac` |
| `01-provisioning-and-bootstrap/linux-config-management/SKILL.md` | `81a9d5be530f4f38389da937f69155903ac0aa2847a8e941378ed35e12881f00` | `4866ca762b58b42e6e3bdb761f2d4f0c99126053d78c8a6cd984f9f9fc4711ce` |
| `01-provisioning-and-bootstrap/linux-config-management/references/ansible-patterns.md` | `ab7402fa7823d88377fa95d3e3622bbfec6a66a92a47804eb5e7916aaaf19e9a` | `c6102e41d1745139c86574b835a1c03e1a781890b20e94c99d5548d397e68ddc` |
| `01-provisioning-and-bootstrap/linux-config-management/references/drift-detection.md` | `f5628ed51b9ac9c1b982c39e87dfa81a531fbb127fd0c95c35b7924381f81974` | `4d5318e44264e43cd9d51e236c3810e63b942c08d38519887fa19d65db9bf86f` |
| `01-provisioning-and-bootstrap/linux-package-management/SKILL.md` | `6f5c52fbaa8d1d8c706bc5e2c35e613efcf7cc9d82428ece2726ee4a48314b9c` | `67e520710d7d35a5af0270d53b527b9520d8eea5c799d4ab43e64c681af54a35` |
| `01-provisioning-and-bootstrap/linux-package-management/references/unattended-upgrades-reference.md` | `511dde41d8f1f1bb39106ac6ac311990a88476e285355c982d31258f5d7c50fe` | `a8e38b25d43ae38858223e75eb9954ad5b618320e3a4599a5ff5c5735c8a568c` |
| `01-provisioning-and-bootstrap/linux-server-provisioning/SKILL.md` | `a0f1250d8ef8edb4a31e9614a072ac5a873d211281220b12cb28b5de36938215` | `2969df9c2a2079be95fcd0e8423ff571e79fd8019e8b097a48c45bd794ec0dd7` |
| `02-users-access-and-secrets/linux-access-control/SKILL.md` | `77781b0a9a2a6f5a03e396951fada6be148f605abe690deebcfa3af27140d38f` | `b01a9e7a727491e0747e13ab70ca8d556bbc9e064c9d78109f532e1fdeee54f5` |
| `02-users-access-and-secrets/linux-access-control/references/permissions-reference.md` | `95b3a095a42a21c8e86a86f5683861e794cf992b2a4ccc1d9cc854fa0fc18335` | `96a092dbf9abe460216d87f39d78bb25dcbe75dc8ddfe309c1d45cde43e03cf2` |
| `02-users-access-and-secrets/linux-access-control/references/users-sudoers-pam.md` | `04d0a4c5b1df8fd1d76e482de6798d2f4de057cbc5340cc0a19cb2646588453e` | `5d9218fe5512a947d4dce792b7965e74ba915909abb3ed5b345ea80b94e9bbe1` |
| `02-users-access-and-secrets/linux-secrets/SKILL.md` | `ec34e88c2f96276eaeaeb59994dbd7f2ec6f423eff45f9714eecdaaad758deeb` | `552be45ab029818551c777f7be29c989256999be8d54c3973dbca3c359f4b33b` |
| `02-users-access-and-secrets/linux-secrets/references/rotation-playbook.md` | `be64f86045019e5e430c04c71e762b2f5a30595006be221d1c01d41c47903042` | `e1b8210842d23a347e4f34b3e0a79f312f0f6da415bb47f2f9ec00f45db07fa3` |
| `03-networking-and-dns/linux-dns-server/SKILL.md` | `364ce256a32330f7c16bbfd1a5cd0bd4c422aaba42077bc7853ab3e87ef4b836` | `6f6fba87f5acca6ea18ad3d79518114bba554dfa52f170fdba666baff8e1c7f1` |
| `03-networking-and-dns/linux-network-admin/SKILL.md` | `54e3ce1c744914d5b34ebfa03279c35dc4d7c74cc3ebe830885ac39c29a23212` | `a59fbb2b21afc234d3f7b4f0ea115cd338ec42e4747cebadf4a06fc7969d0119` |
| `04-web-and-mail-services/linux-mail-server/SKILL.md` | `2d62de3a51e5c513e71b11bca7a149818a23e0264e26769919459a3ed7cc480d` | `f718e15dfe726c1e89f5eb87777ffd9914bff6f8d67b288c67b0ffbac85a5f70` |
| `05-services-and-virtualization/linux-virtualization/SKILL.md` | `7d22792ee0fd3ca0deeaf49aeca135f7431fa8a8df906353bae75ff51e6753b6` | `73f3a3a17b8052643c6a9170a807e6ff2ac9da4db60ad2f26c2b2555f54d08cb` |
| `06-storage-and-filesystems/linux-disk-storage/SKILL.md` | `e5fc3f45079380946f0783d656fa1876fb97aa94c2b566e141d72a3d14287814` | `4338ff2f199f9a9c9f649af51e0797d1ca7c8c5ae38e1ff08b2eab45ed78c63c` |
| `07-security-and-hardening/linux-intrusion-detection/SKILL.md` | `08f20ef9428738e94561b05ba28e35a6b4c9798579418bc8cdccbaec8982d7b5` | `333120684f3712037554162d5b9bbd88175aeab7c0e8006e1b0055d19cd49c73` |
| `07-security-and-hardening/linux-intrusion-detection/references/fail2ban-jails.md` | `a45ccac5dabee7d536f9f96803f2a8067dc8f4db1b5e1be4fab505b5199d2bd6` | `95c5f2614dd2e485c3adf52f28097d82664ec40cc1f5f6b78ef6f891e0e8cbf4` |
| `07-security-and-hardening/linux-intrusion-detection/references/rootkit-scanning.md` | `6a074aa7bc5df18a58f24ebdf840dd23630924aa17928211d961cbe9bb4b4abc` | `1f4edc6e511ada62260c4570f338067486f691d10e731f2f1155ad4a2b111eeb` |
| `07-security-and-hardening/linux-security-analysis/SKILL.md` | `46e019d65228cc341a54e4d344584a6a9c996e80a28d8be4b02a01dcf7eb4912` | `a5e95e7b526116d3551f333c8b61654a73d48bb01d0d59b0f1db0b0dcac24ab5` |
| `07-security-and-hardening/linux-server-hardening/SKILL.md` | `805d0f35d8049da049a30e08e5131939f3d647f7c5536c0a475762f285c22c14` | `7147328329f558f5542f77f6c31163d22428394645ac8a52828e6e3076fb977a` |
| `07-security-and-hardening/linux-server-hardening/references/hardening-checklist.md` | `0a1c02b11ed4bc9997d3ec65c8209aaa1c4c4d99cf6f4366dab6e9a6cee8bef0` | `e82f0ba5b76ffe62d3d3a4b67ceb7cec35e599a4d419ce061b112b4debe56318` |
| `08-observability-and-logging/linux-log-management/SKILL.md` | `715d53b04394a245963b3ff479e39bdbe8ba541d1e1799deb17e494ca626f856` | `59ca4e7cd107d4d7da5f250254a138b4b48b4331eda279c8ffb638bbc9afcb1c` |
| `08-observability-and-logging/linux-observability/SKILL.md` | `cb84ef46fb92c6497f1a3d0aa8f9565578e6f0ff7c48f388d36d4038273c01dc` | `8ac3bf443310fb1edfc7c0fc238d580394e0acdeb27b7c6014a3d85f7619c79d` |
| `08-observability-and-logging/linux-system-monitoring/SKILL.md` | `7f60246c5e558326ba64dc0ffa5713bd9198540981751914a7c21908b0f0b68f` | `c42579fb39d38324d9ed28cac7ead72f61add3e291048db00f7d197a82fde8e8` |
| `09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md` | `994a462dec61046cbda49517abe2ef6d2ae3d6816494d71850b8c5d4c599e239` | `7065901e7ae9026d58c2f731cd717b97aceeb5c4f561b22a24aceb7a12ffb137` |
| `09-troubleshooting-and-recovery/linux-disaster-recovery/references/restore-procedures.md` | `e34950ed5be696068b4cd73128fba1f366107cf44ddcf92d6578b96ed9b1d3db` | `c80845033b150548b3cd20192992bd74c8bd6f8bc845c707e15f08749598c6b2` |
| `09-troubleshooting-and-recovery/linux-troubleshooting/SKILL.md` | `90b4c116c1a8d3a2d4896c37f834c04c62e6ebdf8569b8cfe965821065f547af` | `9d7b85d4c8d5da1f0282254e3a28160931f655b6cbf818628fbf69b1ec72163f` |
| `10-automation-and-scripting/linux-bash-scripting/SKILL.md` | `820fcbfa413e7e449d058f2bb4a487d9f36a8af16dc7f07c238281229d65a8f6` | `2555295e51e90962960a9136d4d7028a40ca3f42fffd52e99ecdb505b0134102` |
| `10-automation-and-scripting/linux-bash-scripting/references/script-template.sh` | `abb16c83727bdd4c90471ef76b9e4b82b72aefad7f0867833da9520ff556e8ca` | `766212eb6f43ba49e7f55531a91d6894cb58f1489655f28e0bf96aa2bc0d08d2` |
| `10-automation-and-scripting/linux-repo-sync/SKILL.md` | `1e2427024279f20bdc540cc34c06cf4a41e6a483dbdf0236593d4daac9d518e8` | `0dff3196841f3a2a6bcf651a5b3080aca6ef93fc49474b19e43c6fe254a5aab9` |
| `15-compliance-and-auditing/linux-file-integrity/SKILL.md` | `2b14f89386ce65af8483b4d4ef65aef1be74266368be14de1b7db180f129400d` | `ddeb45f334fc7d1bfdac337cd7693bd77e02a1c37569a960bb276dce42d1631b` |
| `scripts/install-skills-bin` | `6956c3854645d24a8bceb39b4c947f36eb94e823da3b58981449abcba861f4da` | `6c5252eea49016e6f55e3d041a566e5f03f0f772d60f599a5a0d0483f7feafab` |
| `scripts/sk-rootkit-scan.sh` | `5f9e91a48e5fdd5b7a05455a90b40f1765d463c0b6f01ad6dab0c28836160ed5` | `9518ebcad7914f834b3adba2b7ca0eed37283c97a80360febe6f7abd30da0107` |
| `scripts/tests/install-skills-bin.test.sh` | `37ff7b4fcdec08c1c5beb5c44e6618a1a815e03c76876504f90ca729459c706e` | `e19a050c58f8388b658df0dd32f8c14626a0afa3a402746d61b153d0f4003931` |
| `scripts/tests/run-test.sh` | `89b592f7ef032dd8a0c19e14ddbba1da80abc897ca05af874a6be15725e09965` | `8bda48bad78ba651741c37cd5ef6369aea7defd99a03080adac9c771501f3624` |
