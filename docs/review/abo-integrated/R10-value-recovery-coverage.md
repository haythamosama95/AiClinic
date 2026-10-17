# R10 value/recovery selected-source coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; GPT-6.1 Sol, explicitly medium. **2,164 unique production lines**, 15 disjoint ranges, 6 files; zero unread assigned ranges. Range SHA-256 hashes cover original git-object bytes including line endings and are in [JSON](R10-value-recovery-coverage.json). No HEAD source substituted.

| Path | Inclusive T ranges | Lines |
| --- | --- | ---: |
| `abo/src/work/runner.ts` | 1–110, 369–517 | 259 |
| `abo/src/work/grant.ts` | 600–942 | 343 |
| `abo/src/work/reversal.ts` | 703–798, 958–1004 | 143 |
| `abo/src/notify/intake.ts` | 350–423 | 74 |
| `ai-platform/src/quota-do/index.ts` | 939–1216, 1226–1567, 1575–1653, 1688–1794 | 806 |
| `ai-platform/src/quota-do/coverage.ts` | 810–918, 1575–1640, 2111–2272, 2690–2790, 3840–3940 | 539 |

Read history: runner1–110 was initial orientation; every other range was a selected integration seam. Metadata-only symbol/file searches are not counted as body coverage. Hash computation rereads object bytes programmatically without a second correctness-review pass. Grant600–617 starts at the persistence tail; no whole-helper coverage is claimed. Notify350–423 covers authenticated R2-first intake and reversal routing, while duplicate ordinary callback scheduling uses inherited R3 evidence. Rebuild3840–3940 establishes wipe-before-await; full rebuild helper bodies are inherited R9 evidence. Shipping2690–2790 ends during usage-adjustment insertion; it does not claim full alarm/outbox coverage.

Parent lead owns fresh ABO projection and backend SQL/reset source; sibling owns identity/rotation/transfer/version seams. Their coverage is not counted here. Canonical R3/R4/R5/R6/R7/R9 reports supplied upstream/downstream evidence. No tests/fixtures/vectors/testkit/harness/viewer correctness reads or executions, builds/lint, live services/provider/account/usage calls, source fixes, commits or branch changes.

Result: complete with inherited findings; **0 new findings**. Source-only review does not establish deployed operation or launch readiness.
