# P7.2 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Story grouping under rule S3

**Question:** The unit row has no Implements bullets. Its nine E2E scenarios are the only story candidates. Merging only scenarios that share a live entry point yields six stories: `/notify` and `/return` (E2E-P7.2-01, E2E-P7.2-04); staff billing-token RPC, `/v1/coverage`, and status RPCs (E2E-P7.2-02); cross-tenant ABO routes, RPCs, and platform routes (E2E-P7.2-03); `VendorEntrypoint` paid grant, class H, and class HP (E2E-P7.2-05, E2E-P7.2-06, E2E-P7.2-09); Worker config and PostgREST (E2E-P7.2-07); Dart network capture (E2E-P7.2-08). Size M allows 2–3 stories. Which Implements bullets should group these E2E ids?

**Assumption:** Three Implements bullets, one user story each, covering every E2E-P7.2 id. The six entry-point clusters stay merged and are not split again. Untrusted clinic and payment callers: E2E-P7.2-01, E2E-P7.2-02, E2E-P7.2-03, and E2E-P7.2-04. `VendorEntrypoint` paid grant and class H/HP: E2E-P7.2-05, E2E-P7.2-06, and E2E-P7.2-09. Credential isolation: E2E-P7.2-07 and E2E-P7.2-08. The unit stays one leaf. Spec 094, the codebase, size M, the dependencies, and the E2E text are unchanged.

**Why:** Rule S3 size M allows 2–3 user stories. Each Implements bullet is one candidate story. Bullets merge when they share an entry point until the count is in range, and a bullet splits only when the count is still under the minimum and its scenarios use two entry points. Shared entry points alone leave six stories, above that range. Three bullets put the count in range, so those bullets stay whole. The first story is the outsider or wrong-clinic caller (AD-1, AD-2, AD-3/A36, AD-5). The second is the operator and compromised-ABO path on `VendorEntrypoint` (AD-8, AD-11, AD-12, A27, A26 code half). The third is credential custody (A35, K-1): Worker config and the desktop session JWT. This is a story-grouping assumption, not a task-cap split into P7.2a and P7.2b.

**Amended:** `docs/architecture/ai-billing-orchestration/06-abo-delivery-plan.md` (P7.2 Implements).
