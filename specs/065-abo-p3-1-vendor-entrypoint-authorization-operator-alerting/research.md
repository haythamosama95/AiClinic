# Research: P3.1 R-5

**Unit**: P3.1 · **Requirements**: FR-001, FR-004, FR-011

Rule S6 places this spike in the plan phase. This unit's part is Access `amr` and service-binding caller identity. The named fallback, if the spike fails, is EdDSA-only credentials (05 §10, Spike-dependent items).

## 1. Questions

1. Does Access `amr` prove the operator's passkey for a class HP call?
2. Does a service binding expose an authenticated caller identity for class M?

P2.2 already recorded the WebAuthn ES256 DER-to-raw half of R-5. That conversion stays in the consumed `verifyAssertion`. This unit does not repeat it.

## 2. Access `amr`

The class H and HP check is the forwarded Access JWT, verified by the consumed `verifyAccessJwt` (`packages/vendor-contracts/src/access-jwt.ts`). That function returns `{ ok: true, email }` or `{ ok: false }`. It checks the team certificate, issuer, `aud`, and expiry. It does not read `amr`.

The installed workers types put an optional `amr?: string[]` on `CloudflareAccessIdentity`, reached through `ExecutionContext.access.getIdentity()`, and describe it as an identity-provider hint (the comment's example is `"pwd"`). That object is the Access identity of an HTTP request to this worker. `VendorEntrypoint` is not a `fetch` route and is not on the internet (FR-001). A service-binding RPC does not carry the operator's Access session in `ctx.access`. The operator's JWT arrives as the method argument `access_jwt` (FR-005).

`amr` is not the WebAuthn user-verification flag (04 §1.5). Class HP evidence is `verifyAssertion` on an active credential. This unit does not consult `amr` and does not change `verifyAccessJwt` (rule S7).

## 3. Service-binding caller identity

`WorkerEntrypoint` (`@cloudflare/workers-types`) exposes `env` and `ctx: ExecutionContext<Props>`. `ctx.props` is supplied by the caller. It is not a signature over the caller's script name. `ctx.access` is the HTTP Access context from section 2, not the calling worker.

Miniflare's service binding to the current worker (`kCurrentWorker` plus `entrypoint`) dispatches to the named class. The installed type describes that binding as a service designator. It adds no caller credential.

Class M evidence for `listOperatorCredentials` is the service binding itself (02 §3.3). The method changes no coverage, so it takes no ABO signature (FR-008). The class is not mounted on `fetch`. `workers_dev = false` and `preview_urls = false` (04 §6.4) keep the public dev and preview URLs off.

## 4. Outcome

| Item | Outcome |
| --- | --- |
| Access `amr` | Not meaningful for class HP. The consumed verifier returns the email only. `ctx.access` is not the forwarded JWT on this RPC entrypoint. |
| Service-binding caller identity | None is authenticated. Class M trusts the binding. `ctx.props` is not caller identity. |
| `workers_dev` and preview URLs | Turned off in wrangler, with the entrypoint absent from `fetch`, so the class is not reachable from the internet (FR-001). |
| Fallback | Not used. The questions are answered. EdDSA-only credentials would drop ES256, which the consumed `verifyAssertion` already verifies and which 04 §1.5 requires beside EdDSA (FR-011). |

## 5. Plan consequence

`src/vendor/entrypoint.ts` calls `verifyAccessJwt` and uses the email as `control_audit.actor` and as the actor compared to `actor_email`. It calls `verifyAssertion` for ES256 and EdDSA. It does not read `amr` or `ctx.props`. `listOperatorCredentials` has no signature check. Wrangler sets `workers_dev = false` and `preview_urls = false`.
