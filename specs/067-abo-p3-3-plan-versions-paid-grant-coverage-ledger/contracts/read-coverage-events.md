# Contract: readCoverageEvents

**Unit**: P3.3 · **Requirements**: FR-016

Later units bind to this file for `readCoverageEvents`. Each event object stays `specs/064-abo-p2-2-package-contracts-message-types-webauthn/contracts/feed-event.md`. `validateFeedEvent` is unchanged.

## 1. Call

Class M. Argument `{contract_version, after, limit}`. `contract_version` is checked first. The method reads `coverage_event` only.

## 2. Page

A missing `limit`, or a `limit` outside 1 through 200, is `rejected` with `code` `limit_invalid` and `detail` empty. No events are returned. A `limit` of 200 is accepted.

Otherwise `result` is `ok`, `code` is `""`, and `receipt` is absent. `detail` is the JSON text of `{after, events, next_after, has_more}`.

`after` echoes the caller's cursor. `events` are unsigned objects `{event_id, feed_seq, org_id, installation_id, binding_epoch, clinic_seq, kind, at, snapshot}` with `feed_seq` greater than `after`, in ascending `feed_seq`, at most `limit`. `snapshot` is the stored object. `next_after` is the last returned `feed_seq`, or `after` when the page is empty. `has_more` is true when a further event exists.
