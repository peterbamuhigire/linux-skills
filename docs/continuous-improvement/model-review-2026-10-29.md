# Codex model review — 2026-10-29

Decision: retain the authorised `gpt-6-luna` / `high` pins. No model replacement
is authorised or justified by measured comparative results from this audit.
The running root cannot be changed by editing configuration; this review does
not certify its model identity. Delegated workers and reviewer were explicitly
started as Luna/high.

## Currentness evidence

All web sources below were opened on 2026-10-29. They are time-sensitive primary
provider documentation; recheck at the next Kaizen and before any replacement.
The pages have no general revision date, so the access date is the snapshot date.

| Evidence | Observation and scope | Support / uncertainty |
|---|---|---|
| [Official changelog](https://developers.openai.com/api/docs/changelog), 26 October 2026 entry | `gpt-6.1-terra` release | Verified release entry; triggers evaluation, not automatic adoption |
| [Official model catalogue](https://developers.openai.com/api/docs/models) | Luna, GPT-6.1 Sol, GPT-6.1 Terra and Astra listed | Verified published IDs and standard API prices below; API availability is distinct from account execution |
| [Model-selection guidance](https://developers.openai.com/api/docs/guides/model-selection) | Provider positions Luna for scoped/high-volume work, Sol for complex cost-conscious work, Terra for visual/computer tasks and Astra for demanding work | Provider positioning, not an independent Linux-engine benchmark |
| Local model cache, fetched `2026-10-29T03:05:32.809521937Z` | All four IDs listed, each with high reasoning | Runtime/account catalogue observation; successful Luna worker execution additionally observed |
| `.codex/ensure_model_policy.py --runtime codex --check` | Initial root-policy drift; authorised `--apply` repair followed by PASS | Persisted configuration only; bounded helper preserves unrelated settings and creates backups outside this repo |

Published standard API USD per million input/output tokens at access time:
Luna **0.10/0.50**, GPT-6.1 Terra **1/5**, GPT-6.1 Sol **2/10**, Astra **10/50**.
These are not Codex subscription charges or observed costs of this session.
Source: [official catalogue](https://developers.openai.com/api/docs/models).

## Evaluation and remaining evidence

Luna workers produced runnable fixes and an independent review found additional
metadata and fixture-safety problems, which were repaired. That is task evidence
for this session, not a controlled comparison. No like-for-like quality, latency,
retry-rate or total-cost benchmark against the newer candidates was run.
Comparative suitability remains `NOT_ASSESSED`; no claim that Luna is best is made.

Owner: Peter Bamuhigire. Next full evaluation: by 2026-12-28, or earlier before a
policy change or if availability/quality fails. Use the same Linux bug fixtures,
reasoning effort, acceptance tests and measured end-to-end latency/cost across
candidate models. Until authorised after that evidence, retain existing pins.

Author: Peter Bamuhigire, [techguypeter.com](https://techguypeter.com), +256784464178.
