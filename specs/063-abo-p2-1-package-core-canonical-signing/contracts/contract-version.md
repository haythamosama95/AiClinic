# Contract: Channel constants and the version refusal

**Unit**: P2.1 · **Requirements**: FR-008, FR-009, FR-011

Later units bind to this file. P3.1 consumes `negotiate` for `VendorEntrypoint`. P3.9 consumes `CHANNEL_VERSIONS.platformFeed`. P5.1 and P6.1 consume the constants when they copy them into SQL and Dart. The heartbeat ping and `send_email` alerts have no constant (04 §7.1). Token `ver` stays `"2"` and is not a channel constant (04 §7.1).

## 1. Module

`packages/vendor-contracts/src/version.ts`, re-exported from `packages/vendor-contracts/src/index.ts`.

```ts
export const CHANNEL_VERSIONS: {
  aboClinic: 1
  aboConsole: 1
  backendRpc: 1
  platformClinic: 1
  platformFeed: 1
  vendorEntrypoint: 1
  platformDo: 1
  paymobReturn: 1
  paymobAdapter: 1
}

export function acceptedVersions(current: number): number[]

export function negotiate(
  current: number,
  requested: number | null,
):
  | { ok: true; version: number }
  | {
      ok: false
      code: "contract_version_unsupported"
      accepted_versions: number[]
    }
```

Each constant is the integer 1 (04 §7.1).

| Constant | Channel | Where the version travels |
| --- | --- | --- |
| `aboClinic` | Desktop → ABO clinic API `/v1/*` | `Abo-Contract-Version` |
| `aboConsole` | ABO console → ABO `/ops/*` | `Abo-Contract-Version` |
| `backendRpc` | Desktop → backend RPCs | `p_contract_version` |
| `platformClinic` | Desktop → platform clinic routes | `Aip-Contract-Version` |
| `platformFeed` | Backend feed puller → platform feed | `Aip-Contract-Version` |
| `vendorEntrypoint` | ABO → `VendorEntrypoint` | `contract_version` |
| `platformDo` | Platform Worker → per-clinic DO RPC | `contract_version` |
| `paymobReturn` | Browser return → ABO `/return/{provider}` | `v` |
| `paymobAdapter` | ABO ↔ Paymob API and `/notify/{provider}` | `adapter_version` |

## 2. Negotiation

`acceptedVersions(current)` is `[current - 1, current]` in that order.

`negotiate` accepts `requested` when it equals `current` or `current - 1`. The success `version` is `requested`. The caller answers in that version (04 §7.2).

`requested === null` is a missing version. Any other integer is unsupported. Both return `ok: false`, `code: "contract_version_unsupported"`, and `accepted_versions: acceptedVersions(current)`.

At launch `current` is 1, so the accepted versions are `0` and `1`. P7.3 overrides the constants to exercise other N (rule V5). This unit's clinic tests use `CHANNEL_VERSIONS.platformClinic`.

## 3. Platform clinic wire

`ai-platform/src/vendor/contract-version.ts` imports `CHANNEL_VERSIONS`, `negotiate`, and nothing else from the package. It does not reimplement the rule.

The request header name is `Aip-Contract-Version`. The value is the exact base-10 digits of the integer (`"1"`, `"0"`). A missing header is `requested === null`. Any other header value is unsupported.

```ts
export function requireAipContractVersion(
  request: Request,
):
  | { ok: true; version: number }
  | { ok: false; response: Response }

export function withAipContractVersion(
  response: Response,
  version: number,
): Response
```

On failure, `response` is HTTP 400 with `Content-Type: application/json` and this body:

```json
{ "code": "contract_version_unsupported", "accepted_versions": [0, 1] }
```

`accepted_versions` is `acceptedVersions(CHANNEL_VERSIONS.platformClinic)`. The failure response does not echo `Aip-Contract-Version`.

On success, `withAipContractVersion` returns a `Response` with the same status and body and with `Aip-Contract-Version` set to the base-10 digits of `version`. `worker.ts` applies that to every response of a gated clinic route, including the SSE `Response` from `handleAdapterRequest`, before `fetch` returns.

`worker.ts` calls `requireAipContractVersion` before token verification on `GET /v1/capabilities`, `POST /v1/requests`, `GET /v1/requests/{ref}` when the reference is non-empty, and `GET /v1/coverage`. The check is also before any write. `POST /v1/requests` without the header writes no `ai_request` row.

This unit wires that clinic header only. It does not wire the feed, the entrypoint, the DO, the ABO, the backend RPC, or Paymob.
