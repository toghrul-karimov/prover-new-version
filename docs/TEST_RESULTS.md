# Test results

One row per run. Findings that affect the design go to the human (see `AGENTS.md`); link the decision they lead to.

| Date | Host and versions | Plan item | What was run | Result | Notes |
|---|---|---|---|---|---|
| 2026-10-27 | Development container, Python 3.13, no Lean | Phase 2, step 1 | `python3 -m unittest discover -s verify` | 10 of 10 pass | Git checks only |
| 2026-10-27 | Same, with a stand-in `lake` | Phase 2, step 2 (Git part) | `tests/toy/run-cases.sh` | The 6 Git-level variants fail at the approval check with the right message | The other variants need real Lean |
