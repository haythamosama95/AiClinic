# Contract: GET /v1/coverage

**Unit**: P3.9 · **Requirements**: FR-008

Later units bind to this file for the administrator coverage response. `getCoverage` is unchanged.

## 1. Request

`GET /v1/coverage`

The clinic header check is the existing `requireAipContractVersion` (`CHANNEL_VERSIONS.platformClinic`). The response echoes `Aip-Contract-Version` with `withAipContractVersion`.

The bearer token is the existing AI verifier (`aud` `ai-platform`). `role` must be `administrator`. Any other role, including `staff`, is HTTP 403 and does not call the DO.

## 2. Response

The handler calls DO kind `read_coverage` and no other kind. It does not write the DO. `subscription_ref` is `subscriptionRef(org_id)` from `vendor-contracts`: `AIC-` plus the leading 8 Crockford base-32 characters of SHA-256(`"sub-ref:"` ‖ `org_id`), computed with no lookup.

```json
{
  "subscription_ref": "AIC-XXXXXXXX",
  "snapshot": {},
  "queued_terms": [],
  "recent_terms": []
}
```

`snapshot` is the object `read_coverage` already returns. It is not rebuilt here.

`queued_terms` is that call's list: unheld terms in state `queued`, ascending `position`. Each object is `{plan_id, plan_version, plan_display_name, duration_unit, duration_count}`. A queued term has no dates.

`recent_terms` is that call's list: at most the last 12 terms whose state is `active`, `grace`, or `ended`, highest `position` first. Each object is `{term_id, state, plan_display_name, starts_at, ends_at, grace_ends_at, allowance, used}`. `used` is the `hot` row's `used` when the term is `hot.active_term_id`, and `used_final` otherwise.

No prices, payment references, or provider ids are added.
