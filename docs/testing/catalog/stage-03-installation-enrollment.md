# Stage 03 — Platform installation enrollment (control plane lifecycle)

Source files read: `ai-platform/src/control/lifecycle.ts`, `ai-platform/src/control/auth.ts`, `ai-platform/src/control/http.ts`, `ai-platform/src/control/audit.ts`, `ai-platform/src/control/types.ts`, `ai-platform/src/control/index.ts`, `ai-platform/src/control/support-purge.ts`, `ai-platform/src/retention/index.ts` (purgeByInstallationId, writePurgeAudit), `ai-platform/src/platform-vocabulary.ts`, `ai-platform/src/worker.ts` (control route gate + fall-through 404), `ai-platform/migrations/20260731120000_platform_schema.sql`, `ai-platform/migrations/20260821130000_entitlement_installation_unique.sql`, `docs/architecture/ai-platform/data-journey/05-stage-3-platform-installation-enrollment.md` (orientation only).

Shared concrete values used throughout this chapter:

- Worker origin: `http://localhost:8787` (vitest-pool-workers `SELF` / local dev).
- Operator credential: `Authorization: Bearer op-token-9f8e7d6c5b4a` (env `OPERATOR_BEARER_TOKEN`); wrong token: `op-token-WRONG`.
- Operator id written to audit rows: `platform-operator` (env `OPERATOR_ID`).
- Primary installation `I0` = `3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d`, org `ORG0` = `7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d`, enroll key `K0` = `c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f` with public key `X0` = `n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk` (base64url of 32 Ed25519 bytes).
- Second installation `I2` = `aa10c4d2-5e6f-4a7b-8c9d-0e1f2a3b4c5d`, org `ORG2` = `8b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e`, enroll key `KI2` = `1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d` with public key `XI2` = `dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4`.
- Third installation `I3` = `bb20d5e3-6f7a-4b8c-9d0e-1f2a3b4c5d6e`, org `ORG3` = `9c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f`, enroll key `KI3` = `2b3c4d5e-6f7a-4b8c-9d0e-1f2a3b4c5d6e` with public key `XI3` = `PqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuV`.
- Rotation keys for `I0`: `K1` = `d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a` / `X1` = `Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV`; for `I2`: `K2` = `e6f7a8b9-0c1d-4e2f-9a3b-4c5d6e7f8a9b` / `X2` = `mZx1QwErTyUiOp9sDfGhJkLzXcVbNm2QeRtYuIoPaSd`.
- Never-enrolled installation id `IUNKNOWN` = `00000000-0000-4000-8000-000000000099`; never-registered kid `KUNKNOWN` = `f7a8b9c0-1d2e-4f3a-ab4c-5d6e7f8a9b0c`.
- Canonical valid enroll body for `I0` (mutated per scenario):

```json
{
  "org_id": "7a1b2c3d-4e5f-4a6b-9c8d-0e1f2a3b4c5d",
  "display_name": "Verify Clinic",
  "region": "eu-central",
  "plan": "standard",
  "public_key": "n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk",
  "algorithm": "EdDSA",
  "kid": "c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f"
}
```

---

## Scenario S03-001 — Enroll rejects a request with no Authorization header

| Field | Content |
|-------|---------|
| ID | S03-001 |
| Journey setup | None. D1 migrated; `installation` empty. Auth is checked before any route, payload, or storage work, so no prior state is required. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll` with header `Content-Type: application/json`, no `Authorization` header, body = canonical enroll JSON above. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`, `content-type: application/json`. |
| Side effects | None. `installation`, `installation_key`, `entitlement`, `control_audit` all remain empty. |
| Code reference | ai-platform/src/control/http.ts:L3-L8 — unauthorized; ai-platform/src/control/http.ts:L31-L41 — requireOperator; ai-platform/src/control/auth.ts:L33-L48 — createSecretOperatorAuth.resolve |

## Scenario S03-002 — Enroll rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-002 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll`, headers `Authorization: Bearer op-token-WRONG`, `Content-Type: application/json`, body = canonical enroll JSON. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. The timing-safe compare returns false; no 403 exists anywhere on the control plane. |
| Side effects | None; all four control-plane tables remain empty. |
| Code reference | ai-platform/src/control/auth.ts:L4-L14 — timingSafeEqualString; ai-platform/src/control/auth.ts:L44-L47 — token mismatch returns null |

## Scenario S03-003 — Rotate rejects a missing bearer token

| Field | Content |
|-------|---------|
| ID | S03-003 |
| Journey setup | None (auth precedes the installation lookup). |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/rotate`, `Content-Type: application/json`, no `Authorization`, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L299-L302 — handleRotate auth gate |

## Scenario S03-004 — Rotate rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-004 |
| Journey setup | None. |
| Action | Same as S03-003 but with header `Authorization: Bearer op-token-WRONG`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L299-L302 — handleRotate auth gate |

## Scenario S03-005 — Revoke-key rejects a missing bearer token

| Field | Content |
|-------|---------|
| ID | S03-005 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/revoke-key`, `Content-Type: application/json`, no `Authorization`, body `{"kid":"c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f"}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L383-L386 — handleRevokeKey auth gate |

## Scenario S03-006 — Revoke-key rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-006 |
| Journey setup | None. |
| Action | Same as S03-005 but with header `Authorization: Bearer op-token-WRONG`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L383-L386 — handleRevokeKey auth gate |

## Scenario S03-007 — Suspend rejects a missing bearer token

| Field | Content |
|-------|---------|
| ID | S03-007 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/suspend`, `Content-Type: application/json`, no `Authorization`, body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L470-L473 — handleSuspend auth gate |

## Scenario S03-008 — Suspend rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-008 |
| Journey setup | None. |
| Action | Same as S03-007 but with header `Authorization: Bearer op-token-WRONG`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L470-L473 — handleSuspend auth gate |

## Scenario S03-009 — Resume rejects a missing bearer token

| Field | Content |
|-------|---------|
| ID | S03-009 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/resume`, `Content-Type: application/json`, no `Authorization`, body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L523-L526 — handleResume auth gate |

## Scenario S03-010 — Resume rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-010 |
| Journey setup | None. |
| Action | Same as S03-009 but with header `Authorization: Bearer op-token-WRONG`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L523-L526 — handleResume auth gate |

## Scenario S03-011 — Delete rejects a missing bearer token

| Field | Content |
|-------|---------|
| ID | S03-011 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/delete`, `Content-Type: application/json`, no `Authorization`, body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L573-L576 — handleDelete auth gate |

## Scenario S03-012 — Delete rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-012 |
| Journey setup | None. |
| Action | Same as S03-011 but with header `Authorization: Bearer op-token-WRONG`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L573-L576 — handleDelete auth gate |

## Scenario S03-013 — Purge rejects a missing bearer token

| Field | Content |
|-------|---------|
| ID | S03-013 |
| Journey setup | None. Auth precedes even the R2-binding check in `handleInstallationPurge`. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/purge`, `Content-Type: application/json`, no `Authorization`, body `{}`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None — in particular no `purge_installation` audit row is written. |
| Code reference | ai-platform/src/control/support-purge.ts:L62-L65 — handleInstallationPurge auth gate |

## Scenario S03-014 — Purge rejects a wrong bearer token

| Field | Content |
|-------|---------|
| ID | S03-014 |
| Journey setup | None. |
| Action | Same as S03-013 but with header `Authorization: Bearer op-token-WRONG`. |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/support-purge.ts:L62-L65 — handleInstallationPurge auth gate |

## Scenario S03-015 — Malformed Authorization schemes and empty tokens are rejected

| Field | Content |
|-------|---------|
| ID | S03-015 |
| Journey setup | None. Representative route: enroll; the same `resolve` gates every lifecycle route. |
| Action | Three requests to `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll` with the canonical enroll body: (a) header `Authorization: Bearer ` (scheme with trailing space, empty token — `slice("Bearer ".length).trim()` yields `""`); (b) header `Authorization: Basic b3A6cGFzcw==`; (c) header `Authorization: op-token-9f8e7d6c5b4a` (no scheme prefix, fails `startsWith("Bearer ")`). |
| Expected outcome | HTTP 401 with body exactly `{"error":"unauthorized"}` for all three requests. |
| Side effects | None. |
| Code reference | ai-platform/src/control/auth.ts:L37-L44 — scheme prefix check and empty-token check |

## Scenario S03-016 — Auth is checked before route-shape and payload validation

| Field | Content |
|-------|---------|
| ID | S03-016 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/not-a-uuid/enroll`, no `Authorization`, `Content-Type: application/json`, body `not-json` (would be `invalid_payload` on the path id and `invalid_json` on the body if validation ran first). |
| Expected outcome | HTTP 401, body exactly `{"error":"unauthorized"}` — never a 400. Handler order is `requireOperator` → `requireValidInstallationId` → `parseJsonBody`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L204-L216 — handleEnroll gate ordering |

## Scenario S03-017 — Unknown installation action falls through to a plain-text 404

| Field | Content |
|-------|---------|
| ID | S03-017 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/obliterate` with valid operator bearer and body `{}`. |
| Expected outcome | HTTP 404, body `Not Found` (plain text, no JSON envelope, no `error` field). `CONTROL_ACTION_PATTERN` does not match `obliterate`, so the request never enters control dispatch and hits the worker fall-through. |
| Side effects | None. |
| Code reference | ai-platform/src/control/index.ts:L69-L70 — CONTROL_ACTION_PATTERN; ai-platform/src/worker.ts:L1440-L1444 — route_not_found fall-through |

## Scenario S03-018 — Non-POST method on a lifecycle route falls through to a plain-text 404

| Field | Content |
|-------|---------|
| ID | S03-018 |
| Journey setup | None. |
| Action | `GET http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/suspend` with valid operator bearer. |
| Expected outcome | HTTP 404, body `Not Found` (plain text). The worker only admits control routes when `method === "POST"` (GET is reserved for the quota-inspect route, another chapter). No 405 exists. |
| Side effects | None. |
| Code reference | ai-platform/src/worker.ts:L1354-L1359 — method gate on isControlRoute |

## Scenario S03-019 — Trailing slash on a lifecycle route falls through to a plain-text 404

| Field | Content |
|-------|---------|
| ID | S03-019 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll/` (trailing slash) with valid operator bearer and canonical enroll body. |
| Expected outcome | HTTP 404, body `Not Found` (plain text). `CONTROL_ACTION_PATTERN` is end-anchored after the action verb, so the trailing slash prevents a match. |
| Side effects | None. |
| Code reference | ai-platform/src/control/index.ts:L69-L70 — CONTROL_ACTION_PATTERN anchoring |

## Scenario S03-020 — Enroll rejects a non-JSON body

| Field | Content |
|-------|---------|
| ID | S03-020 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll`, operator bearer, `Content-Type: application/json`, body `not-json`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_json"}`. |
| Side effects | None; all four tables remain empty. |
| Code reference | ai-platform/src/control/http.ts:L43-L49 — parseJsonBody |

## Scenario S03-021 — Enroll rejects a non-object JSON body

| Field | Content |
|-------|---------|
| ID | S03-021 |
| Journey setup | None. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll`, operator bearer, body `[1,2,3]` (JSON array). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. JSON `null` and JSON scalars (e.g. `"hello"`, `42`) hit the same `body === null || typeof body !== "object" || Array.isArray(body)` guard and produce the identical response. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L87-L89 — validateEnrollPayload object guard |

## Scenario S03-022 — Enroll rejects a missing org_id

| Field | Content |
|-------|---------|
| ID | S03-022 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with the `org_id` field removed entirely. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` (`requireNonEmptyString(undefined)` → null). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L90-L107 — validateEnrollPayload required-field sweep; ai-platform/src/control/http.ts:L51-L56 — requireNonEmptyString |

## Scenario S03-023 — Enroll rejects a blank display_name

| Field | Content |
|-------|---------|
| ID | S03-023 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"display_name": "   "` (whitespace-only). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` (`value.trim() === ""`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L51-L56 — requireNonEmptyString trim check |

## Scenario S03-024 — Enroll rejects a non-string region

| Field | Content |
|-------|---------|
| ID | S03-024 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"region": 42` (number). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` (`typeof value !== "string"`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L51-L56 — requireNonEmptyString type check |

## Scenario S03-025 — Enroll rejects a missing plan

| Field | Content |
|-------|---------|
| ID | S03-025 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with the `plan` field removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L93-L107 — required-field sweep |

## Scenario S03-026 — Enroll rejects a missing public_key

| Field | Content |
|-------|---------|
| ID | S03-026 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with the `public_key` field removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L94-L107 — required-field sweep |

## Scenario S03-027 — Enroll rejects a missing algorithm

| Field | Content |
|-------|---------|
| ID | S03-027 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with the `algorithm` field removed. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L95-L107 — required-field sweep |

## Scenario S03-028 — Enroll rejects a missing kid

| Field | Content |
|-------|---------|
| ID | S03-028 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with the `kid` field removed (equivalently `"kid": ""`). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L96-L107 — required-field sweep |

## Scenario S03-029 — Enroll rejects an unknown plan tier

| Field | Content |
|-------|---------|
| ID | S03-029 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"plan": "platinum"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. Closed tier vocabulary is `starter`, `standard`, `professional`, `enterprise`; the check is case-sensitive (`"Standard"` also fails). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L108-L110 — plan check; ai-platform/src/platform-vocabulary.ts:L2-L8 — PLAN_TIERS; ai-platform/src/platform-vocabulary.ts:L27-L29 — isKnownPlanTier |

## Scenario S03-030 — Enroll rejects an unsupported algorithm

| Field | Content |
|-------|---------|
| ID | S03-030 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"algorithm": "RS256"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. Only the exact string `EdDSA` is accepted (case-sensitive: `"eddsa"` fails). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L111-L113 — algorithm check; ai-platform/src/platform-vocabulary.ts:L31-L33 — isSupportedInstallationKeyAlgorithm |

## Scenario S03-031 — Enroll rejects a non-UUID org_id

| Field | Content |
|-------|---------|
| ID | S03-031 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"org_id": "x"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L114-L116 — UUID checks; ai-platform/src/platform-vocabulary.ts:L35-L37 — isCanonicalUuid |

## Scenario S03-032 — Enroll rejects a non-UUID kid

| Field | Content |
|-------|---------|
| ID | S03-032 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"kid": "key-1"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L114-L116 — UUID checks |

## Scenario S03-033 — Enroll rejects a non-UUID path installation_id

| Field | Content |
|-------|---------|
| ID | S03-033 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/not-a-uuid/enroll`, operator bearer, canonical enroll body. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. The path segment matches the dispatch pattern (`[^/]+`) but fails `isCanonicalUuid` inside the handler. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L45-L55 — requireValidInstallationId; ai-platform/src/control/lifecycle.ts:L38-L43 — parseInstallationId |

## Scenario S03-034 — Enroll rejects a public_key that decodes to the wrong byte length

| Field | Content |
|-------|---------|
| ID | S03-034 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"public_key": "c2hvcnQ"` (valid base64url, decodes to 5 bytes, not 32). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` via `isEd25519PublicKeyByteLength` inside `validateEnrollPayload` (the async import check is never reached). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L117-L119 — public_key length check; ai-platform/src/platform-vocabulary.ts:L53-L61 — isEd25519PublicKeyByteLength |

## Scenario S03-035 — Enroll rejects a public_key that is not base64url-decodable

| Field | Content |
|-------|---------|
| ID | S03-035 |
| Journey setup | None. |
| Action | `POST …/enroll` for `I0`, operator bearer, canonical enroll body with `"public_key": "!!!not-base64!!!"`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}` (`decodeBase64url` returns null → length check fails). |
| Side effects | None. |
| Code reference | ai-platform/src/platform-vocabulary.ts:L39-L51 — decodeBase64url; ai-platform/src/platform-vocabulary.ts:L53-L61 — isEd25519PublicKeyByteLength |

## Scenario S03-036 — Enroll accepts uppercase hex UUIDs (boundary)

| Field | Content |
|-------|---------|
| ID | S03-036 |
| Journey setup | None. D1 has no rows for `I2`/`ORG2`. |
| Action | `POST http://localhost:8787/control/installations/AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D/enroll`, operator bearer, body `{"org_id":"8B2C3D4E-5F6A-4B7C-8D9E-0F1A2B3C4D5E","display_name":"Boundary Clinic","region":"eu-central","plan":"starter","public_key":"dGhJkLzXcVbNm2QeRtYuIoPaSd8f7a9b0c1d2e3f4","algorithm":"EdDSA","kid":"1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D"}` (all UUIDs uppercase). |
| Expected outcome | HTTP 200, body exactly `{"platform_base_url":"http://localhost:8787"}`. `CANONICAL_UUID_RE` carries the `/i` flag, so uppercase hex passes and the strings are stored verbatim (uppercase) in D1. Note: later scenarios reference `I2`/`KI2` by their lowercase forms only for readability — all D1 assertions for this installation use the uppercase stored values. |
| Side effects | `installation` row for the uppercase id with `status = active`; `installation_key` row `1A2B3C4D-…` with `revoked_at = NULL`; `entitlement` row `plan = starter`, `status = pending`; `control_audit` row `action = enroll`, `operator_id = platform-operator`. |
| Code reference | ai-platform/src/platform-vocabulary.ts:L20-L22 — CANONICAL_UUID_RE with /i; ai-platform/src/control/lifecycle.ts:L199-L291 — handleEnroll |

## Scenario S03-037 — Enroll happy path registers installation, key, pending entitlement, and audit

| Field | Content |
|-------|---------|
| ID | S03-037 |
| Journey setup | Stage 2 clinic keypair enrollment produced `installation_id = I0`, `kid = K0`, `public_jwk.x = X0`; the operator copies those values into the enroll call. Platform D1 has no row for `I0` or `ORG0` (verified by the S03-020…S03-035 probes writing nothing). |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/enroll`, headers `Authorization: Bearer op-token-9f8e7d6c5b4a`, `Content-Type: application/json`, body = canonical enroll JSON above. |
| Expected outcome | HTTP 200, body exactly `{"platform_base_url":"http://localhost:8787"}` (`new URL(request.url).origin` — the only field; no token, no quota fields). |
| Side effects | One atomic D1 batch writes: (1) `installation` row `installation_id = I0`, `org_id = ORG0`, `display_name = Verify Clinic`, `status = active`, `region = eu-central`, `enrolled_at = <now ISO>`; (2) `installation_key` row `key_id = K0`, `installation_id = I0`, `public_key = X0`, `algorithm = EdDSA`, `valid_from = enrolled_at`, `valid_until = valid_from + 365 days` (`INSTALLATION_KEY_TTL_DAYS`), `revoked_at = NULL`; (3) `entitlement` row with new UUID `entitlement_id`, `plan = standard`, `period_start = period_end = enrolled_at`, `request_quota = 0`, `token_budget = 0`, `cost_budget = 0`, `allowed_capabilities = '[]'`, `soft_threshold = 0`, `status = pending`; (4) `control_audit` row `action = enroll`, `target = I0`, `operator_id = platform-operator`, `before_pointer = after_pointer = NULL`. No R2 writes. No `capability_grant` rows. |
| Code reference | ai-platform/src/control/lifecycle.ts:L199-L291 — handleEnroll; ai-platform/src/control/lifecycle.ts:L29-L36 — INSTALLATION_KEY_TTL_DAYS / installationKeyValidUntil; ai-platform/migrations/20260731120000_platform_schema.sql:L4-L38 — installation, installation_key, entitlement tables |

## Scenario S03-038 — Re-enroll of the same installation_id returns already_enrolled

| Field | Content |
|-------|---------|
| ID | S03-038 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | Repeat the exact S03-037 request (same path id, same body). |
| Expected outcome | HTTP 409, body exactly `{"error":"already_enrolled"}` (pre-SELECT matches on `installation_id`). |
| Side effects | None — row counts for `installation`, `installation_key`, `entitlement`, `control_audit` unchanged; no new batch is attempted. |
| Code reference | ai-platform/src/control/lifecycle.ts:L230-L238 — existing-row pre-check |

## Scenario S03-039 — Enroll of a new installation_id with an existing org_id returns already_enrolled

| Field | Content |
|-------|---------|
| ID | S03-039 |
| Journey setup | S03-037 enrolled `I0` with `ORG0`. |
| Action | `POST http://localhost:8787/control/installations/4a5b6c7d-8e9f-4a0b-bc1d-2e3f4a5b6c7d/enroll`, operator bearer, canonical enroll body with `"display_name": "Verify Clinic DR"` and `"kid": "5b6c7d8e-9f0a-4b1c-8d2e-3f4a5b6c7d8e"` (fresh path id and kid, same `org_id = ORG0`). |
| Expected outcome | HTTP 409, body exactly `{"error":"already_enrolled"}` — the pre-SELECT is `installation_id = ? OR org_id = ?`, so `org_id` alone triggers the conflict. |
| Side effects | None; no row is created for the new path id. |
| Code reference | ai-platform/src/control/lifecycle.ts:L230-L238 — existing-row pre-check |

## Scenario S03-040 — Enroll reusing an existing kid fails the batch with duplicate_kid and leaves no orphan installation

| Field | Content |
|-------|---------|
| ID | S03-040 |
| Journey setup | S03-037 enrolled `I0` with key `K0`. |
| Action | `POST http://localhost:8787/control/installations/6c7d8e9f-0a1b-4c2d-9e3f-4a5b6c7d8e9f/enroll`, operator bearer, body `{"org_id":"ad4e5f6a-7b8c-4d9e-ae0f-1a2b3c4d5e6f","display_name":"Other Clinic","region":"eu-central","plan":"standard","public_key":"n4bQgYhMfWWaL-qgxVrQ1O91g3Z2Q4u2Zz8v0m5p8xk","algorithm":"EdDSA","kid":"c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f"}` (fresh installation id and org, but `kid = K0` already in `installation_key`). |
| Expected outcome | HTTP 409, body exactly `{"error":"duplicate_kid"}`. The pre-SELECT passes (new id and org); the D1 batch fails on `UNIQUE constraint failed: installation_key.key_id` and `constraintTarget` maps the message to `installation_key`. |
| Side effects | The batch is transactional: no `installation` row for `6c7d8e9f-…`, no second `installation_key` row, no `entitlement` row, no `control_audit` row. `installation` still contains exactly the S03-036 and S03-037 rows. |
| Code reference | ai-platform/src/control/lifecycle.ts:L162-L179 — isUniqueConstraint / constraintTarget; ai-platform/src/control/lifecycle.ts:L181-L197 — runControlBatch; ai-platform/migrations/20260731120000_platform_schema.sql:L13-L22 — installation_key PK |

## Scenario S03-041 — Suspend of an unknown installation returns installation_not_found

| Field | Content |
|-------|---------|
| ID | S03-041 |
| Journey setup | None beyond migrations; `IUNKNOWN` was never enrolled. |
| Action | `POST http://localhost:8787/control/installations/00000000-0000-4000-8000-000000000099/suspend`, operator bearer, body `{}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L481-L490 — handleSuspend installation lookup |

## Scenario S03-042 — Suspend happy path freezes an active installation

| Field | Content |
|-------|---------|
| ID | S03-042 |
| Journey setup | S03-037 enrolled `I0` (`status = active`). |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/suspend`, operator bearer, `Content-Type: application/json`, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | `installation.status` for `I0` becomes `suspended`; `control_audit` gains a row `action = suspend`, `target = I0`, `operator_id = platform-operator`, both pointers NULL. `entitlement.status` is NOT changed (stays `pending`); `installation_key` untouched. |
| Code reference | ai-platform/src/control/lifecycle.ts:L466-L516 — handleSuspend |

## Scenario S03-043 — Suspend of an already-suspended installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-043 |
| Journey setup | S03-042 suspended `I0`. |
| Action | Repeat the S03-042 request. |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}` (status `suspended` matches the rejected set). |
| Side effects | None; `control_audit` gains no row. |
| Code reference | ai-platform/src/control/lifecycle.ts:L492-L497 — suspend status guard |

## Scenario S03-044 — Resume of an unknown installation returns installation_not_found

| Field | Content |
|-------|---------|
| ID | S03-044 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/00000000-0000-4000-8000-000000000099/resume`, operator bearer, body `{}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L534-L543 — handleResume installation lookup |

## Scenario S03-045 — Resume happy path restores a suspended installation to active

| Field | Content |
|-------|---------|
| ID | S03-045 |
| Journey setup | S03-042 suspended `I0` (S03-043 confirmed the suspended state). |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/resume`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | `installation.status` for `I0` becomes `active`; `control_audit` gains a row `action = resume`, `target = I0`, `operator_id = platform-operator`, pointers NULL. No other table changes. |
| Code reference | ai-platform/src/control/lifecycle.ts:L518-L564 — handleResume |

## Scenario S03-046 — Resume of an active installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-046 |
| Journey setup | S03-045 returned `I0` to `active`. |
| Action | Repeat the S03-045 request. |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}` — resume requires current status exactly `suspended`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L545-L547 — resume status guard |

## Scenario S03-047 — Suspend ignores the request body entirely

| Field | Content |
|-------|---------|
| ID | S03-047 |
| Journey setup | S03-036 enrolled `I2` (`status = active`). |
| Action | `POST http://localhost:8787/control/installations/AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D/suspend`, operator bearer, `Content-Type: text/plain`, body `this is not json at all`. |
| Expected outcome | HTTP 200, body exactly `{}`. `handleSuspend` (like `handleResume` and `handleDelete`) never calls `parseJsonBody`; the body is unread, so malformed JSON, wrong content type, or an empty body all succeed identically. |
| Side effects | `installation.status` for the `I2` row becomes `suspended`; `control_audit` gains an `action = suspend` row targeting the uppercase `I2` id. |
| Code reference | ai-platform/src/control/lifecycle.ts:L466-L516 — handleSuspend (no body read) |

## Scenario S03-048 — Rotate rejects a non-JSON body

| Field | Content |
|-------|---------|
| ID | S03-048 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/rotate`, operator bearer, body `not-json`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_json"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L43-L49 — parseJsonBody; ai-platform/src/control/lifecycle.ts:L309-L312 — handleRotate body parse |

## Scenario S03-049 — Rotate rejects a non-object JSON body

| Field | Content |
|-------|---------|
| ID | S03-049 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `["kid"]` (JSON array). `null` and scalars behave identically. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L134-L136 — validateRotatePayload object guard |

## Scenario S03-050 — Rotate rejects a missing kid

| Field | Content |
|-------|---------|
| ID | S03-050 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}` (no `kid`). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L137-L142 — rotate required-field sweep |

## Scenario S03-051 — Rotate rejects a missing public_key

| Field | Content |
|-------|---------|
| ID | S03-051 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","algorithm":"EdDSA"}` (no `public_key`). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L137-L142 — rotate required-field sweep |

## Scenario S03-052 — Rotate rejects a missing algorithm

| Field | Content |
|-------|---------|
| ID | S03-052 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV"}` (no `algorithm`). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L137-L142 — rotate required-field sweep |

## Scenario S03-053 — Rotate rejects an unsupported algorithm

| Field | Content |
|-------|---------|
| ID | S03-053 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"ES256"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L143-L145 — rotate algorithm check |

## Scenario S03-054 — Rotate rejects a non-UUID kid

| Field | Content |
|-------|---------|
| ID | S03-054 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"kid":"rotate-1","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L146-L148 — rotate kid UUID check |

## Scenario S03-055 — Rotate rejects a public_key of the wrong byte length

| Field | Content |
|-------|---------|
| ID | S03-055 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","public_key":"c2hvcnQ","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L149-L151 — rotate public_key length check |

## Scenario S03-056 — Rotate of an unknown installation returns installation_not_found

| Field | Content |
|-------|---------|
| ID | S03-056 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/00000000-0000-4000-8000-000000000099/rotate`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L325-L333 — handleRotate installation lookup |

## Scenario S03-057 — Rotate with an already-registered kid returns duplicate_kid

| Field | Content |
|-------|---------|
| ID | S03-057 |
| Journey setup | S03-037 enrolled `I0` with key `K0`. |
| Action | `POST …/rotate` for `I0`, operator bearer, body `{"kid":"c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}` (`kid = K0` already exists). |
| Expected outcome | HTTP 409, body exactly `{"error":"duplicate_kid"}`. The pre-check `SELECT key_id FROM installation_key WHERE key_id = ?` is global across installations — a kid enrolled by ANY installation (e.g. `KI2` from S03-036) triggers the same 409. |
| Side effects | None; no new key row, no audit row. |
| Code reference | ai-platform/src/control/lifecycle.ts:L339-L346 — rotate kid pre-check |

## Scenario S03-058 — Rotate happy path adds a second active key (dual-key overlap)

| Field | Content |
|-------|---------|
| ID | S03-058 |
| Journey setup | S03-037 enrolled `I0` (`K0` active); S03-045 resumed `I0` to `active`. Stage 2 clinic key rotation minted the successor `kid = K1` / `public_jwk.x = X1` for the same installation. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/rotate`, operator bearer, `Content-Type: application/json`, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 200, body exactly `{}` (no `platform_base_url` echo on post-enroll mutations). |
| Side effects | `installation_key` gains a row `key_id = K1`, `installation_id = I0`, `public_key = X1`, `algorithm = EdDSA`, `valid_from = <now>`, `valid_until = valid_from + 365 days`, `revoked_at = NULL`. `K0` is untouched (`revoked_at` stays NULL) — two active keys coexist until `revoke-key`. `control_audit` gains `action = rotate`, `target = I0`, `operator_id = platform-operator`, pointers NULL. `installation` and `entitlement` unchanged. |
| Code reference | ai-platform/src/control/lifecycle.ts:L293-L375 — handleRotate |

## Scenario S03-059 — Rotate succeeds on a suspended installation

| Field | Content |
|-------|---------|
| ID | S03-059 |
| Journey setup | S03-036 enrolled `I2`; S03-047 suspended `I2`. |
| Action | `POST http://localhost:8787/control/installations/AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D/rotate`, operator bearer, body `{"kid":"e6f7a8b9-0c1d-4e2f-9a3b-4c5d6e7f8a9b","public_key":"mZx1QwErTyUiOp9sDfGhJkLzXcVbNm2QeRtYuIoPaSd","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 200, body exactly `{}`. `handleRotate` rejects only `status = deleted`; `suspended` is not blocked. |
| Side effects | `installation_key` gains row `K2` for the `I2` id with `revoked_at = NULL`; `control_audit` gains `action = rotate` targeting the uppercase `I2` id. `installation.status` stays `suspended`. |
| Code reference | ai-platform/src/control/lifecycle.ts:L335-L337 — rotate blocks only deleted status |

## Scenario S03-060 — Revoke-key rejects a non-JSON body

| Field | Content |
|-------|---------|
| ID | S03-060 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/revoke-key`, operator bearer, body `not-json`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_json"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/http.ts:L43-L49 — parseJsonBody; ai-platform/src/control/lifecycle.ts:L392-L395 — handleRevokeKey body parse |

## Scenario S03-061 — Revoke-key rejects a non-object JSON body

| Field | Content |
|-------|---------|
| ID | S03-061 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/revoke-key` for `I0`, operator bearer, body `["c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f"]`. `null` and scalars behave identically. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L68-L72 — validateRevokeKeyPayload object guard |

## Scenario S03-062 — Revoke-key rejects a missing or empty kid

| Field | Content |
|-------|---------|
| ID | S03-062 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/revoke-key` for `I0`, operator bearer, body `{}` (equivalently `{"kid":""}` or `{"kid":"  "}`). |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L73-L76 — revoke kid required check |

## Scenario S03-063 — Revoke-key rejects a non-UUID kid

| Field | Content |
|-------|---------|
| ID | S03-063 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/revoke-key` for `I0`, operator bearer, body `{"kid":"old-key"}`. |
| Expected outcome | HTTP 400, body exactly `{"error":"invalid_payload"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L77-L80 — revoke kid UUID check |

## Scenario S03-064 — Revoke-key on an unknown installation returns installation_not_found

| Field | Content |
|-------|---------|
| ID | S03-064 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/00000000-0000-4000-8000-000000000099/revoke-key`, operator bearer, body `{"kid":"c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f"}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}` (installation lookup precedes the key lookup). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L404-L412 — handleRevokeKey installation lookup |

## Scenario S03-065 — Revoke-key of a well-formed but unknown kid returns key_not_found

| Field | Content |
|-------|---------|
| ID | S03-065 |
| Journey setup | S03-037 enrolled `I0`. |
| Action | `POST …/revoke-key` for `I0`, operator bearer, body `{"kid":"f7a8b9c0-1d2e-4f3a-ab4c-5d6e7f8a9b0c"}` (`KUNKNOWN`, never registered). |
| Expected outcome | HTTP 404, body exactly `{"error":"key_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L418-L427 — key row lookup |

## Scenario S03-066 — Revoke-key of a kid owned by a different installation returns key_not_found

| Field | Content |
|-------|---------|
| ID | S03-066 |
| Journey setup | S03-036 enrolled `I2` with key `KI2`; S03-037 enrolled `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/revoke-key`, operator bearer, body `{"kid":"1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"}` (`KI2`, which exists but belongs to `I2`). |
| Expected outcome | HTTP 404, body exactly `{"error":"key_not_found"}` — the lookup is scoped `WHERE key_id = ? AND installation_id = ?`, so cross-installation kids are indistinguishable from unknown kids. |
| Side effects | None; `KI2` remains active on `I2`. |
| Code reference | ai-platform/src/control/lifecycle.ts:L418-L427 — installation-scoped key lookup |

## Scenario S03-067 — Revoke-key happy path retires one key while another stays active

| Field | Content |
|-------|---------|
| ID | S03-067 |
| Journey setup | S03-037 enrolled `I0` (`K0`); S03-058 rotated in `K1`. Both keys active. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/revoke-key`, operator bearer, `Content-Type: application/json`, body `{"kid":"c4d5e6f7-8a9b-4c0d-9e1f-2a3b4c5d6e7f"}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | `installation_key` row `K0` gets `revoked_at = <now ISO>` (UPDATE guarded by `revoked_at IS NULL`); `K1` stays active. `control_audit` gains `action = revoke-key`, `target = I0`, `operator_id = platform-operator`, `before_pointer = NULL`, `after_pointer = K0` — the only lifecycle action that sets `after_pointer`. No other table changes. |
| Code reference | ai-platform/src/control/lifecycle.ts:L444-L464 — revoke UPDATE + audit insert |

## Scenario S03-068 — Revoke-key of an already-revoked key returns key_already_revoked

| Field | Content |
|-------|---------|
| ID | S03-068 |
| Journey setup | S03-067 revoked `K0` on `I0`. |
| Action | Repeat the S03-067 request. |
| Expected outcome | HTTP 409, body exactly `{"error":"key_already_revoked"}`. This check fires before the last-active-key count, so re-revoking a retired key never reports `cannot_revoke_last_active_key`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L429-L431 — revoked_at guard |

## Scenario S03-069 — Revoke-key of the sole remaining active key returns cannot_revoke_last_active_key

| Field | Content |
|-------|---------|
| ID | S03-069 |
| Journey setup | S03-067 left `K1` as the only active key on `I0` (`K0` revoked). |
| Action | `POST …/revoke-key` for `I0`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a"}`. |
| Expected outcome | HTTP 409, body exactly `{"error":"cannot_revoke_last_active_key"}` — active-key count for `I0` is 1, and `<= 1` blocks the revoke. Production remedy: rotate a successor first (S03-058), then revoke. |
| Side effects | None; `K1` keeps `revoked_at = NULL`. |
| Code reference | ai-platform/src/control/lifecycle.ts:L433-L442 — active key count guard |

## Scenario S03-070 — Revoke-key succeeds on a suspended installation

| Field | Content |
|-------|---------|
| ID | S03-070 |
| Journey setup | S03-036 enrolled `I2` (`KI2`); S03-047 suspended `I2`; S03-059 rotated `K2` onto suspended `I2` (two active keys). |
| Action | `POST http://localhost:8787/control/installations/AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D/revoke-key`, operator bearer, body `{"kid":"1a2b3c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"}`. |
| Expected outcome | HTTP 200, body exactly `{}`. `handleRevokeKey` blocks only `status = deleted`; suspension does not restrict key management. |
| Side effects | `KI2` row gets `revoked_at` set; `K2` stays active; `control_audit` gains `action = revoke-key`, `after_pointer = KI2`, targeting the uppercase `I2` id. `installation.status` stays `suspended`. |
| Code reference | ai-platform/src/control/lifecycle.ts:L414-L416 — revoke blocks only deleted status |

## Scenario S03-071 — Delete of an unknown installation returns installation_not_found

| Field | Content |
|-------|---------|
| ID | S03-071 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/00000000-0000-4000-8000-000000000099/delete`, operator bearer, body `{}`. |
| Expected outcome | HTTP 404, body exactly `{"error":"installation_not_found"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L584-L593 — handleDelete installation lookup |

## Scenario S03-072 — Delete happy path marks an active installation deleted (no suspend precondition)

| Field | Content |
|-------|---------|
| ID | S03-072 |
| Journey setup | S03-037 enrolled `I0`; S03-045 resumed it to `active`; S03-058/S03-067/S03-069 exercised its keys. `I0` is `active` at this point — it was never re-suspended. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/delete`, operator bearer, `Content-Type: application/json`, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. The code imposes no "must be suspended first" precondition — the only rejected prior state is `deleted`. |
| Side effects | `installation.status` for `I0` becomes `deleted`; `control_audit` gains `action = delete`, `target = I0`, `operator_id = platform-operator`, pointers NULL. `installation_key`, `entitlement`, journal, and R2 rows are NOT removed — delete is a status flag, not data removal. |
| Code reference | ai-platform/src/control/lifecycle.ts:L566-L616 — handleDelete |

## Scenario S03-073 — Delete of an already-deleted installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-073 |
| Journey setup | S03-072 deleted `I0`. |
| Action | Repeat the S03-072 request. |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L595-L597 — delete status guard |

## Scenario S03-074 — Rotate on a deleted installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-074 |
| Journey setup | S03-072 deleted `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/rotate`, operator bearer, body `{"kid":"7d8e9f0a-1b2c-4d3e-8f4a-5b6c7d8e9f0a","public_key":"Aq7RtY2mZxCvB8nM3kLpQwErTyUiOpAsDfGhJkLzXcV","algorithm":"EdDSA"}`. |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}`. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L335-L337 — rotate deleted-status guard |

## Scenario S03-075 — Revoke-key on a deleted installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-075 |
| Journey setup | S03-072 deleted `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/revoke-key`, operator bearer, body `{"kid":"d5e6f7a8-9b0c-4d1e-8f2a-3b4c5d6e7f8a"}` (`K1`, still active on paper). |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}` — the deleted-status check precedes the key lookup, so even a valid kid is rejected. |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L414-L416 — revoke deleted-status guard |

## Scenario S03-076 — Suspend on a deleted installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-076 |
| Journey setup | S03-072 deleted `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/suspend`, operator bearer, body `{}`. |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}` (`deleted` is in the suspend rejected set alongside `suspended`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L492-L497 — suspend status guard |

## Scenario S03-077 — Resume on a deleted installation returns illegal_lifecycle_transition

| Field | Content |
|-------|---------|
| ID | S03-077 |
| Journey setup | S03-072 deleted `I0`. |
| Action | `POST …/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/resume`, operator bearer, body `{}`. |
| Expected outcome | HTTP 409, body exactly `{"error":"illegal_lifecycle_transition"}` (status `deleted` ≠ `suspended`). |
| Side effects | None. |
| Code reference | ai-platform/src/control/lifecycle.ts:L545-L547 — resume status guard |

## Scenario S03-078 — Delete succeeds directly from suspended

| Field | Content |
|-------|---------|
| ID | S03-078 |
| Journey setup | S03-036 enrolled `I2`; S03-047 suspended it; S03-059/S03-070 managed its keys. `I2` is `suspended`. |
| Action | `POST http://localhost:8787/control/installations/AA10C4D2-5E6F-4A7B-8C9D-0E1F2A3B4C5D/delete`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}` — `suspended → deleted` is a legal transition (only `deleted → delete` is blocked). |
| Side effects | `installation.status` for the `I2` row becomes `deleted`; `control_audit` gains `action = delete` targeting the uppercase `I2` id. Keys and entitlement rows remain. |
| Code reference | ai-platform/src/control/lifecycle.ts:L595-L597 — delete status guard (only deleted blocked) |

## Scenario S03-079 — Purge happy path removes the full installation footprint from D1 and R2

| Field | Content |
|-------|---------|
| ID | S03-079 |
| Journey setup | S03-037 enrolled `I0`; S03-072 deleted it. Build a realistic footprint for `I0`: two completed requests `R1 = 5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b` (Stage 8 request ingress accepted + Stage 9 settlement completed; `payload_pointer = request/5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7a8b/envelope` with the R2 envelope object present) and `R2 = 6f7a8b9c-0d1e-4f2a-9b3c-4d5e6f7a8b9c` (payload already diagnostic-purged by the Stage 13 retention cron, so `payload_pointer = NULL` but the derived R2 object `request/6f7a8b9c-…/envelope` still exists); one `ai_attempt` per request (Stage 10 provider invocation); two `usage_event` rows (Stage 11 ledger); one `usage_rollup` row with `dimensions = {"installation_id":"3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d","period":"2026-09"}` (Stage 12 rollup cron); one `platform_counter` row with `dimension_set = {"installation_id":"3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d","kind":"guard_rejection"}`; one `capability_grant` row with `scope = installation:3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d` (Stage 4 entitle); one `grace_admission_queue` row for `I0` (Stage 8 grace path). [SEED] justification: the rollup/counter/grant/grace rows are by-products of crons and guard stages outside this chapter; they are inserted directly with the exact column shapes the producing stages write, so purge's JSON-dimension deletes can be observed deterministically. |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/purge`, operator bearer, `Content-Type: application/json`, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. |
| Side effects | Must occur: (1) `control_audit` intent row `action = purge_installation`, `target = I0`, `operator_id = platform-operator` written BEFORE any delete; (2) R2 deletes for BOTH derived keys `request/5e6f7a8b-…/envelope` and `request/6f7a8b9c-…/envelope` (derived from request id even when `payload_pointer` is NULL); (3) D1 batch deletes all `ai_attempt` rows for `I0`'s requests, all `usage_event` rows for `I0`, all `ai_request` rows for `I0`, the `usage_rollup` and `platform_counter` rows whose JSON dimensions match `I0`, the `capability_grant` row with scope `installation:I0`, all `installation_key` rows (`K0`, `K1`), the `entitlement` row, and finally the `installation` row itself; (4) a SECOND `control_audit` completion row `action = purge_installation` after the batch — exactly two purge audit rows total. Must NOT occur: the `grace_admission_queue` row for `I0` survives (purge never touches that table); pre-existing `control_audit` history rows for `I0` (`enroll`, `suspend`, `resume`, `rotate`, `revoke-key`, `delete`) survive; other installations' rows (`I2`) are untouched. |
| Code reference | ai-platform/src/control/support-purge.ts:L57-L94 — handleInstallationPurge; ai-platform/src/retention/index.ts:L287-L356 — purgeByInstallationId; ai-platform/src/retention/index.ts:L118-L131 — writePurgeAudit; ai-platform/src/control/audit.ts:L3-L16 — writeAudit |

## Scenario S03-080 — Purge succeeds on an active installation (no status or delete precondition)

| Field | Content |
|-------|---------|
| ID | S03-080 |
| Journey setup | Enroll `I3` exactly as in S03-037 (`POST /control/installations/bb20d5e3-6f7a-4b8c-9d0e-1f2a3b4c5d6e/enroll` with `org_id = ORG3`, `kid = KI3`, `public_key = XI3`, `plan = enterprise`, `display_name = Hasty Clinic`, `region = eu-central`). Do NOT suspend or delete it. |
| Action | `POST http://localhost:8787/control/installations/bb20d5e3-6f7a-4b8c-9d0e-1f2a3b4c5d6e/purge`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. `handleInstallationPurge` performs no installation lookup and no status check — purge is the operator's recovery tool and deletes whatever exists for the id. |
| Side effects | `installation`, `installation_key`, and `entitlement` rows for `I3` are gone; two `control_audit` rows `action = purge_installation`, `target = I3` exist (intent + completion). The pre-existing `enroll` audit row for `I3` survives. |
| Code reference | ai-platform/src/control/support-purge.ts:L57-L94 — handleInstallationPurge (no status gate); ai-platform/src/retention/index.ts:L287-L356 — purgeByInstallationId |

## Scenario S03-081 — Purge of a never-enrolled installation id returns 200 with audit-only writes

| Field | Content |
|-------|---------|
| ID | S03-081 |
| Journey setup | None; `IUNKNOWN` has no rows anywhere. |
| Action | `POST http://localhost:8787/control/installations/00000000-0000-4000-8000-000000000099/purge`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. There is no `installation_not_found` path in purge — an unknown id is not an error. |
| Side effects | Zero rows deleted from any data table; zero R2 deletes; exactly two `control_audit` rows `action = purge_installation`, `target = 00000000-0000-4000-8000-000000000099`, `operator_id = platform-operator` are inserted. |
| Code reference | ai-platform/src/control/support-purge.ts:L57-L94 — handleInstallationPurge |

## Scenario S03-082 — Purge accepts a non-UUID path id without validation

| Field | Content |
|-------|---------|
| ID | S03-082 |
| Journey setup | None. |
| Action | `POST http://localhost:8787/control/installations/not-a-uuid/purge`, operator bearer, body `{}`. |
| Expected outcome | HTTP 200, body exactly `{}`. Unlike the lifecycle handlers, purge never calls `isCanonicalUuid` on the path id — any slash-free segment is accepted and simply matches no rows. |
| Side effects | Zero data-row deletes; two `control_audit` rows `action = purge_installation`, `target = not-a-uuid`. |
| Code reference | ai-platform/src/control/support-purge.ts:L70-L76 — purge path match (regex only, no UUID check) |

## Scenario S03-083 — Purge without an R2 binding returns missing_r2_binding before any write

| Field | Content |
|-------|---------|
| ID | S03-083 |
| Journey setup | S03-037-style enroll exists (any installation). Test invokes `dispatchControlRequest` (or `handleInstallationPurge`) with `bindings = { DB }` — no `R2` — which the worker env cannot express but the dispatch seam can (see Non-automatable notes). |
| Action | `POST http://localhost:8787/control/installations/3f6b2a1c-9d4e-4f7a-8b1c-2e5d6a7b8c9d/purge`, operator bearer, body `{}`, against a binding set lacking `R2`. |
| Expected outcome | HTTP 500, body exactly `{"error":"missing_r2_binding"}`. The check runs after auth but before the intent audit write. |
| Side effects | None — critically, NO `purge_installation` intent audit row is written and no deletes occur. |
| Code reference | ai-platform/src/control/support-purge.ts:L67-L69 — R2 binding guard |

---

## Doc-drift observations

1. **`400 invalid_route` is listed but unreachable via HTTP.** The stage-3 doc failure tables for rotate (§7), revoke-key (§7.1), suspend (§7.2), resume (§7.3), delete (§7.4), and purge (§7.5) all list `400 invalid_route` for "malformed path". In code, `CONTROL_ACTION_PATTERN` (`control/index.ts`) pre-filters requests to exactly the shape each handler's own path regex requires (`parseInstallationId` in `lifecycle.ts`, the purge regex in `support-purge.ts`), so once a request reaches a handler the "no match" branch can never fire. The only path-shape 400 actually reachable over HTTP is `invalid_payload` for a non-UUID path id on lifecycle routes (S03-033) — and purge does not even validate that (S03-082). See Non-automatable notes for the direct-invocation seam.
2. **Purge `500 storage_error` is documented but not produced by code.** Doc §7.5 lists `500 storage_error` for "D1/R2 failure during purge". `handleInstallationPurge`/`purgeByInstallationId` contain no error mapping: a D1 or R2 failure throws, and the worker has no try/catch around control dispatch, so the runtime returns a non-JSON 500 — never the `{"error":"storage_error"}` body. `storage_error` is only returned by `runControlBatch` in `lifecycle.ts` (enroll/rotate/revoke-key/suspend/resume/delete).
3. **Suspend/resume/delete "request body `{}`" is a convention, not a requirement.** Doc §§7.2–7.4 show `{}` bodies; the handlers never read the body at all (S03-047). Any content type, malformed JSON, or empty body succeeds identically.
4. **Rotate and revoke-key are permitted on suspended installations — undocumented.** The code blocks only `status = deleted` in `handleRotate`/`handleRevokeKey` (S03-059, S03-070). The stage-3 doc does not state whether key management works while suspended; the suspend section only describes the `/v1/*` guard effect.
5. **Delete has no suspend precondition — doc is silent, code is permissive.** `handleDelete` allows `active → deleted` directly (S03-072) and `suspended → deleted` (S03-078). The doc's purge section says "Use after `delete`", but nothing in code enforces delete-before-purge either (S03-080).
6. **"Canonical UUID" is case-insensitive in code.** `CANONICAL_UUID_RE` uses the `/i` flag, so uppercase hex UUIDs pass validation and are stored verbatim (S03-036). Docs imply lowercase canonical form.
7. **Purge audit cardinality.** Doc §8.3.13 expects "at least one" `purge_installation` audit row; code writes exactly two per purge call (intent row in `handleInstallationPurge` via `writeAudit`, completion row in `purgeByInstallationId` via `writePurgeAudit`) — including for unknown or malformed ids (S03-081, S03-082). Doc §7.5's step list does describe both writes; only the probe expectation is loose.
8. **Purge preserves `control_audit` history and `grace_admission_queue`.** The doc mentions the grace queue survival but does not call out that the installation's prior audit history (`enroll`, `rotate`, etc.) survives purge — only data tables are deleted (S03-079 side effects).
9. **No drift on enroll semantics.** Enroll dedup on `installation_id OR org_id` (S03-038/S03-039), `duplicate_kid` via batch UNIQUE (S03-040), the pending/zero-quota entitlement, `valid_until = +365d`, and the `{platform_base_url}`-only success body all match the doc exactly.

## Non-automatable notes

1. **`500 storage_error` from `runControlBatch` (all six lifecycle handlers).** With real D1 under `@cloudflare/vitest-pool-workers`, a non-constraint batch failure cannot be induced without sabotaging the database (the UNIQUE-constraint paths are already covered by S03-040 and S03-057). Proposed seam: call the handler directly with a stub `D1Database` whose `batch()` rejects with a non-constraint `Error("disk I/O error")`; assert HTTP 500 `{"error":"storage_error"}`.
2. **`requireValidPublicKey` import-failure branch (enroll S03-037 path, rotate).** In the Workers runtime, `crypto.subtle.importKey("raw", <any 32 bytes>, "Ed25519")` succeeds for every length-valid input, so the `catch → 400 invalid_payload` branch after the length check is not reachable with real crypto. Proposed seam: stub `crypto.subtle.importKey` to throw for one test.
3. **`400 invalid_route` from `requireValidInstallationId` and from `handleInstallationPurge`'s own path match.** Unreachable through the worker's HTTP surface because `CONTROL_ACTION_PATTERN` pre-filters to the identical shape (see Doc-drift #1). Proposed seam: invoke `handleEnroll`/`handleInstallationPurge` directly with a crafted `Request` whose URL bypasses dispatch, asserting `{"error":"invalid_route"}`.
4. **Purge mid-sequence failure semantics (partial purge).** A throwing R2 `delete` or D1 statement inside `purgeByInstallationId` propagates as an unhandled exception (non-JSON 500) after the intent audit row was written — the intent-row-first design exists precisely for this case. Real bindings cannot be forced to fail selectively. Proposed seam: stub `R2Bucket.delete` to throw on the first object; assert the intent `purge_installation` audit row exists, the completion row does not, and the response is a runtime 500 without the JSON error envelope.
5. **S03-083 binding shape.** The production worker always passes `R2` from env (`worker.ts`); a missing-R2 configuration is only expressible by calling `dispatchControlRequest`/`handleInstallationPurge` directly with `{ DB }` bindings. This is automatable in vitest but not through `SELF.fetch` against the standard test wrangler config.
6. **Timing-safety of the bearer compare.** `timingSafeEqualString` is a side-channel property; it is not behaviorally observable over HTTP in the test pool and is noted here for completeness only — the observable contract (exact 401 body for every non-matching credential) is fully covered by S03-001…S03-016.
