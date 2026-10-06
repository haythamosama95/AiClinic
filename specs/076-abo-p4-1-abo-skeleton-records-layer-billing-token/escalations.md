# P4.1 escalations

Assumptions chosen by the resolver. Each one is written into the design docs named below.

## 1. Unsupported-version body, cross-host rejection, and the ledger object key

**Question:** Three contract values are unnamed in the cited spans. (1) On HTTP 400 `contract_version_unsupported`, 04 §2.3 says the body is `{code, message, contract_version}` and that it lists the accepted versions. It does not say which field holds that list, or what `contract_version` is when the header is missing or outside N and N−1. (2) 02 §1.4 says the ABO rejects `/ops/*` on the billing host and `/v1/*` on the ops host, and E2E-P4.1-06 only says “rejected”. Status and body are unnamed. (3) 03 §2.1 says the minute exporter writes one NDJSON object per fact under the R2 prefix `ledger/` in `fact_seq` order. The object key is unnamed.

**Assumption:** (1) The accepted-version list is `accepted_versions`, `[N−1, N]` with N−1 first. `contract_version` is N both when `Abo-Contract-Version` is missing and when it is outside N and N−1, and the response header `Abo-Contract-Version` is that same N. The body is `{code, message, contract_version, accepted_versions}`. (2) Both cross-host crossings answer HTTP 404 with an empty body, before the contract-version check and before authentication. That body is not an 04 §2.3 error. (3) Each fact is the object `ledger/<fact_seq>.ndjson`, where `<fact_seq>` is that fact's `fact_seq` in decimal with no padding, and the object is one JSON line.

**Why:** 04 §7.2 and the 04 §4.2 row already name `accepted_versions` for this refusal, in the order `acceptedVersions` returns. NFR-09 says the response states the version it answers in, and §7.2 answers in the request's version only when that version was accepted, so a missing or rejected header is answered as N. A 404 with an empty body is the status already used when a route is not served, and it leaves `not_found` meaning an unknown or other-tenant id. The host check comes first so this 404 stays distinct from the version refusal. `grant-ledger/<grant_id>.ndjson` is already one object per record, one JSON line, so the fact copy uses `fact_seq` the same way. Replay already walks `fact_seq` order, so the key needs no padding.

**Amended:** `docs/architecture/ai-billing-orchestration/04-abo-contracts.md` (§2.3); `docs/architecture/ai-billing-orchestration/02-abo-architecture-and-threat-model.md` (§1.4); `docs/architecture/ai-billing-orchestration/03-abo-data-model-and-lifecycle.md` (§2.1).

## 2. How the daily cron observes a missing R2 bucket lock

**Question:** How does the daily cron observe that the R2 bucket lock is missing? FR-009 and 05 §2 AL-16 require that check on the daily cron, and the cited spans do not name a binding, API, header, or config that reports the lock.

**Assumption:** The daily cron reads Cloudflare's Get Bucket Lock Rules: `GET https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}/lock`, with `Authorization: Bearer` set to the secret `R2_LOCK_READ_TOKEN`. `account_id` is the var `CLOUDFLARE_ACCOUNT_ID`. `bucket_name` is the var `R2_BUCKET_NAME`. That token cannot set lock rules. The lock is present when the body has `success` true and `result.rules` includes an enabled rule whose `condition.type` is `Indefinite` and whose `prefix` is `ledger/` or empty. The lock is missing, and the check raises AL-16, only when that call returns `success` true and no such rule is present. Any other response leaves the lock condition unraised. H-ABO answers this GET. Unless a scenario supplies another body, the answer is `success` true and one enabled Indefinite rule with prefix `ledger/`.

**Why:** The Workers R2 binding does not return lock rules. Cloudflare reports them from this GET. RC-03's limit is an account token that can remove the lock, so the cron's token cannot set rules, and a failed or non-success response is not treated as a missing lock. An enabled Indefinite rule on `ledger/`, or on an empty prefix (the whole bucket), is the locked `ledger/` copy in 03 §2.1 and the "until a retention policy is set" hold in RC-03. The harness default keeps the export-stall case from also being a missing lock.

**Amended:** `specs/076-abo-p4-1-abo-skeleton-records-layer-billing-token/spec.md` (FR-009, §2.6 edge case).
