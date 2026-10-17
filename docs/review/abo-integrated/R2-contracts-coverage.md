# R2 contracts coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; HEAD verified. Ranges inclusive. Full production shared package reviewed; supporting caller reads below are bounded, not whole-file claims. No source tests/testkit/vectors/config tests/viewer/build/run reviewed or executed.

## Full primary reads

All 1,925 lines in `packages/vendor-contracts/src/*.ts`: access-jwt 1–146; base64url 1–19; canonical 1–65; coverage-snapshot 1–123; feed-event 1–71; grant-envelope 1–372; identifiers 1–102; index 1–41; jws 1–124; operation 1–65; receipt 1–182; result-envelope 1–80; token-claims 1–244; version 1–43; webauthn 1–248. `package.json`, `tsconfig.json`, `wrangler.toml` fully read. No testkit subpath implementation or package-lock audit.

## Supporting source actually read

| Path (repository-relative) | Inclusive ranges |
| --- | --- |
| `backend/supabase/migrations/20261014170000_canonical_billing_jwt_json.sql` | full 1–250 |
| `backend/supabase/migrations/20261014170100_canonical_feed_jwt_json.sql` | full 1–76 |
| `backend/supabase/migrations/20261007180000_issuer_key_custody.sql` | 180–229,1010–1090,1116–1139,1311–1340 |
| `backend/supabase/migrations/20261008010000_read_time_status_notices.sql` | 315–475 |
| `backend/supabase/migrations/20261007230000_coverage_feed_puller_status.sql` | 150–208,310–368,470–565 |
| `ai-platform/src/identity/index.ts` | 95–175,395–525 |
| `ai-platform/src/worker.ts` | 2190–2255 |
| `abo/src/clinic-api/auth.ts` | 180–335 |
| `ai-platform/src/vendor/entrypoint.ts` | 750–825,1150–1220,1350–1450,3200–3290,3480–3555,3960–4025 |
| `abo/src/ops/index.ts` | 230–290,430–525 |
| `abo/src/work/grant.ts` | 450–510,725–765 |
| `abo/src/work/reversal.ts` | 390–445,710–745 |
| `ai-platform/src/quota-do/coverage.ts` | 510–580,3040–3080 |
| `frontend/lib/core/contract_versions.dart` | full |
| `frontend/lib/core/rpc/rpc_result.dart` | full |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | full |
| `frontend/lib/core/ai/https_submit_port.dart` | full (supporting read, coordinator owns adjudication) |
| `frontend/lib/core/ai/discovery_client.dart` | full (same) |
| `frontend/lib/core/ai/usage_summary_client.dart` | full (same) |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | full |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | 65–128 |
| `frontend/lib/features/ai/billing/subscription_summary.dart` | 85–150 |
| `frontend/lib/features/ai/billing/abo_client.dart` | 600–800; version-field search only in earlier DTO regions |
| `frontend/lib/features/ai/billing/checkout_screen.dart` | 115–158,190–245,330–385; exception-symbol search elsewhere |

References: packet-R2; R1 canonical tenant/identity report; R2 manifest navigation; system map; relevant 04 canonical/JWS, assertion, receipt, token and channel paragraphs. Review plan/context file inventory read for exclusions/authority. Escalation JSON output was truncated; only named package/SQL records discussed in report are dispositioned, not an assertion that the whole inventory was read.

## Ownership limits / continuation

No unread primary shared production module remains. Platform/ABO siblings own full host/version dispatch, HP ceremony replay/actor/credential policy and registration lifecycle; coordinator owns complete phase escalation closure and DO version behavior. R4/R6 own grant/receipt business-state effects and transfer policy; R7 owns full SQL projection/refresh concurrency and desktop UX; R9 owns durable replay/rebuild implications. No whole-file coverage is inferred from searches or supporting slices.
