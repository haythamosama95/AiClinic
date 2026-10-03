# Contract: Tenant binding

**Unit**: P3.2 · **Requirements**: FR-007, FR-008, FR-009, FR-014

Later units bind to this file for the first-seen org binding. `held_for_transfer` and epoch increments above 1 are not written here.

## 1. First valid token

After AI-token verification succeeds, the verifier loads `tenant_binding` for `org` with `status` `active`.

A hit sets `Principal.installationId` to that row's `installation_id`. No second binding is inserted.

A miss counts `tenant_binding` rows with `epoch` 1 whose `created_at` is inside the last 24 hours of the platform clock. The count is a direct D1 query, not a cache read.

- When the count is 50 or more, the attempt inserts nothing. The clinic route returns 401 `unauthenticated`. The platform raises AL-20.
- When the count is under 50, one D1 batch inserts the `installation` row and the binding. The binding is `status` `active`, `epoch` 1, `retired_at` null, `reason` null, and `created_at` the insert time. The installation values are in `data-model.md`. A unique conflict on the live-org index re-reads the active binding and does not insert a second one.

A second valid token for that org returns the same `installation_id`.

## 2. AL-20

`platform_alert.alert_key` is `AL-20`. `code` is `AL-20`. Email `subject` is `AL-20`. Email `text` is `{"code":"AL-20"}`. No other key. The credential AL-13 body is unchanged.

The first raise sends that body and sets `next_send_at` to 24 hours after the platform clock. Repeat is daily. The existing `*/5` retry also handles this key: when `next_send_at` is due, it counts epoch-1 rows in the last 24 hours again. Above 50, it sends the same body and moves `next_send_at` forward 24 hours. At 50 or below, it sets `resolved_at` and does not send. A thrown send leaves `send_state` `unsent`, which the existing unsent retry already sends.

## 3. Rotation

`retireIssuerKey` and `revokeIssuerKey` do not update `tenant_binding`.
