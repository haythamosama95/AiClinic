# R1 consumer coverage

Target `db9244fddfddc1905335fb8c7105328c15a0cc5e`; 2026-10-16. All assigned non-backend R1 primary regions read at T; backend ownership remains sibling R1-SQL. Result: complete with findings. This manifest records actual reads, not whole-file ownership of supporting paths. No source edits or excluded implementation reads.

## Primary regions read

| Path | Exact inclusive ranges |
| --- | --- |
| `abo/src/clinic-api/auth.ts` | 1–310 |
| `ai-platform/migrations/20261003130000_issuer_key_tenant_binding.sql` | 1–41 |
| `ai-platform/src/identity/index.ts` | 1–556 |
| `ai-platform/src/vendor/entrypoint.ts` | 209–230, 309–322, 328–369, 548–602, 676–688, 2193–2765 |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | 1–41 |
| `frontend/lib/core/rpc/app_rpc_invoker.dart` | 1–111 |
| `frontend/lib/features/ai/billing/billing_token_client.dart` | 1–128 |

## Supporting source read for the R1 seams

- `packages/vendor-contracts/src/token-claims.ts` 1–244; `canonical.ts` 1–65; `operation.ts` 1–65; `access-jwt.ts` 1–146; `webauthn.ts` 1–248. Claims/canonical support establishes the C1 defect and SQL byte requirements; HP dependencies read only to establish registry authorization, not a completed R2 package review.
- `ai-platform/src/config-cache/index.ts` 1–450: cache/load/reader, including issuer/binding/installation/token-contract branches.
- `ai-platform/src/vendor/entrypoint.ts` additional 209–370, 548–602, 676–688, 695–1335, 1858–1872: row decoding, base64, Access certificate fetching/verification, credential read/promotion, operation/hash/field binding, replay and assertion checks/audit. Regions outside R1 primary method bodies are supporting only.
- `ai-platform/src/worker.ts` 1–80, 1392–1440, 2100–2290, 2370–2510: production verifier context, feed key import/status/claims and actual route callers. Feed payload correctness belongs R7.
- `ai-platform/src/discovery/index.ts` 1–134; `coverage-read/index.ts` 1–145; `pipeline/index.ts` 330–420; `journal/index.ts` 469–503, 543–610; `capability/index.ts` 225–250: caller-to-receiver identity, scope/role gate and installation-scoped request lookup.
- `ai-platform/src/clock.ts` 1–46; alert/index.ts 322–377, 400–435 and rate-limit/index.ts 55–85: production clock gate, registry/cap alert calls and rejection metric. Full delivery internals of alerts are R9.
- `ai-platform/migrations/20261003140000_plan_version_paid_grant_coverage.sql` 1–10 (service-key schema); searches across migration SQL found no issuer-table later ALTER/CHECK override. No test configuration read.
- `abo/src/worker.ts` 1–80, 185–355: environment/token types and actual host/version/auth/rate/tenant dispatch; `clinic-api/rate.ts` 1–64; `clinic-api/billing-contact.ts` 45–160; `clinic-api/checkouts.ts` 195–220, 520–555, 595–620, 860–920; `clinic-api/billing-reads.ts` 1–170, 170–295: auth claim receivers, owner filters, durable JTI propagation. Only those concerns assessed here.
- `abo/src/ops/index.ts` 2525–2608, 3590–3666 and `watch/hourly.ts` 80–150: actual issuer/service relay and pin-set consumer; general operator/browser ceremony and alert semantics remain R2/R8/R9. `abo/src/clock.ts` complete 1–40.
- `frontend/lib/core/rpc/rpc_result.dart` complete; `core/contract_versions.dart` complete; `core/ai/ports.dart` 1–80; `core/ai/ai_client_sdk.dart` complete (1–end); `core/ai/https_submit_port.dart` 1–180; `core/ai/discovery_client.dart` 45–125; `core/ai/usage_summary_client.dart` 30–100. Token-only HTTP boundary and cache/remint behavior assessed; response/presentation behavior handed to R7.
- `frontend/lib/features/ai/billing/administrator_billing_page.dart` 1–160; `billing/abo_client.dart` 570–800; `presentation/pages/ai_page.dart` 1–185, 355–470, 620–end: token client/SDK composition, lifetime and identity listeners.
- `frontend/lib/app/router.dart` 1–150 and `app/providers/auth_session_provider.dart` complete: actual administrator redirect/auth refresh; no production `set_active_organization` caller found in frontend source search.
- `ai-platform/wrangler.toml`: targeted configuration search for clock/cert/cache/Supabase values; `abo/wrangler.toml` complete. Config environment review beyond R1 identity and bypass accessibility remains R9.

## Reference material and escalation disposition

Read repository AGENTS.md and constitution; complete review plan in bounded reads (some output repeated after tool truncation); packet-index, packet-R1, manifest-R1 markdown and machine manifest; system map; escalations-R1 full records (14 routed IDs). Amended architecture: 02 trust boundaries/credential/token profiles, rotation and constitution sections; 03 identity schema rows and section 4; 04 token claims/clinic API, status/RPC/read/feed/coverage contracts. Source findings rely on final T, never history summaries. No historical implementation diffs were necessary because all assigned non-backend primary regions are retained T regions.

| ID | R1 disposition / consumer owner |
| --- | --- |
| 066:1 | Registry envelope/raw-key producer to AI/ABO/pin comparison read; no encoding discrepancy found. |
| 066:2 | First-installation/epoch count read; cap enforcement C2. |
| 066:3 | Sequential cap return/AL20 path read; C2 covers concurrent enforcement. |
| 066:4 | Retire/revoke state producers and key verifier consumers read; no silent resurrection. |
| 066:5 | Reference propagation of :1–:4; no extra implementation rule. |
| 066:6 | Final identity/cache replacement verified; admission/tier removal completeness belongs R5/R8. |
| 066:7, :8, :9 | Reference-only/excluded effect confirmed; no harness implementation read. |
| 076:1 | Auth route consumes prior host/version gate; full host/version error/export correctness R2/R9. |
| 077:1 | JTI claim → checkout fact field traced; payment and return version R3/R9/R2. |
| 087:1 | Signing/next/retired SQL distinction supplied by sibling; active/retiring/revoked verifier states checked here. |
| 087:2 | Reference-only/excluded effect; clock override is absent from production vars inspected. |
| 088:1 | SQL/R7 owns refresh clock; AppRpcInvoker and RpcResult preserve backend rejection codes. |

No unread assigned primary range remains. Full R1 completion still requires the coordinator's SQL/consumer reconciliation, with SQL authority defects retained rather than assuming staff/membership synchronization. Open future-phase seams are explicitly listed in the review report; no R2–R10 completion is implied.
