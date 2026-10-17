# ABO delivery provenance

Target: `db9244fddfddc1905335fb8c7105328c15a0cc5e`. Baseline: `c6cf2c3809a38e2a348f373e926cf2585cfcf291`. Historical tip: `d2e7666f59d8ea7b37a5e05fae89f34d96ba1a3f`.

R0 metadata inventory only. No correctness conclusions; no implementation patches, excluded contents, tests or builds were read or executed. Exact path histories and full commit SHAs are in [provenance.json](provenance.json). Final source at T and [regions.json](regions.json) control review ownership.

Mapping method: each delivery interval begins at the first historical metadata appearance of its spec directory and ends before the next newly introduced unit. Exact changed-path membership is recorded for every commit. Intervals are navigation aids, not assertions that every edit implements only that unit; early P1 work and later cross-unit fixes overlap. Later edits remain attached to every affected final path, including commits whose subjects mention campaigns.

Final R0 classification reconciliation: this metadata history retains **172 historical candidate paths**, of which **170 are final in-scope paths** and two settings UI paths are explicitly excluded incidental context (`settings_rail.dart`, `settings_page.dart`). Their historical mentions below do not put them into source-review ownership; candidate/region inventories control scope. No final in-scope path is missing from the mapping.

## Unit → final changed paths

### 061-abo-p1-1-membership-active-org

History interval: `b057db9591c8` → `4a43c8d323de`; 1 historical candidate paths (final classification controls).

- `backend/supabase/migrations/20261002120000_membership_active_org.sql` (A; R1; 3 unit touches; 0 later touches).

### 062-abo-p1-2-tenant-scoping-cross-tenant-suite

History interval: `84e9f86315d3` → `e97f3c6b7cf0`; 1 historical candidate paths (final classification controls).

- `backend/supabase/migrations/20261002150000_tenant_scoping.sql` (A; R1; 1 unit touches; 0 later touches).

### 063-abo-p2-1-package-core-canonical-signing

History interval: `29068d1687d2` → `7f4800bc85b5`; 13 historical candidate paths (final classification controls).

- `ai-platform/package-lock.json` (M; R9; 1 unit touches; 3 later touches).
- `ai-platform/package.json` (M; R9; 1 unit touches; 3 later touches).
- `ai-platform/src/vendor/contract-version.ts` (A; R2; 1 unit touches; 0 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 26 later touches).
- `packages/vendor-contracts/package-lock.json` (A; R9; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/package.json` (A; R9; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/canonical.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/identifiers.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/index.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/jws.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/version.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/tsconfig.json` (A; R9; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/wrangler.toml` (A; R9; 1 unit touches; 0 later touches).

### 064-abo-p2-2-package-contracts-message-types-webauthn

History interval: `af7998456ad5` → `5aa47ad02e28`; 12 historical candidate paths (final classification controls).

- `packages/vendor-contracts/package.json` (A; R9; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/access-jwt.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/base64url.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/coverage-snapshot.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/feed-event.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/grant-envelope.ts` (A; R2; 1 unit touches; 2 later touches).
- `packages/vendor-contracts/src/index.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/operation.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/receipt.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/result-envelope.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/token-claims.ts` (A; R2; 1 unit touches; 3 later touches).
- `packages/vendor-contracts/src/webauthn.ts` (A; R2; 1 unit touches; 0 later touches).

### 065-abo-p3-1-vendor-entrypoint-authorization-operator-alerting

History interval: `1b4e441b237d` → `bd8e54fff615`; 8 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql` (A; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/alert/email.ts` (A; R9; 1 unit touches; 0 later touches).
- `ai-platform/src/alert/index.ts` (A; R9; 1 unit touches; 7 later touches).
- `ai-platform/src/clock.ts` (A; R5; 1 unit touches; 1 later touches).
- `ai-platform/src/control/audit.ts` (M; R8; 1 unit touches; 2 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 1 unit touches; 25 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 25 later touches).
- `ai-platform/wrangler.toml` (M; R9; 1 unit touches; 4 later touches).

### 066-abo-p3-2-issuer-tokens-registry-tenant-bindings

History interval: `1429740687f0` → `e27b60a1a4b2`; 16 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` (A; R1; 1 unit touches; 0 later touches).
- `ai-platform/src/alert/index.ts` (A; R9; 1 unit touches; 6 later touches).
- `ai-platform/src/clock.ts` (A; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/config-cache/index.ts` (M; R5; 1 unit touches; 3 later touches).
- `ai-platform/src/control/index.ts` (M; R8; 1 unit touches; 3 later touches).
- `ai-platform/src/control/lifecycle.ts` (D; R8; 1 unit touches; 1 later touches).
- `ai-platform/src/discovery/index.ts` (M; R5; 1 unit touches; 3 later touches).
- `ai-platform/src/identity/index.ts` (M; R1; 1 unit touches; 4 later touches).
- `ai-platform/src/journal/index.ts` (M; R9; 1 unit touches; 4 later touches).
- `ai-platform/src/pipeline/index.ts` (M; R5; 1 unit touches; 8 later touches).
- `ai-platform/src/platform-vocabulary.ts` (M; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/retention/index.ts` (M; R9; 1 unit touches; 3 later touches).
- `ai-platform/src/usage-summary/index.ts` (D; R5; 1 unit touches; 3 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 1 unit touches; 24 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 24 later touches).
- `ai-platform/wrangler.toml` (M; R9; 1 unit touches; 3 later touches).

### 067-abo-p3-3-plan-versions-paid-grant-coverage-ledger

History interval: `fc15884b437b` → `2c515abacb3e`; 12 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql` (A; R4; 1 unit touches; 0 later touches).
- `ai-platform/src/admission/index.ts` (M; R5; 1 unit touches; 11 later touches).
- `ai-platform/src/alert/index.ts` (A; R9; 1 unit touches; 5 later touches).
- `ai-platform/src/control/quota-inspect.ts` (D; R8; 1 unit touches; 1 later touches).
- `ai-platform/src/credit/index.ts` (M; R5; 1 unit touches; 2 later touches).
- `ai-platform/src/pipeline/index.ts` (M; R5; 1 unit touches; 7 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 1 unit touches; 20 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 1 unit touches; 22 later touches).
- `ai-platform/src/usage-summary/index.ts` (D; R5; 1 unit touches; 2 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 1 unit touches; 23 later touches).
- `ai-platform/src/worker.ts` (M; R5; 2 unit touches; 22 later touches).
- `ai-platform/wrangler.toml` (M; R9; 1 unit touches; 2 later touches).

### 068-abo-p3-4-admission-settlement-against-terms

History interval: `f1238972f32f` → `f4c10c03cde6`; 20 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261006120000_usage_term.sql` (A; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/adapter.ts` (M; R5; 2 unit touches; 1 later touches).
- `ai-platform/src/admission/index.ts` (M; R5; 3 unit touches; 8 later touches).
- `ai-platform/src/capability/index.ts` (M; R5; 2 unit touches; 6 later touches).
- `ai-platform/src/coverage/calendar.ts` (A; R4; 1 unit touches; 0 later touches).
- `ai-platform/src/credit/index.ts` (M; R5; 1 unit touches; 1 later touches).
- `ai-platform/src/dashboards/index.ts` (M; R9; 1 unit touches; 1 later touches).
- `ai-platform/src/discovery/index.ts` (M; R5; 2 unit touches; 1 later touches).
- `ai-platform/src/entitlement/index.ts` (M; R5; 2 unit touches; 2 later touches).
- `ai-platform/src/errors.ts` (M; R5; 1 unit touches; 4 later touches).
- `ai-platform/src/identity/index.ts` (M; R1; 1 unit touches; 3 later touches).
- `ai-platform/src/journal/index.ts` (M; R9; 1 unit touches; 3 later touches).
- `ai-platform/src/manifest/index.ts` (M; R5; 1 unit touches; 1 later touches).
- `ai-platform/src/pipeline/index.ts` (M; R5; 3 unit touches; 4 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 3 unit touches; 17 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 4 unit touches; 18 later touches).
- `ai-platform/src/rollup/index.ts` (M; R9; 1 unit touches; 1 later touches).
- `ai-platform/src/soft-threshold/index.ts` (M; R5; 1 unit touches; 1 later touches).
- `ai-platform/src/usage-summary/index.ts` (D; R5; 1 unit touches; 1 later touches).
- `ai-platform/src/worker.ts` (M; R5; 3 unit touches; 19 later touches).

### 069-abo-p3-5-term-boundaries-grace-renewal

History interval: `a5a3f2295243` → `5a4e696ffcbd`; 3 historical candidate paths (final classification controls).

- `ai-platform/src/quota-do/coverage.ts` (A; R5; 3 unit touches; 14 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 2 unit touches; 16 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 18 later touches).

### 070-abo-p3-6-complimentary-grants-ceilings-adjustments-suspension

History interval: `0a2d2d09d6a2` → `6b2791d9e46b`; 6 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261006130000_ceiling_policy.sql` (A; R9; 1 unit touches; 0 later touches).
- `ai-platform/src/alert/index.ts` (A; R9; 1 unit touches; 4 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 2 unit touches; 12 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 1 unit touches; 15 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 3 unit touches; 20 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 17 later touches).

### 071-abo-p3-7-reversal-voids-tombstones-held-terms

History interval: `07de72dfe76f` → `e921714d81a0`; 5 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261006140000_grant_void.sql` (A; R6; 1 unit touches; 0 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 2 unit touches; 10 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 1 unit touches; 14 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 3 unit touches; 17 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 16 later touches).

### 072-abo-p3-8-transfer-deletion-with-coverage-left

History interval: `4f14b333db43` → `7d0054495250`; 10 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261006150000_transfer.sql` (A; R6; 1 unit touches; 0 later touches).
- `ai-platform/src/alert/index.ts` (A; R9; 2 unit touches; 2 later touches).
- `ai-platform/src/config-cache/index.ts` (M; R5; 1 unit touches; 2 later touches).
- `ai-platform/src/coverage/transfer.ts` (A; R6; 3 unit touches; 0 later touches).
- `ai-platform/src/identity/index.ts` (M; R1; 2 unit touches; 1 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 3 unit touches; 7 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 2 unit touches; 12 later touches).
- `ai-platform/src/retention/index.ts` (M; R9; 2 unit touches; 1 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 3 unit touches; 14 later touches).
- `ai-platform/src/worker.ts` (M; R5; 3 unit touches; 13 later touches).

### 073-abo-p3-9-fallback-admission-coverage-feed-administrator

History interval: `91f17f3348ac` → `359a3ee75f90`; 11 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261006160000_fallback_admission_feed.sql` (A; R5; 2 unit touches; 0 later touches).
- `ai-platform/src/admission/index.ts` (M; R5; 2 unit touches; 6 later touches).
- `ai-platform/src/capability/index.ts` (M; R5; 1 unit touches; 5 later touches).
- `ai-platform/src/coverage-read/index.ts` (A; R7; 1 unit touches; 0 later touches).
- `ai-platform/src/credit/index.ts` (M; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/pipeline/index.ts` (M; R5; 1 unit touches; 3 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 1 unit touches; 11 later touches).
- `ai-platform/src/retention/index.ts` (M; R9; 1 unit touches; 0 later touches).
- `ai-platform/src/usage-summary/index.ts` (D; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 1 unit touches; 13 later touches).
- `ai-platform/src/worker.ts` (M; R5; 2 unit touches; 11 later touches).

### 074-abo-p3-10-control-plane-port-vendor-entrypoint-removal

History interval: `8f21e49f5dbe` → `9296b0d0af2b`; 25 historical candidate paths (final classification controls).

- `ai-platform/migrations/20261006170000_drop_invoicing.sql` (A; R9; 1 unit touches; 0 later touches).
- `ai-platform/migrations/20261006170100_drop_plan_entitlement.sql` (A; R9; 1 unit touches; 0 later touches).
- `ai-platform/src/admission/index.ts` (M; R5; 1 unit touches; 5 later touches).
- `ai-platform/src/config-cache/index.ts` (M; R5; 1 unit touches; 1 later touches).
- `ai-platform/src/control/audit.ts` (M; R8; 1 unit touches; 1 later touches).
- `ai-platform/src/control/auth.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/capability-lifecycle.ts` (M; R8; 2 unit touches; 1 later touches).
- `ai-platform/src/control/cohort.ts` (M; R8; 1 unit touches; 1 later touches).
- `ai-platform/src/control/credit-price.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/entitle.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/http.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/index.ts` (M; R8; 1 unit touches; 2 later touches).
- `ai-platform/src/control/kill-switch.ts` (M; R8; 2 unit touches; 0 later touches).
- `ai-platform/src/control/lifecycle.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/plan.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/quota-inspect.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/routing-policy.ts` (M; R8; 2 unit touches; 0 later touches).
- `ai-platform/src/control/support-purge.ts` (D; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/token-contract.ts` (M; R8; 2 unit touches; 0 later touches).
- `ai-platform/src/control/types.ts` (M; R8; 2 unit touches; 0 later touches).
- `ai-platform/src/period-close/index.ts` (D; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/support/index.ts` (M; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 3 unit touches; 10 later touches).
- `ai-platform/src/worker.ts` (M; R5; 1 unit touches; 10 later touches).
- `ai-platform/wrangler.toml` (M; R9; 1 unit touches; 1 later touches).

### 075-abo-p3-11-platform-rebuild-procedures-write-budget

History interval: `03150146d16f` → `7f61dad4ce7b`; 14 historical candidate paths (final classification controls).

- `ai-platform/src/admission/index.ts` (M; R5; 1 unit touches; 4 later touches).
- `ai-platform/src/alert/index.ts` (A; R9; 2 unit touches; 0 later touches).
- `ai-platform/src/capability/index.ts` (M; R5; 2 unit touches; 3 later touches).
- `ai-platform/src/control/audit.ts` (M; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/capability-lifecycle.ts` (M; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/cohort.ts` (M; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/control/installation-lifecycle.ts` (A; R8; 1 unit touches; 0 later touches).
- `ai-platform/src/dashboards/index.ts` (M; R9; 1 unit touches; 0 later touches).
- `ai-platform/src/errors.ts` (M; R5; 1 unit touches; 3 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 3 unit touches; 4 later touches).
- `ai-platform/src/quota-do/index.ts` (M; R5; 4 unit touches; 7 later touches).
- `ai-platform/src/router/index.ts` (M; R5; 1 unit touches; 0 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 3 unit touches; 7 later touches).
- `ai-platform/src/worker.ts` (M; R5; 3 unit touches; 7 later touches).

### 076-abo-p4-1-abo-skeleton-records-layer-billing-token

History interval: `0c63d6f222f9` → `831f877301ad`; 16 historical candidate paths (final classification controls).

- `abo/migrations/0001_records.sql` (A; R9; 1 unit touches; 0 later touches).
- `abo/package-lock.json` (A; R9; 1 unit touches; 0 later touches).
- `abo/package.json` (A; R9; 1 unit touches; 1 later touches).
- `abo/src/alert/index.ts` (A; R9; 2 unit touches; 6 later touches).
- `abo/src/alert/lock.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/auth.ts` (A; R1; 1 unit touches; 1 later touches).
- `abo/src/clinic-api/billing-contact.ts` (A; R3; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/offers.ts` (A; R3; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/rate.ts` (A; R3; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/version.ts` (A; R2; 1 unit touches; 2 later touches).
- `abo/src/clock.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/records/append.ts` (A; R9; 2 unit touches; 1 later touches).
- `abo/src/records/export.ts` (A; R9; 1 unit touches; 1 later touches).
- `abo/src/worker.ts` (A; R9; 6 unit touches; 15 later touches).
- `abo/tsconfig.json` (A; R9; 1 unit touches; 0 later touches).
- `abo/wrangler.toml` (A; R9; 1 unit touches; 4 later touches).

### 077-abo-p4-2-checkout-paymob-intention

History interval: `422fcdb585ff` → `48cd6e36d5fe`; 16 historical candidate paths (final classification controls).

- `abo/migrations/0002_checkout.sql` (A; R3; 1 unit touches; 0 later touches).
- `abo/package.json` (A; R9; 1 unit touches; 0 later touches).
- `abo/scripts/check-import-boundary.mjs` (A; R9; 2 unit touches; 0 later touches).
- `abo/src/clinic-api/checkouts.ts` (A; R3; 2 unit touches; 4 later touches).
- `abo/src/coverage/view.ts` (A; R7; 1 unit touches; 0 later touches).
- `abo/src/provider/paymob/adapter.ts` (A; R3; 1 unit touches; 6 later touches).
- `abo/src/provider/paymob/client.ts` (A; R3; 2 unit touches; 2 later touches).
- `abo/src/provider/port.ts` (A; R3; 1 unit touches; 4 later touches).
- `abo/src/provider/registry.ts` (A; R3; 1 unit touches; 1 later touches).
- `abo/src/worker.ts` (A; R9; 1 unit touches; 14 later touches).
- `abo/wrangler.toml` (A; R9; 1 unit touches; 3 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 1 unit touches; 6 later touches).
- `packages/vendor-contracts/src/base64url.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/canonical.ts` (A; R2; 1 unit touches; 0 later touches).
- `packages/vendor-contracts/src/grant-envelope.ts` (A; R2; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/jws.ts` (A; R2; 1 unit touches; 0 later touches).

### 078-abo-p4-3-notification-intake-inquiry-work-pipeline

History interval: `140d7dbc0246` → `53a0c2f5d82c`; 9 historical candidate paths (final classification controls).

- `abo/migrations/0003_notify_work.sql` (A; R3; 1 unit touches; 0 later touches).
- `abo/src/alert/index.ts` (A; R9; 1 unit touches; 5 later touches).
- `abo/src/notify/intake.ts` (A; R3; 2 unit touches; 6 later touches).
- `abo/src/provider/paymob/adapter.ts` (A; R3; 2 unit touches; 4 later touches).
- `abo/src/provider/paymob/client.ts` (A; R3; 2 unit touches; 0 later touches).
- `abo/src/provider/port.ts` (A; R3; 2 unit touches; 2 later touches).
- `abo/src/work/runner.ts` (A; R3; 2 unit touches; 6 later touches).
- `abo/src/worker.ts` (A; R9; 1 unit touches; 13 later touches).
- `abo/wrangler.toml` (A; R9; 1 unit touches; 2 later touches).

### 079-abo-p4-4-grant-pipeline-to-platform-purchase

History interval: `48e716060c51` → `8470d6daac11`; 9 historical candidate paths (final classification controls).

- `abo/migrations/0004_grant.sql` (A; R4; 1 unit touches; 0 later touches).
- `abo/src/alert/index.ts` (A; R9; 2 unit touches; 3 later touches).
- `abo/src/clinic-api/billing-reads.ts` (A; R7; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/checkouts.ts` (A; R3; 1 unit touches; 3 later touches).
- `abo/src/notify/intake.ts` (A; R3; 1 unit touches; 5 later touches).
- `abo/src/work/grant.ts` (A; R4; 2 unit touches; 7 later touches).
- `abo/src/worker.ts` (A; R9; 1 unit touches; 12 later touches).
- `abo/wrangler.toml` (A; R9; 1 unit touches; 1 later touches).
- `packages/vendor-contracts/src/grant-envelope.ts` (A; R2; 1 unit touches; 0 later touches).

### 080-abo-p4-5-sweeps-reversals-inquiry-budget

History interval: `c39a5b6ab0b9` → `39eab38298d3`; 13 historical candidate paths (final classification controls).

- `abo/migrations/0005_reversal.sql` (A; R6; 1 unit touches; 0 later touches).
- `abo/src/alert/index.ts` (A; R9; 1 unit touches; 2 later touches).
- `abo/src/clinic-api/checkouts.ts` (A; R3; 1 unit touches; 2 later touches).
- `abo/src/notify/intake.ts` (A; R3; 2 unit touches; 3 later touches).
- `abo/src/provider/paymob/adapter.ts` (A; R3; 1 unit touches; 3 later touches).
- `abo/src/work/grant.ts` (A; R4; 2 unit touches; 5 later touches).
- `abo/src/work/inquiry-budget.ts` (A; R3; 2 unit touches; 1 later touches).
- `abo/src/work/reversal.ts` (A; R6; 2 unit touches; 2 later touches).
- `abo/src/work/runner.ts` (A; R3; 3 unit touches; 3 later touches).
- `abo/src/work/sweep.ts` (A; R6; 2 unit touches; 1 later touches).
- `abo/src/worker.ts` (A; R9; 2 unit touches; 10 later touches).
- `ai-platform/src/quota-do/coverage.ts` (A; R5; 2 unit touches; 2 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 2 unit touches; 4 later touches).

### 081-abo-p4-6-operator-console-access-perimeter-lookup

History interval: `da591da25926` → `6ef0f517ec96`; 5 historical candidate paths (final classification controls).

- `abo/migrations/0006_operator_action.sql` (A; R8; 1 unit touches; 0 later touches).
- `abo/src/ops/index.ts` (A; R8; 2 unit touches; 12 later touches).
- `abo/src/worker.ts` (A; R9; 1 unit touches; 9 later touches).
- `ai-platform/src/vendor/entrypoint.ts` (A; R8; 2 unit touches; 2 later touches).
- `packages/vendor-contracts/src/access-jwt.ts` (A; R2; 1 unit touches; 0 later touches).

### 082-abo-p4-7-console-passkey-ceremony-abo-side-hp

History interval: `69b4a3842ede` → `b5acf54828be`; 4 historical candidate paths (final classification controls).

- `abo/migrations/0007_hp_actions.sql` (A; R8; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/checkouts.ts` (A; R3; 1 unit touches; 1 later touches).
- `abo/src/ops/index.ts` (A; R8; 2 unit touches; 10 later touches).
- `abo/src/work/grant.ts` (A; R4; 1 unit touches; 4 later touches).

### 083-abo-p4-8-console-relays-complimentary-grants-adjustments

History interval: `d0d12980380f` → `2c776c6439e2`; 3 historical candidate paths (final classification controls).

- `abo/src/ops/index.ts` (A; R8; 3 unit touches; 7 later touches).
- `abo/src/work/grant.ts` (A; R4; 1 unit touches; 3 later touches).
- `abo/src/worker.ts` (A; R9; 2 unit touches; 7 later touches).

### 084-abo-p4-9-console-relays-configuration-registries-bootstrap

History interval: `ef24b468dd3d` → `596c44633cf7`; 1 historical candidate paths (final classification controls).

- `abo/src/ops/index.ts` (A; R8; 3 unit touches; 4 later touches).

### 085-abo-p4-10-reconciliation-payout-import-findings

History interval: `aa9c938ce481` → `9ab4db5dc901`; 7 historical candidate paths (final classification controls).

- `abo/migrations/0008_reconciliation.sql` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/alert/index.ts` (A; R9; 1 unit touches; 1 later touches).
- `abo/src/ops/index.ts` (A; R8; 1 unit touches; 3 later touches).
- `abo/src/provider/paymob/adapter.ts` (A; R3; 1 unit touches; 2 later touches).
- `abo/src/provider/port.ts` (A; R3; 1 unit touches; 1 later touches).
- `abo/src/reconciliation/run.ts` (A; R9; 2 unit touches; 2 later touches).
- `abo/src/worker.ts` (A; R9; 1 unit touches; 6 later touches).

### 086-abo-p4-11-daily-digest-platform-watch-housekeeping

History interval: `d2846c8016de` → `b1e98428ed9b`; 19 historical candidate paths (final classification controls).

- `abo/migrations/0009_digest_watch.sql` (A; R9; 1 unit touches; 0 later touches).
- `abo/scripts/rebuild-abo.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/alert/index.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/auth.ts` (A; R1; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/checkouts.ts` (A; R3; 1 unit touches; 0 later touches).
- `abo/src/clinic-api/version.ts` (A; R2; 2 unit touches; 0 later touches).
- `abo/src/digest/run.ts` (A; R9; 2 unit touches; 0 later touches).
- `abo/src/housekeeping/run.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/ops/index.ts` (A; R8; 2 unit touches; 1 later touches).
- `abo/src/provider/paymob/adapter.ts` (A; R3; 1 unit touches; 1 later touches).
- `abo/src/rebuild.ts` (A; R9; 2 unit touches; 1 later touches).
- `abo/src/reconciliation/run.ts` (A; R9; 1 unit touches; 1 later touches).
- `abo/src/records/append.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/records/export.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/watch/hourly.ts` (A; R9; 1 unit touches; 0 later touches).
- `abo/src/work/grant.ts` (A; R4; 1 unit touches; 2 later touches).
- `abo/src/work/reversal.ts` (A; R6; 1 unit touches; 1 later touches).
- `abo/src/work/runner.ts` (A; R3; 1 unit touches; 2 later touches).
- `abo/src/worker.ts` (A; R9; 2 unit touches; 4 later touches).

### 087-abo-p5-1-issuer-key-custody-token-issuance

History interval: `dbecbb93a63b` → `a2a873d70159`; 1 historical candidate paths (final classification controls).

- `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` (A; R1; 3 unit touches; 1 later touches).

### 088-abo-p5-2-coverage-feed-puller-status-projection

History interval: `bc56c4a16bb0` → `c56b67b3656c`; 1 historical candidate paths (final classification controls).

- `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` (A; R7; 3 unit touches; 0 later touches).

### 088b-abo-p5-2b-read-time-status-notices

History interval: `47b24795be6a` → `8c1180b323dd`; 1 historical candidate paths (final classification controls).

- `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` (A; R7; 2 unit touches; 0 later touches).

### 089-abo-p6-1-desktop-contract-versions-token-minting

History interval: `8cebf657ca4b` → `d782443360ee`; 16 historical candidate paths (final classification controls).

- `frontend/lib/app/app.dart` (M; R7; 2 unit touches; 0 later touches).
- `frontend/lib/app/providers/ai_shell_status_provider.dart` (A; R7; 2 unit touches; 0 later touches).
- `frontend/lib/core/ai/ai_client_sdk.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/discovery_client.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/https_submit_port.dart` (M; R7; 2 unit touches; 1 later touches).
- `frontend/lib/core/ai/ports.dart` (M; R7; 1 unit touches; 1 later touches).
- `frontend/lib/core/ai/sse_events.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/supabase_aat_mint_port.dart` (M; R1; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/usage_summary_client.dart` (M; R7; 1 unit touches; 1 later touches).
- `frontend/lib/core/contract_versions.dart` (A; R2; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/availability/ai_availability.dart` (M; R7; 2 unit touches; 0 later touches).
- `frontend/lib/features/ai/availability/ai_availability_reader.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/degraded/ai_degraded_view.dart` (M; R7; 1 unit touches; 3 later touches).
- `frontend/lib/features/ai/host/ai_feature_host_page.dart` (M; R7; 2 unit touches; 3 later touches).
- `frontend/lib/features/ai/presentation/pages/ai_page.dart` (M; R7; 2 unit touches; 2 later touches).
- `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` (M; R7; 2 unit touches; 1 later touches).

### 090-abo-p6-2-desktop-denial-states-administrator-coverage

History interval: `59aff3022aa2` → `6b8b0bc987f3`; 9 historical candidate paths (final classification controls).

- `frontend/lib/core/ai/https_submit_port.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/ports.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/taxonomy.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/core/ai/usage_summary_client.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/degraded/ai_degraded_view.dart` (M; R7; 2 unit touches; 1 later touches).
- `frontend/lib/features/ai/host/ai_feature_host_page.dart` (M; R7; 2 unit touches; 1 later touches).
- `frontend/lib/features/ai/presentation/pages/ai_page.dart` (M; R7; 2 unit touches; 0 later touches).
- `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` (M; R7; 1 unit touches; 0 later touches).

### 091-abo-p6-3-administrator-billing-offers-contact-checkout

History interval: `017df137b603` → `2f4274ccd781`; 12 historical candidate paths (final classification controls).

- `frontend/lib/app/app_routes.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/app/router.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/abo_client.dart` (A; R7; 2 unit touches; 1 later touches).
- `frontend/lib/features/ai/billing/administrator_billing_page.dart` (A; R7; 2 unit touches; 2 later touches).
- `frontend/lib/features/ai/billing/billing_contact_form.dart` (A; R3; 2 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/billing_token_client.dart` (A; R1; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/checkout_screen.dart` (A; R3; 2 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/offers_screen.dart` (A; R3; 2 unit touches; 0 later touches).
- `frontend/lib/features/ai/degraded/ai_degraded_view.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/host/ai_feature_host_page.dart` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/l10n/app_ar.arb` (M; R7; 1 unit touches; 0 later touches).
- `frontend/lib/l10n/app_en.arb` (M; R7; 1 unit touches; 0 later touches).

### 092-abo-p6-4-administrator-subscription-payment-history-notices

History interval: `b3bf21e0cbdd` → `e6f7a2d7cef4`; 5 historical candidate paths (final classification controls).

- `frontend/lib/features/ai/billing/abo_client.dart` (A; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/administrator_billing_page.dart` (A; R7; 1 unit touches; 1 later touches).
- `frontend/lib/features/ai/billing/commercial_notices.dart` (A; R7; 1 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/payment_history.dart` (A; R7; 2 unit touches; 0 later touches).
- `frontend/lib/features/ai/billing/subscription_summary.dart` (A; R7; 1 unit touches; 0 later touches).

### 093-abo-p7-1-clean-up-dependent-paths-control-residue

History interval: `7c3ef50e07a7` → `edcade274a8b`; 1 historical candidate paths (final classification controls).

- `.github/scripts/control-residue-guard.sh` (A; R9; 1 unit touches; 0 later touches).

### 094-abo-p7-2-cross-system-security-isolation-suite

History interval: `4a08cda12571` → `a3995765f5d3`; 0 historical candidate paths (final classification controls).

No final in-scope path touched in this delivery interval; reference/excluded metadata still establishes unit provenance.


### 095-abo-p7-3-contract-version-matrix

History interval: `f8054e627a56` → `9795e78582ea`; 0 historical candidate paths (final classification controls).

No final in-scope path touched in this delivery interval; reference/excluded metadata still establishes unit provenance.


### 096-abo-p8-1-staging-environment-external-monitors-profile

History interval: `515783e7fe51` → `87104450fd5a`; 3 historical candidate paths (final classification controls).

- `abo/src/worker.ts` (A; R9; 1 unit touches; 3 later touches).
- `abo/wrangler.toml` (A; R9; 1 unit touches; 0 later touches).
- `ai-platform/wrangler.toml` (M; R9; 1 unit touches; 0 later touches).

### 097-abo-p8-2-staging-acceptance-a1-a36

History interval: `2a22c00f4bb9` → `ac9f7f46f4b5`; 0 historical candidate paths (final classification controls).

No final in-scope path touched in this delivery interval; reference/excluded metadata still establishes unit provenance.


### 098-abo-p8-3-launch-readiness-checks

History interval: `2e033ea6b8a7` → `6c91bbd8edf1`; 0 historical candidate paths (final classification controls).

No final in-scope path touched in this delivery interval; reference/excluded metadata still establishes unit provenance.


## Later source fixes

These commits occur after the final delivery implementation. Names/statuses identify effects; subjects never determine scope. Read the final paths, not every intermediate patch.

- `10ecb09b3e17` — fix(backend): repair staff membership session RLS and storage test fixtures
  - `A backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql`
- `95abcd8c0943` — fix(ai-platform): persist shipped coverage alerts and refresh schema snap
  - `M ai-platform/src/errors.ts`
  - `M ai-platform/src/quota-do/coverage.ts`
  - `M ai-platform/src/worker.ts`
- `0e5a685a7f4c` — fix(abo): confirm budget, Paymob reversal intake, and full migration harness
  - `M abo/src/notify/intake.ts`
  - `M abo/src/work/inquiry-budget.ts`
  - `M abo/src/work/runner.ts`
- `deb077a6a696` — Fix ai-platform npm-test failures
  - `M ai-platform/src/admission/index.ts`
  - `M ai-platform/src/capability/index.ts`
  - `M ai-platform/src/quota-do/index.ts`
  - `M ai-platform/src/worker.ts`
- `dcc63d706e67` — Fix ABO cross-worker campaign failures
  - `M abo/src/notify/intake.ts`
  - `M abo/src/provider/registry.ts`
  - `M abo/src/rebuild.ts`
  - `M abo/src/reconciliation/run.ts`
  - `M abo/src/work/reversal.ts`
  - `M abo/src/work/runner.ts`
  - `M abo/src/work/sweep.ts`
  - `M ai-platform/migrations/20260803120000_token_contract.sql`
- `07615507caa5` — Fix frontend campaign failures
  - `M frontend/lib/features/settings/presentation/components/settings_rail.dart`
  - `M frontend/lib/features/settings/presentation/pages/settings_page.dart`
- `5d0a687f295f` — Fix ai-platform npm test failures
  - `M ai-platform/src/capability/index.ts`
  - `A ai-platform/src/control/index.ts`
  - `M ai-platform/src/discovery/index.ts`
  - `M ai-platform/src/entitlement/index.ts`
  - `M ai-platform/src/errors.ts`
  - `M ai-platform/src/identity/index.ts`
  - `M ai-platform/src/journal/index.ts`
  - `M ai-platform/src/pipeline/index.ts`
  - `M ai-platform/src/quota-do/coverage.ts`
  - `M ai-platform/src/quota-do/index.ts`
  - `M ai-platform/src/worker.ts`
- `6c80d5335e83` — Fix AI platform campaign failures
  - `M ai-platform/src/entitlement/index.ts`
  - `M ai-platform/src/quota-do/index.ts`
- `25eea3b6a269` — Fix AI platform E2E failures
  - `M ai-platform/src/worker.ts`
- `05919c95ac86` — Improve AI Platform campaign failure reports
  - `M ai-platform/src/adapter.ts`
  - `M ai-platform/src/admission/index.ts`
  - `M ai-platform/src/capability/index.ts`
  - `M ai-platform/src/config-cache/index.ts`
  - `M ai-platform/src/control/index.ts`
  - `M ai-platform/src/journal/index.ts`
  - `M ai-platform/src/pipeline/index.ts`
  - `M ai-platform/src/quota-do/index.ts`
  - `M ai-platform/src/soft-threshold/index.ts`
  - `M ai-platform/src/worker.ts`
- `065dca522a80` — Fix campaign test failure reporting and cases
  - `M ai-platform/src/admission/index.ts`
  - `M ai-platform/src/quota-do/index.ts`
- `0cc4c6f67c25` — Fixing rest of ai platform npm-tests
  - `M ai-platform/src/quota-do/index.ts`
- `771ceed717fc` — Fixing rest of ai platform npm-tests
  - `A ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql`
  - `M ai-platform/src/admission/index.ts`
  - `M ai-platform/src/errors.ts`
  - `M ai-platform/src/journal/index.ts`
  - `M ai-platform/src/manifest/index.ts`
  - `M ai-platform/src/pipeline/index.ts`
  - `M ai-platform/src/quota-do/index.ts`
  - `M ai-platform/src/worker.ts`
- `e1a42092c9e1` — Restore CI campaign fixes
  - `M abo/src/worker.ts`
  - `A backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql`
  - `M packages/vendor-contracts/src/token-claims.ts`
- `cb99ded04cc1` — Revert "Restore CI campaign fixes"
  - `M abo/src/worker.ts`
  - `D backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql`
  - `M packages/vendor-contracts/src/token-claims.ts`
- `953e5e6e1567` — Fix CI campaign flakiness: email stub, pool upgrade, deterministic clock
  - `M ai-platform/package-lock.json`
  - `M ai-platform/package.json`
  - `M ai-platform/src/rollup/index.ts`
  - `M ai-platform/src/vendor/entrypoint.ts`
  - `M ai-platform/src/worker.ts`
- `98d1f9edc08b` — Re-apply e1a42092 hunks 1-7 (revert cb99ded0, keep test_campaign_live_stats.py)
  - `M abo/src/worker.ts`
  - `A backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql`
  - `M packages/vendor-contracts/src/token-claims.ts`
- `987e8f99ad17` — Fix receipt base64 decoding in workerd, canonical feed-token JSON, raise local auth rate limits
  - `M backend/supabase/config.toml`
  - `A backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql`
  - `M packages/vendor-contracts/src/receipt.ts`
- `530626fe3391` — Improve CI campaign diagnostics and RPC contract
  - `M backend/supabase/migrations/20261007180000_issuer_key_custody.sql`
  - `M frontend/lib/core/rpc/app_rpc_invoker.dart`
- `0592df157106` — Fix CI campaign failures and E2E worker setup
  - `M frontend/lib/core/rpc/app_rpc_invoker.dart`
- `9204d8430886` — fix: inject access certs in fullstack harness
  - `M ai-platform/src/vendor/entrypoint.ts`
- `b0a8a0fdb841` — Fix fullstack campaign failure cases
  - `M abo/src/ops/index.ts`
- `6ff1f4eabcd8` — Fix fullstack campaign failures
  - `M abo/src/work/grant.ts`
- `7acca5652c90` — Fix grant cross-worker and P7.3 campaign failures
  - `M abo/src/work/grant.ts`
- `2d157b648695` — Migrate Workers tests to Cloudflare Vitest plugin
  - `M ai-platform/package-lock.json`
  - `M ai-platform/package.json`
- `747cfa36eaff` — Restore isolated Workers test runner
  - `M ai-platform/package-lock.json`
  - `M ai-platform/package.json`
- `74a29cfa50ee` — Fix fullstack CI failure paths
  - `M abo/src/notify/intake.ts`
  - `M abo/src/provider/paymob/adapter.ts`
  - `M abo/src/provider/port.ts`
- `d316989d543f` — Address latest fullstack CI failures
  - `M frontend/lib/features/ai/billing/administrator_billing_page.dart`

## Deletions and replacements

Deleted target candidates retain their baseline names and owning phase. The history index also records deletions within delivery intervals. Symbol-level replacements and final SQL overrides must be traced through the final region packet, rather than treating a missing file as no work.

- `ai-platform/src/control/auth.ts` → R8 (deleted at T).
- `ai-platform/src/control/credit-price.ts` → R8 (deleted at T).
- `ai-platform/src/control/entitle.ts` → R8 (deleted at T).
- `ai-platform/src/control/http.ts` → R8 (deleted at T).
- `ai-platform/src/control/lifecycle.ts` → R8 (deleted at T).
- `ai-platform/src/control/plan.ts` → R8 (deleted at T).
- `ai-platform/src/control/quota-inspect.ts` → R8 (deleted at T).
- `ai-platform/src/control/support-purge.ts` → R8 (deleted at T).
- `ai-platform/src/period-close/index.ts` → R5 (deleted at T).
- `ai-platform/src/usage-summary/index.ts` → R5 (deleted at T).

## Coverage notes

Mapped 39 units (061–098 plus 088b); global path history covers all 172 in-scope final-diff candidates and 28 later commits touching in-scope source.

Paths touched only outside the delivery intervals (global history still recorded):

- `ai-platform/migrations/20260803120000_token_contract.sql`
- `ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql`
- `backend/supabase/config.toml`
- `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql`
- `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql`
- `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql`
- `frontend/lib/core/rpc/app_rpc_invoker.dart`
- `frontend/lib/features/settings/presentation/components/settings_rail.dart`
- `frontend/lib/features/settings/presentation/pages/settings_page.dart`

## Later additions attached to earlier unit surfaces

These links route later-added paths back to the delivery unit whose authority surface they amend; they are not claims that the files existed during that unit.

- `061-abo-p1-1-membership-active-org` → `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` (see exact commit history in JSON).
- `062-abo-p1-2-tenant-scoping-cross-tenant-suite` → `backend/supabase/migrations/20261009120000_fix_staff_membership_session_rls.sql` (see exact commit history in JSON).
- `066-abo-p3-2-issuer-tokens-registry-tenant-bindings` → `ai-platform/migrations/20260803120000_token_contract.sql` (see exact commit history in JSON).
- `068-abo-p3-4-admission-settlement-against-terms` → `ai-platform/migrations/20261014120000_ai_request_idempotency_fingerprint.sql` (see exact commit history in JSON).
- `087-abo-p5-1-issuer-key-custody-token-issuance` → `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` (see exact commit history in JSON).
- `087-abo-p5-1-issuer-key-custody-token-issuance` → `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql` (see exact commit history in JSON).
- `088-abo-p5-2-coverage-feed-puller-status-projection` → `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql` (see exact commit history in JSON).
- `089-abo-p6-1-desktop-contract-versions-token-minting` → `frontend/lib/core/rpc/app_rpc_invoker.dart` (see exact commit history in JSON).

Mandatory later-fix topics: staff/session RLS; canonical billing/feed JWT migrations; AI request fingerprint migration; payment intake and Paymob normalization; grant pipeline; runtime receipt decoding. `later_source_fix_topics` supplies phase routing.
