# Contract: GET /v1/feed/coverage

**Unit**: P3.9 · **Requirements**: FR-005, FR-006

Later units bind to this file for the HTTP feed. `readCoverageEvents` is unchanged. The backend pull cycle is out of scope.

## 1. Request

`GET /v1/feed/coverage?after=<feed_seq>&limit=<n>`

`Aip-Contract-Version` is checked first, before the `Authorization` header is read and before any D1 write. The channel is `CHANNEL_VERSIONS.platformFeed` (1 at launch) through the existing `negotiate`. A missing header or a version `negotiate` rejects is HTTP 400:

```json
{ "code": "contract_version_unsupported", "accepted_versions": [0, 1] }
```

`accepted_versions` is the array `negotiate` returns. `feed_consumer` is not written.

After the version check, the bearer token must pass `validateTokenClaims` with audience `ai-platform-feed`. The claims are `aud` `ai-platform-feed`, `sub` `backend-feed`, `org` absent, lifetime ≤ 120 seconds. Any other token, including an AI token (`aud` `ai-platform`), is HTTP 401 and does not write `feed_consumer`. A feed token on `POST /v1/requests` stays HTTP 401 through the existing AI verifier.

`after` missing is 0. `limit` missing or outside 1 through 200 is treated as 200. This route does not use the `limit_invalid` code.

## 2. Page

Header `Aip-Contract-Version` is the negotiated version. The body is not signed.

```json
{
  "contract_version": 1,
  "after": 0,
  "events": [],
  "next_after": 0,
  "has_more": false
}
```

`contract_version` is the negotiated feed version. `after` echoes the cursor used. `events` are rows of `coverage_event` with `feed_seq` greater than `after`, ascending `feed_seq`, at most `limit`. Each event is `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}`. `snapshot` is the stored JSON object. `kind` is one of `grant_applied`, `grant_voided`, `term_activated`, `term_ended`, `term_held`, `term_released`, `grace_started`, `band_crossed`, `suspension_changed`, `transfer`.

`next_after` is the last returned `feed_seq`, or `after` when `events` is empty. `has_more` is true when a further row exists with `feed_seq` greater than that `next_after`.

## 3. Consumer row

On this success path only, upsert `feed_consumer` where `consumer` is `backend-feed`. `last_pull_at` is `clockNowIso`. `last_cursor` is `next_after`.
