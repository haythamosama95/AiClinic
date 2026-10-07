# Data Model: Console passkey ceremony and ABO-side HP actions

**Branch**: `ai/082-abo-p4-7-console-passkey-ceremony-abo-side-hp` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

Entities this unit writes. Existing tables keep their current columns. This unit adds `payment_release` and the ABO D1 `assertion_used` store.

## 1. `offer_event`

Append-only record of publish, retire, and reinstate for an offer version (03 §2.2). An offer is sellable when its latest event is `published`. The sellable version is the latest published one. Past prices remain on `offer_version`.

| Field | Rule |
| --- | --- |
| `offer_id` | Existing offer |
| `kind` | `published`, `retired`, or `reinstated` |
| `version` | Offer version the event names |
| `actor` | Access email of the operator |
| `at` | ABO clock time of the action |
| `contract_version` | Existing NOT NULL column on the table |

Publishing a new version inserts an `offer_version` row. That row's existing `assertion_sha256` column stores the challenge hash. Retire and reinstate insert `offer_event` only. They do not update `offer_version`.

## 2. Terms text

Terms versions published, retired, or reinstated by the same HP catalogue action as offer versions (FR-007). The text is stored in R2. The existing `terms_version` row holds `terms_version`, `locale`, `text_r2_key`, `text_sha256`, `published_by`, and `contract_version`. `published_by` is the Access email. `text_sha256` is the hash of the stored text. The R2 object key is `text_r2_key`.

`assertion_sha256` for the action is recorded on `operator_action` and, when a new offer version is inserted, on that `offer_version` row. `terms_version` has no `assertion_sha256` column.

## 3. `payment_release`

Append-only HP release of a withheld payment (03 §2.6). Created by this unit.

| Field | Rule |
| --- | --- |
| `payment_id` | Primary key. The withheld payment |
| `operator_action_id` | The `operator_action` row for the release |
| `at` | ABO clock time of the release |

A fully reversed payment gets no row. Update and delete abort, matching the other append-only ABO tables.

## 4. `billing_contact` erasure

Existing table. The erasure action blanks `name`, `email`, and `phone` on every version of one tenant, sets `erased_at`, and sets `erased_by` to the Access email (03 §2.3). `contact_sha256` stays. Raw provider bodies for that tenant (`notification.body_r2_key` and `inquiry_result.raw_r2_key`) are deleted from R2. The D1 hash columns and `ledger/` export objects stay.

## 5. `operator_action`

Existing ABO record. A refused HP action stores the result here (E2E-P4.7-03). An accepted HP action stores the same row with `assertion_sha256` set to the challenge hash, then calls `recordOperatorAction`. The platform `control_audit` row from that call keeps `assertion_sha256` null (P4.6 freeze).

A missing, expired, or wrong-`aud` Access JWT writes no `operator_action` row.

## 6. `assertion_used`

ABO D1 store named in 04 §1.5. On acceptance, and before the HP write, the ABO inserts the challenge hash. A hash already stored is `rejected` with `assertion_used` before the HP write.

The challenge hash is the hex SHA-256 of the canonical operation object. That is the hash whose base64url form is the WebAuthn challenge.

| Field | Rule |
| --- | --- |
| `challenge_sha256` | Primary key. The challenge hash |

Update and delete abort. A repeat does not insert a second row and does not perform the HP write.
