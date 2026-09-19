# Reversible runtime experiment contract

Author: Peter Bamuhigire | techguypeter.com | +256 784 464 178

Use this reference for one bounded workload experiment. It is a measurement
contract, not permission to tune a host or rank runtimes from one favourable
sample.

## Required record

Record workload identity, target and environment, baseline window, runtime and
instrumentation mode, sample count, and the success measure before changing one
factor. Keep the baseline and treatment comparable. Record latency distribution
(including tail percentiles), errors, throughput where relevant, and resource
use. An average-speed improvement fails if the tail or error guardrail regresses.

The experiment must declare a stop threshold, rollback action, last safe state,
rollback verification, owner, and review date. If instrumentation modes differ,
mark the comparison `INCOMPARABLE` rather than ranking it. If no live workload
was measured, mark performance and production evidence `NOT_ASSESSED`.

The synthetic baseline, treatment, tail regression, rollback, and incomparable
mode cases are checked by:

```powershell
python -X utf8 -m unittest tests/test_kaizen_contracts.py -v
```

No service, kernel, scheduler, or production workload is contacted by the
fixture.
