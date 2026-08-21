# AI Platform Data Journey — Source File Index

---

| Area                   | Path                                                                              |
| ---------------------- | --------------------------------------------------------------------------------- |
| Worker entry           | `ai-platform/src/worker.ts`                                                       |
| Ingress adapter        | `ai-platform/src/adapter.ts`                                                      |
| Guard pipeline         | `ai-platform/src/pipeline/index.ts`                                               |
| Identity / AAT         | `ai-platform/src/identity/index.ts`                                               |
| Entitlement            | `ai-platform/src/entitlement/index.ts`                                            |
| Admission              | `ai-platform/src/admission/index.ts`                                              |
| Journal + R2           | `ai-platform/src/journal/index.ts`                                                |
| Router                 | `ai-platform/src/router/index.ts`                                                 |
| Invocation             | `ai-platform/src/invocation/index.ts`                                             |
| Stream broker          | `ai-platform/src/stream/index.ts`                                                 |
| Canonical types        | `ai-platform/src/contracts/canonical.ts`                                          |
| Providers              | `ai-platform/src/provider/deepseek.ts`, `gemini.ts`, `fake.ts`                    |
| Quota DO               | `ai-platform/src/quota-do/index.ts`                                               |
| Config cache           | `ai-platform/src/config-cache/index.ts`                                           |
| Control enroll         | `ai-platform/src/control/lifecycle.ts`                                            |
| Control entitle        | `ai-platform/src/control/entitle.ts`                                              |
| Routing policy         | `ai-platform/src/control/routing-policy.ts`                                       |
| Token contract         | `ai-platform/src/control/token-contract.ts`                                       |
| Errors taxonomy        | `ai-platform/src/errors.ts`                                                       |
| Wrangler config        | `ai-platform/wrangler.toml`                                                       |
| D1 migrations          | `ai-platform/migrations/*.sql`                                                    |
| Visit summary manifest | `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`                 |
| Clinic keypair RPC     | `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` |
| AAT issuer RPC         | `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql`              |
| AAT contract spec      | `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md`               |


---

*This document was derived from runtime code in* `ai-platform/` *and clinic Supabase migrations. When code changes, update the corresponding stage section and column tables.*
