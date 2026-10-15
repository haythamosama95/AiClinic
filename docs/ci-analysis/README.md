# CI failure analysis — run 38695681551 (commit 953e5e6e)

These are the analysis reports produced by the investigating agents for CI run 38695681551 on branch `ai/abo-master` at commit `953e5e6e`. The consolidated, actionable fix plan is [`../../../ci-fix-plan-run-38695681551.md`](../../../ci-fix-plan-run-38695681551.md) at the repo root; these reports are reference material and are superseded by the plan where they disagree. The earlier `ci-failure-analysis-run-38695681551.md` at the repo root contains several conclusions shown to be wrong in these reports.

| File | Scope |
|---|---|
| `00-failing-tests-list.txt` | Raw failing-test list extracted from all subcampaign logs of the run. |
| `01-ai-platform-npm-test-and-load.md` | ai-platform npm-test/load: missing `request_fingerprint` migration breaks 76 tests; three more causes. |
| `02-ai-platform-idempotency-replay-settlement.md` | Idempotent replay/settlement failures: three harness/test causes, no product change needed. |
| `03-abo-cross-worker-and-e2e-fullstack.md` | abo/cross-worker and e2e-fullstack failures: migration gaps and CI environment issues. |
| `04-frontend-and-vendor-contracts-bundle-scan.md` | Frontend and vendor-contracts failures: campaign routing bugs and missing node_modules. |
| `05-fix-history-and-coupling.md` | Fix-history forensics: why fixing one campaign breaks another; unmerged parallel fix lines. |
| `06-e1a42092-selective-reapply.md` | Analysis of reverted `e1a42092`: seven of eight hunks still needed at HEAD. |
| `06a-e1a42092-recommended-hunks-1-7.patch` | Recommended, re-applicable hunks 1–7 of `e1a42092` as a patch. |
| `07-migration-reference-inventory.md` | Reference inventory of ai-platform migrations and where tests import them. |
| `08-failure-log-digest.md` | Mechanical per-subcampaign digest of failing tests and last log lines. |

Note: Line numbers in these reports refer to commit `953e5e6e`.