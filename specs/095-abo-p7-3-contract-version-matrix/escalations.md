# P7.3 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Worker N with DO N+1

**Question:** E2E-P7.3-05 says a Worker on N with a DO on N+1 yields `coverage_unknown`. 04 §7.1 says the DO accepts N and N−1, answers in the version the call used, and that a gradual rollout pairs an old Worker with a new DO. A DO whose current version is N+1 therefore accepts the Worker's N. Which outcome must the matrix assert for that pairing?

**Assumption:** The matrix asserts accepted, answered in N (the version the call used). A DO whose current version is N+1 is the 04 §7.3 step-1 receiver: it accepts N and N+1. The Worker's N is that DO's N−1, so the 04 §7.1 gradual-rollout pairing succeeds. `coverage_unknown` is only the Worker's mapping of a DO `rejected` `contract_version_unsupported` when the version is missing or outside the DO's N and N−1.

**Why:** 04 §7.1 and §7.2 require the DO to accept its current version and the previous one and to answer in the version the call used. §7.3 deploys that receiver before senders move to N+1, so an old Worker keeps working against the new DO. `coverage_unknown` is the refusal mapping in the same §7.1 row, not the outcome of a version the DO accepts. Answering in the DO's current N+1 would make the Worker treat the answer as unknown and would undo deploy-receivers-first.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (E2E-P7.3-05).

## 2. RPC receiver current version

**Question:** E2E-P7.3-01 must build every 04 §7.1 receiver, including the five PostgREST RPCs, with overridden package constants so that receiver's current version is N+1. Those functions (`issue_ai_token`, `issue_billing_token`, `get_ai_status`, `get_ai_billing_status`, `request_ai_status_refresh`) accept only the literals `(0, 1)` and do not read `ai.contract_versions`. This unit may add tests only under `e2e/fullstack/` and per-codebase test variants, and it must not change the published package constants. How does a test variant override the RPC receiver's current version to N+1?

**Assumption:** The backend per-codebase test variant replaces the five `public` function bodies for the E2E-P7.3-01 RPC cases so the accepted pair is `(1, 2)`. Receiver current is the published N+1 (`2`); N−1 is the published current (`1`). Success answers in the version the call used. A missing version, or a version outside `{1, 2}`, is `CONTRACT_VERSION_UNSUPPORTED` before authentication and before any write, with `accepted_versions` `[1, 2]`; an `rpc_result` refusal carries `contract_version` `2`. `issue_ai_token` still raises. `auth_internal` bodies stay published. The variant restores the published `(0, 1)` public bodies before it exits. It writes no migration, does not update `ai.contract_versions`, and does not change `packages/vendor-contracts`. Receivers that import `CHANNEL_VERSIONS` still use overridden package constants.

**Why:** The five functions hardcode `(0, 1)` and do not read the package or `ai.contract_versions`, so a package-constant override cannot move them. A migration that taught them to read `ai.contract_versions`, or a change to the published package, is outside this unit: the delivery plan limits P7.3 to `e2e/fullstack/` and per-codebase test variants. The test-only public-gate replacement is that variant. Restoring `(0, 1)` before exit leaves the published receivers and the E2E-P5.1-09 contract test unchanged.

**Amended:** `specs/095-abo-p7-3-contract-version-matrix/spec.md` (FR-001, E2E-P7.3-01, §7).
