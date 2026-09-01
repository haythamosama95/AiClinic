# AI Platform Data Journey — Complete R2 Object Reference

## Table of Contents

1. [Routing policy document](#1-routing-policy-document)
2. [Request diagnostic envelope](#2-request-diagnostic-envelope)
3. [Behavioral verification](#3-behavioral-verification)
   - [3.1 Setup](#31-setup)
   - [3.2 Coverage](#32-coverage)
   - [3.3 Ordered probes](#33-ordered-probes)
     - [3.3.1 Reset to a known R2 state](#331-reset-to-a-known-r2-state)
     - [3.3.2 Who cannot read R2](#332-who-cannot-read-r2)
     - [3.3.3 Publish failure does not write R2](#333-publish-failure-does-not-write-r2)
     - [3.3.4 Publish a full routing policy document](#334-publish-a-full-routing-policy-document)
     - [3.3.5 Key naming, Content-Type, and D1 pointer](#335-key-naming-content-type-and-d1-pointer)
     - [3.3.6 Duplicate publish does not overwrite](#336-duplicate-publish-does-not-overwrite)
     - [3.3.7 Canary, promote, and rollback leave R2 unchanged](#337-canary-promote-and-rollback-leave-r2-unchanged)
     - [3.3.8 What is not stored in R2](#338-what-is-not-stored-in-r2)
     - [3.3.9 Config-cache loads the published document](#339-config-cache-loads-the-published-document)
     - [3.3.10 Complete a request, envelope key](#3310-complete-a-request-envelope-key)
     - [3.3.11 Envelope every field](#3311-envelope-every-field)
     - [3.3.12 Who can read the envelope](#3312-who-can-read-the-envelope)
     - [3.3.13 Failed terminal, one envelope](#3313-failed-terminal-one-envelope)
     - [3.3.14 Cancelled terminal, one envelope](#3314-cancelled-terminal-one-envelope)
     - [3.3.15 Retention purge deletes the envelope](#3315-retention-purge-deletes-the-envelope)
     - [3.3.16 Installation purge deletes envelopes](#3316-installation-purge-deletes-envelopes)

---

## 1. Routing policy document


| Property     | Value                                               |
| ------------ | --------------------------------------------------- |
| Key pattern  | `control/routing-policy/{policy_id}/{version}.json` |
| Content-Type | `application/json`                                  |
| D1 link      | `routing_policy.content_pointer`                    |
| Written by   | `control/routing-policy.ts` publish                 |
| Read by      | `config-cache` → router                             |


Full field list: [07-stage-5-routing-policy.md §4](07-stage-5-routing-policy.md#4-r2-document-every-field).

## 2. Request diagnostic envelope


| Property    | Value                                          |
| ----------- | ---------------------------------------------- |
| Key pattern | `request/{request_id}/envelope`                |
| D1 link     | `ai_request.payload_pointer`                   |
| Written by  | `journal/index.ts` on every terminal settlement (`Completed`, `Failed`, `Cancelled`) — one object per request |
| Read by     | `getRequest`, support lookup                   |
| Deleted by  | Retention purge (90d diagnostic horizon)       |


Full field list: [13-stage-11-terminal-settlement.md §7](13-stage-11-terminal-settlement.md#7-r2-envelope-every-field).

## 3. Behavioral verification

Live probes against a local Worker and the same Miniflare R2 store the Worker writes. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§3.3](#33-ordered-probes) top to bottom** on throwaway local persist. If every probe matches, the two R2 families in this file are working.

The warehouse has **only** these two object families. Publish writes the playbook; settlement writes one diagnostic envelope per request. There is no public HTTP GET for an R2 key — clients see `result` through `GET /v1/requests/{reference}`; operators see the full envelope through `POST /control/support/lookup` or `wrangler r2 object get`.

### 3.1 Setup

- Local Worker from `ai-platform/` (`npm run dev` → `wrangler dev --env development`) with `OPERATOR_BEARER_TOKEN` in `.dev.vars`. Prefer persist you can wipe (`.wrangler/state`).
- An enrolled, **entitled** installation with an AAT (Stages 3–4 and 6). Save `installation_id` as **I0**, the AAT, and the AAT `org` / `branch` claims (envelope context probes need them on the POST body, not in R2).
- `jq` or `python3` to inspect JSON. Run every `wrangler` command from `ai-platform/` so `--local --env development` hits the same bucket `ai-platform-development` the Worker binds as `R2`.
- If `wrangler r2 object get --local` misses an object the Worker just wrote, add `--persist-to .wrangler/state` (same directory `wrangler dev` uses).
- Restart the Worker after publish / canary / promote so the 30 s config-cache cannot serve a stale miss.
- For [§3.3.15](#3315-retention-purge-deletes-the-envelope), start (or restart) with scheduled testing:

```bash
cd ai-platform
npx wrangler dev --env development --test-scheduled
```

Reuse these exports:

```bash
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export AAT='…'
export INSTALLATION_ID='<I0>'
```

`wrangler r2 object get|delete` takes **one** path `{bucket}/{key}`. Wrangler 4.86 has no `r2 object list`.

### 3.2 Coverage

Every object, key, reader, and field claim in this file maps to a probe. Carry them all out.


| Claim | Probe |
| ----- | ----- |
| Only two R2 families: routing policy + request envelope | [§3.3.1](#331-reset-to-a-known-r2-state), [§3.3.8](#338-what-is-not-stored-in-r2) |
| No public HTTP GET of an R2 key; AAT cannot read the warehouse | [§3.3.2](#332-who-cannot-read-r2), [§3.3.12](#3312-who-can-read-the-envelope) |
| Publish identity mismatch → 400; no R2 object | [§3.3.3](#333-publish-failure-does-not-write-r2) |
| Missing operator bearer cannot publish | [§3.3.2](#332-who-cannot-read-r2), [§3.3.3](#333-publish-failure-does-not-write-r2) |
| Key `control/routing-policy/{policy_id}/{version}.json` (`.json` suffix; version from the URL) | [§3.3.5](#335-key-naming-content-type-and-d1-pointer) |
| Publish writes R2 then D1 `routing_policy.content_pointer` | [§3.3.4](#334-publish-a-full-routing-policy-document), [§3.3.5](#335-key-naming-content-type-and-d1-pointer) |
| Body is JSON (`Content-Type: application/json` at `R2.put`) | [§3.3.5](#335-key-naming-content-type-and-d1-pointer) |
| `schema_version` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `policy_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `policy_version` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `defaults` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `defaults.cost_class` (schema-retained) | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `defaults.max_parallel_attempts` (schema-retained) | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules` (non-empty) | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].rule_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match.capability_ids` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match.installation_ids` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match.cost_classes` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match.tiers` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match.languages` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].match.latency_classes` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].requires` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].requires.structured_output` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].requires.min_context_window` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].requires.languages` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].provider_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].model_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].features` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].features.structured_output` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].features.min_context_window` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].features.languages` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].features.latency_class` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].features.cost_class` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].max_attempts` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].targets[].timeout_ms` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `rules[].max_parallel_attempts` (schema-retained) | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `overrides` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `overrides[].installation_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `overrides[].exclude_providers` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `overrides[].pin_target.provider_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `overrides[].pin_target.model_id` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| `overrides[].force_cost_class` | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| Extra JSON keys stored as-is | [§3.3.4](#334-publish-a-full-routing-policy-document) |
| Duplicate publish → 409 `already_published`; R2 body unchanged | [§3.3.6](#336-duplicate-publish-does-not-overwrite) |
| Canary / promote / rollback write D1 only — not R2 | [§3.3.7](#337-canary-promote-and-rollback-leave-r2-unchanged) |
| Manifests, price table, prompts, kill switches, quota, D1 columns are not R2 objects | [§3.3.8](#338-what-is-not-stored-in-r2) |
| Config-cache loads `content_pointer` → router uses the document | [§3.3.9](#339-config-cache-loads-the-published-document) |
| Key `request/{request_id}/envelope` (no `.json` suffix) | [§3.3.10](#3310-complete-a-request-envelope-key) |
| One envelope per request; `ai_request.payload_pointer` equals that key | [§3.3.10](#3310-complete-a-request-envelope-key) |
| Written on `Completed` | [§3.3.10](#3310-complete-a-request-envelope-key) |
| `context` = filteredContext (permitted keys only) | [§3.3.11](#3311-envelope-every-field) |
| `prompt` = CanonicalRequest (composed artifact **text**, not the ref) | [§3.3.11](#3311-envelope-every-field) |
| `prompt.parts` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.formatDirective` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.samplingConstraints` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.maxOutputTokens` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.stopConditions` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.toolDeclarations` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.stream` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.deadline` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.correlationIds.request_reference` | [§3.3.11](#3311-envelope-every-field) |
| `prompt.correlationIds.trace_id` | [§3.3.11](#3311-envelope-every-field) |
| `attempts[]` = `{ payload, truncated }` (16 KiB cap) | [§3.3.11](#3311-envelope-every-field) |
| `result.finalContent` | [§3.3.11](#3311-envelope-every-field) |
| `result.usage` | [§3.3.11](#3311-envelope-every-field) |
| `result.providerModel` | [§3.3.11](#3311-envelope-every-field) |
| `result.finishReason` | [§3.3.11](#3311-envelope-every-field) |
| `result.providerRequestId` | [§3.3.11](#3311-envelope-every-field) |
| `result.timing` | [§3.3.11](#3311-envelope-every-field) |
| `GET /v1/requests/{ref}` (AAT, Completed) returns `result` only | [§3.3.12](#3312-who-can-read-the-envelope) |
| Support lookup (operator) returns the full envelope | [§3.3.12](#3312-who-can-read-the-envelope) |
| Wrong-installation AAT cannot read another clinic’s envelope | [§3.3.12](#3312-who-can-read-the-envelope) |
| `Failed` still writes **one** envelope; empty chain stores `no_provider_attempt` | [§3.3.13](#3313-failed-terminal-one-envelope) |
| Fail/cancel `result.finishReason` is the taxonomy code | [§3.3.13](#3313-failed-terminal-one-envelope), [§3.3.14](#3314-cancelled-terminal-one-envelope) |
| `Cancelled` still writes **one** envelope | [§3.3.14](#3314-cancelled-terminal-one-envelope) |
| Retention purge deletes the envelope and nulls `payload_pointer` (90d journal horizon) | [§3.3.15](#3315-retention-purge-deletes-the-envelope) |
| Installation purge deletes envelopes | [§3.3.16](#3316-installation-purge-deletes-envelopes) |


### 3.3 Ordered probes

#### 3.3.1 Reset to a known R2 state

**Do:** from `ai-platform/`, delete leftover probe objects if a previous run wrote them:

```bash
npx wrangler r2 object delete \
  ai-platform-development/control/routing-policy/verify-r2/1.json \
  --local --env development -y

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "DELETE FROM routing_policy WHERE policy_id = 'verify-r2'"
```

**Do:** get keys that must not exist yet:

```bash
npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1.json \
  --file /tmp/routing-policy.json --local --env development
```

**Expect:** get fails (object not found). The warehouse does not invent a playbook until publish.

#### 3.3.2 Who cannot read R2

R2 is a Worker binding, not an HTTP file server. Clinic AATs never present a bucket key.

**Do:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  "$GATEWAY/control/routing-policy/verify-r2/1.json"

curl -s -o /dev/null -w '%{http_code}\n' \
  "$GATEWAY/request/does-not-exist/envelope"

curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $AAT" \
  "$GATEWAY/control/routing-policy/verify-r2/1.json"

curl -s -X POST "$GATEWAY/control/routing-policies/verify-r2/versions/1/publish" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_id":"verify-r2","policy_version":1}}'
```

**Expect:** the three GETs are **404** (no object route). Publish without `Authorization: Bearer $OPERATOR_BEARER_TOKEN` is **401**. The clinic token cannot read or write the warehouse.

#### 3.3.3 Publish failure does not write R2

**Do:** operator bearer, URL and document identity disagree:

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/verify-r2/versions/1/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":{"schema_version":1,"policy_id":"standard","policy_version":1,"defaults":{},"rules":[],"overrides":[]}}'
```

Then repeat the `wrangler r2 object get` from [§3.3.1](#331-reset-to-a-known-r2-state).

**Expect:** HTTP 400, `policy_identity_mismatch`. Get still fails. Validation runs **before** `R2.put`.

#### 3.3.4 Publish a full routing policy document

**Do:** publish `verify-r2` version `1` with **every** field from [§1](#1-routing-policy-document) / [07 §4](07-stage-5-routing-policy.md#4-r2-document-every-field), including optional match keys, schema-retained defaults, a catch-all, and a stacked override (so nothing is omitted). Replace `<I0>`:

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/verify-r2/versions/1/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"document\": {
      \"schema_version\": 1,
      \"policy_id\": \"verify-r2\",
      \"policy_version\": 1,
      \"defaults\": {
        \"cost_class\": \"standard\",
        \"max_parallel_attempts\": 1
      },
      \"rules\": [
        {
          \"rule_id\": \"visit-summary-standard\",
          \"match\": {
            \"capability_ids\": [\"clinic.visit_summary\"],
            \"installation_ids\": [\"$INSTALLATION_ID\"],
            \"cost_classes\": [\"standard\", \"premium\"],
            \"tiers\": [\"standard\", \"degraded\"],
            \"languages\": [\"en\"],
            \"latency_classes\": [\"standard\"]
          },
          \"requires\": {
            \"structured_output\": false,
            \"min_context_window\": 32000,
            \"languages\": [\"en\"]
          },
          \"targets\": [
            {
              \"provider_id\": \"fake\",
              \"model_id\": \"fake-v1\",
              \"features\": {
                \"structured_output\": true,
                \"min_context_window\": 128000,
                \"languages\": [\"en\"],
                \"latency_class\": \"standard\",
                \"cost_class\": \"standard\"
              },
              \"max_attempts\": 2,
              \"timeout_ms\": 30000
            }
          ],
          \"max_parallel_attempts\": 1
        },
        {
          \"rule_id\": \"catch-all\",
          \"match\": {},
          \"requires\": {
            \"structured_output\": false,
            \"min_context_window\": 0,
            \"languages\": []
          },
          \"targets\": [
            {
              \"provider_id\": \"fake\",
              \"model_id\": \"fake-v1\",
              \"features\": {
                \"structured_output\": true,
                \"min_context_window\": 128000,
                \"languages\": [\"en\"],
                \"latency_class\": \"standard\",
                \"cost_class\": \"standard\"
              },
              \"max_attempts\": 2,
              \"timeout_ms\": 30000
            }
          ],
          \"max_parallel_attempts\": 1
        }
      ],
      \"overrides\": [
        {
          \"installation_id\": \"$INSTALLATION_ID\",
          \"exclude_providers\": [\"gemini\"],
          \"pin_target\": {
            \"provider_id\": \"fake\",
            \"model_id\": \"fake-v1\"
          },
          \"force_cost_class\": \"economy\"
        }
      ],
      \"ops_note\": \"verify-r2-extra-key\"
    }
  }"
```

**Expect:** HTTP 200. (A `warnings: ["latency_class_mismatch"]` array appears only when a published capability’s `routingPolicyRef` is this policy version and no target `latency_class` matches — `clinic.visit_summary` refs `routing/standard@v1`, so this body should be `{}`.)

**Do:** fetch the object:

```bash
npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1.json \
  --file /tmp/routing-policy.json --local --env development

python3 - <<'PY'
import json
d = json.load(open("/tmp/routing-policy.json"))
assert d["schema_version"] == 1
assert d["policy_id"] == "verify-r2"
assert d["policy_version"] == 1
assert d["defaults"]["cost_class"] == "standard"
assert d["defaults"]["max_parallel_attempts"] == 1
assert d["ops_note"] == "verify-r2-extra-key"
r0, r1 = d["rules"]
assert r0["rule_id"] == "visit-summary-standard"
assert r0["match"]["capability_ids"] == ["clinic.visit_summary"]
assert r0["match"]["installation_ids"]
assert r0["match"]["cost_classes"] == ["standard", "premium"]
assert r0["match"]["tiers"] == ["standard", "degraded"]
assert r0["match"]["languages"] == ["en"]
assert r0["match"]["latency_classes"] == ["standard"]
assert r0["requires"]["structured_output"] is False
assert r0["requires"]["min_context_window"] == 32000
assert r0["requires"]["languages"] == ["en"]
t0 = r0["targets"][0]
assert t0["provider_id"] == "fake"
assert t0["model_id"] == "fake-v1"
assert t0["features"]["structured_output"] is True
assert t0["features"]["min_context_window"] == 128000
assert t0["features"]["languages"] == ["en"]
assert t0["features"]["latency_class"] == "standard"
assert t0["features"]["cost_class"] == "standard"
assert t0["max_attempts"] == 2
assert t0["timeout_ms"] == 30000
assert r0["max_parallel_attempts"] == 1
assert r1["rule_id"] == "catch-all"
assert r1["match"] == {}
ov = d["overrides"][0]
assert ov["exclude_providers"] == ["gemini"]
assert ov["pin_target"]["provider_id"] == "fake"
assert ov["pin_target"]["model_id"] == "fake-v1"
assert ov["force_cost_class"] == "economy"
print("ok")
PY
```

**Expect:** get succeeds. **Every** field round-trips:

- `schema_version` = `1`
- `policy_id` = `"verify-r2"`
- `policy_version` = `1`
- `defaults.cost_class` = `"standard"` (stored; the router ignores it)
- `defaults.max_parallel_attempts` = `1` (stored; ignored)
- `rules[0].rule_id` = `"visit-summary-standard"`
- `rules[0].match.capability_ids` = `["clinic.visit_summary"]`
- `rules[0].match.installation_ids` = `[I0]`
- `rules[0].match.cost_classes` = `["standard", "premium"]`
- `rules[0].match.tiers` = `["standard", "degraded"]`
- `rules[0].match.languages` = `["en"]`
- `rules[0].match.latency_classes` = `["standard"]`
- `rules[0].requires.structured_output` = `false`
- `rules[0].requires.min_context_window` = `32000`
- `rules[0].requires.languages` = `["en"]`
- `rules[0].targets[0].provider_id` = `"fake"`
- `rules[0].targets[0].model_id` = `"fake-v1"`
- `rules[0].targets[0].features.structured_output` = `true`
- `rules[0].targets[0].features.min_context_window` = `128000`
- `rules[0].targets[0].features.languages` = `["en"]`
- `rules[0].targets[0].features.latency_class` = `"standard"`
- `rules[0].targets[0].features.cost_class` = `"standard"`
- `rules[0].targets[0].max_attempts` = `2`
- `rules[0].targets[0].timeout_ms` = `30000`
- `rules[0].max_parallel_attempts` = `1` (stored; ignored)
- `rules[1].rule_id` = `"catch-all"` with `match` `{}`
- `overrides[0].installation_id` = **I0**
- `overrides[0].exclude_providers` = `["gemini"]`
- `overrides[0].pin_target.provider_id` = `"fake"`
- `overrides[0].pin_target.model_id` = `"fake-v1"`
- `overrides[0].force_cost_class` = `"economy"`
- `ops_note` = `"verify-r2-extra-key"` (unknown keys are stored)

Save a checksum for the next probes: `sha256sum /tmp/routing-policy.json`. Call this **H0**.

#### 3.3.5 Key naming, Content-Type, and D1 pointer

**Do:** get the wrong keys:

```bash
npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1 \
  --file /tmp/wrong-key.json --local --env development

npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1.json.json \
  --file /tmp/wrong-key.json --local --env development
```

**Do:**

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT policy_id, version, content_pointer, status FROM routing_policy WHERE policy_id = 'verify-r2'"
```

**Expect:** the wrong keys fail. D1 has one row: `policy_id = verify-r2`, `version = 1` (TEXT, from the URL), `content_pointer = control/routing-policy/verify-r2/1.json`, `status = published`. The pointer **is** the R2 key — not a UUID, not a repo path (`control/routing-policy/platform-default/1.json` is the on-disk fixture name only).

**Expect:** `/tmp/routing-policy.json` is JSON. Publish sets `httpMetadata.contentType = application/json` on `R2.put`. `wrangler r2 object get` writes the **body only** — it has no flag to print httpMetadata, so the header itself is not visible from this CLI.

#### 3.3.6 Duplicate publish does not overwrite

**Do:** publish again with a different body (`ops_note` changed, or `rules` emptied):

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/verify-r2/versions/1/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":{"schema_version":1,"policy_id":"verify-r2","policy_version":1,"defaults":{},"rules":[{"rule_id":"x","match":{},"requires":{"structured_output":false,"min_context_window":0,"languages":[]},"targets":[]}],"overrides":[],"ops_note":"should-not-land"}}'
```

Then get the object again and `sha256sum` it.

**Expect:** HTTP 409, `already_published`. Checksum still **H0**. `ops_note` is still `"verify-r2-extra-key"`. Duplicate publish checks D1 **before** `R2.put`.

#### 3.3.7 Canary, promote, and rollback leave R2 unchanged

**Do:**

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/verify-r2/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"

npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1.json \
  --file /tmp/routing-policy-after-canary.json --local --env development

curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/verify-r2/versions/1/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1.json \
  --file /tmp/routing-policy-after-promote.json --local --env development

curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/verify-r2/versions/1/rollback" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/verify-r2/1.json \
  --file /tmp/routing-policy-after-rollback.json --local --env development

sha256sum /tmp/routing-policy.json \
  /tmp/routing-policy-after-canary.json \
  /tmp/routing-policy-after-promote.json \
  /tmp/routing-policy-after-rollback.json
```

**Expect:** canary / promote / rollback return 200. All four checksums equal **H0**. Those actions UPDATE D1 `status` / `canary_installation_ids` only. They do not put or delete the playbook.

#### 3.3.8 What is not stored in R2

**Do:** get keys for catalog and ledger artifacts that this file does **not** claim:

```bash
npx wrangler r2 object get \
  ai-platform-development/control/pricing/platform-default/1.json \
  --file /tmp/not-r2.json --local --env development

npx wrangler r2 object get \
  ai-platform-development/manifests/published/clinic.visit_summary@1.0.0.json \
  --file /tmp/not-r2.json --local --env development

npx wrangler r2 object get \
  ai-platform-development/prompts/clinic.visit_summary/system.md \
  --file /tmp/not-r2.json --local --env development

npx wrangler r2 object get \
  ai-platform-development/kill_switches/global \
  --file /tmp/not-r2.json --local --env development
```

**Do:** confirm kill switches and money live in D1 / the Quota DO, not the playbook:

```bash
python3 - <<'PY'
import json
d = json.load(open("/tmp/routing-policy.json"))
assert "kill_switches" not in d
assert "usage" not in d
print("ok")
PY

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('kill_switch','usage_event','token_contract')"
```

**Expect:** those four gets fail. The playbook JSON has no kill-switch or usage block. `kill_switch`, `usage_event`, and `token_contract` exist as **D1 tables**. Manifests, prompt files, and `control/pricing/platform-default/1.json` are **bundled in the Worker**. Quota counters are the Durable Object. Wrangler 4.86 has no `r2 object list`, so you cannot dump the whole bucket from this CLI — negative gets plus D1 pointers are the live check.

#### 3.3.9 Config-cache loads the published document

`verify-r2` is not the visit-summary playbook (`routingPolicyRef` is `routing/standard@v1`). To prove the cache reads R2 on the invoke path, publish a new **standard** version whose catch-all targets `fake` (so local invoke does not need provider secrets), then canary it to **I0**.

**Do:** if `standard` version `2` is already published, skip to canary (409 is [§3.3.6](#336-duplicate-publish-does-not-overwrite) again).

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "document": {
      "schema_version": 1,
      "policy_id": "standard",
      "policy_version": 2,
      "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
      "rules": [{
        "rule_id": "catch-all",
        "match": {},
        "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
        "targets": [{
          "provider_id": "fake",
          "model_id": "fake-v1",
          "features": {
            "structured_output": true,
            "min_context_window": 128000,
            "languages": ["en"],
            "latency_class": "standard",
            "cost_class": "standard"
          },
          "max_attempts": 2,
          "timeout_ms": 30000
        }]
      }],
      "overrides": []
    }
  }'

npx wrangler r2 object get \
  ai-platform-development/control/routing-policy/standard/2.json \
  --file /tmp/standard-v2.json --local --env development

curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
```

Restart the Worker ([§3.1](#31-setup)).

**Do:** confirm D1 `content_pointer` matches the key you just got:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT version, content_pointer, status, canary_installation_ids FROM routing_policy WHERE policy_id = 'standard' AND version = '2'"
```

**Expect:** get succeeds; `content_pointer = control/routing-policy/standard/2.json`; `status = canary`. Config-cache loads that pointer from R2 (the router never takes an R2 binding of its own). The next probe’s `providerModel.provider = "fake"` is the live proof the document was read.

#### 3.3.10 Complete a request, envelope key

**Do:** one visit-summary request. Replace org/branch with the AAT claims. Capture `request_reference` from the `accepted` SSE event.

```bash
curl -N -s -X POST "$GATEWAY/v1/requests" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -H "x-idempotency-key: $(python3 -c 'import uuid; print(uuid.uuid4())')" \
  -H "x-capability-version: 1.0.0" \
  -d "{
    \"capability_id\": \"clinic.visit_summary\",
    \"user_intent\": \"Summarize today's visit for the chart.\",
    \"context\": {
      \"org\": \"<AAT org>\",
      \"branch\": \"<AAT branch>\",
      \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\",
      \"drop_me\": \"must-not-reach-envelope\"
    }
  }"
```

Wait for SSE `completed` (FakeAdapter is immediate). Sleep two seconds so `waitUntil` can finish `R2.put`. Then:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, state, payload_pointer FROM ai_request WHERE request_reference = '<REFERENCE>'"
```

Call the `request_id` **R0**. Then:

```bash
npx wrangler r2 object get \
  ai-platform-development/request/<R0>/envelope \
  --file /tmp/envelope.json --local --env development

npx wrangler r2 object get \
  ai-platform-development/request/<R0>/envelope.json \
  --file /tmp/wrong-envelope.json --local --env development

npx wrangler r2 object get \
  ai-platform-development/request/<R0>/attempts \
  --file /tmp/wrong-envelope.json --local --env development
```

**Expect:** `state = Completed`. `payload_pointer = request/<R0>/envelope` — **no** `.json` suffix. Get of that key succeeds. Get of `envelope.json` and `attempts` fail. Settlement writes **one** object, not a pair.

#### 3.3.11 Envelope every field

**Do:** inspect `/tmp/envelope.json`. Top level is exactly `{ context, prompt, attempts, result }` ([§2](#2-request-diagnostic-envelope) / [13 §7](13-stage-11-terminal-settlement.md#7-r2-envelope-every-field)).

```bash
python3 - <<'PY'
import json
e = json.load(open("/tmp/envelope.json"))
assert set(e) == {"context", "prompt", "attempts", "result"}
assert e["context"] == {"visit.chief_complaint@v1": "Patient reports headache for 3 days."}
assert "drop_me" not in e["context"]
assert "org" not in e["context"]
p = e["prompt"]
for k in ("parts", "formatDirective", "samplingConstraints", "maxOutputTokens",
          "stopConditions", "toolDeclarations", "stream", "deadline", "correlationIds"):
    assert k in p
assert any(part["role"] == "system" and part["content"] for part in p["parts"])
assert any(part["role"] == "data" for part in p["parts"])
assert p["parts"][-1]["role"] == "user"
assert "Summarize today's visit" in p["parts"][-1]["content"]
assert p["formatDirective"]["mode"] == "prose"
assert p["formatDirective"]["outputSchemaRef"] is None
assert p["samplingConstraints"]["allowedLanguages"] == ["en"]
assert p["maxOutputTokens"] == 1024
assert p["toolDeclarations"] == []
assert p["stream"] is True
assert p["deadline"] is None
assert p["correlationIds"]["request_reference"]
assert p["correlationIds"]["trace_id"]
a0 = e["attempts"][0]
assert a0["truncated"] is False
assert a0["payload"]["fake"] is True
assert a0["payload"]["outcome"] == "success"
r = e["result"]
assert r["finalContent"]["type"] == "text"
assert r["finalContent"]["text"] == "Fake adapter summary."
assert r["usage"] == {"input": 10, "output": 20, "cached": 0}
assert r["providerModel"] == {"provider": "fake", "model": "fake-v1"}
assert r["finishReason"] == "stop"
assert r["providerRequestId"] == "fake-req-001"
assert r["timing"]["queue_ms"] == 1
assert r["timing"]["provider_ms"] == 5
assert r["timing"]["total_ms"] == 6
print("ok")
PY
```

**Expect:**

- `context` has **only** `visit.chief_complaint@v1`. `org`, `branch`, and `drop_me` are not stored (filteredContext, not the raw POST body).
- `prompt` is a CanonicalRequest — composed artifact **text** lives in `parts[]`. There is no prompt-artifact object in R2; D1 `prompt_artifact_hash` is the content hash of those bytes, not this key.
- `prompt.parts` — system instruction, rules, output-format instruction, a `data` part with the rendered complaint, last part `role = "user"` with the neutralized intent.
- `prompt.formatDirective.mode` = `"prose"`; `outputSchemaRef` = `null`
- `prompt.samplingConstraints.allowedLanguages` = `["en"]`
- `prompt.maxOutputTokens` = `1024`
- `prompt.stopConditions` present (array; may be empty)
- `prompt.toolDeclarations` = `[]`
- `prompt.stream` = `true` (live SSE compose sets `streamFlag`)
- `prompt.deadline` = `null`
- `prompt.correlationIds.request_reference` equals the SSE `accepted` reference
- `prompt.correlationIds.trace_id` equals the AAT `jti` (not `x-trace-id`)
- `attempts` length 1; each entry is `{ payload, truncated }`, not D1 `ai_attempt` columns (`cost` / `provider` live in D1)
- `attempts[0].payload` = `{ "fake": true, "outcome": "success" }`; `truncated` = `false`
- `result.finalContent` = `{ "type": "text", "text": "Fake adapter summary." }`
- `result.usage` = `{ "input": 10, "output": 20, "cached": 0 }`
- `result.providerModel` = `{ "provider": "fake", "model": "fake-v1" }` — this is [§3.3.9](#339-config-cache-loads-the-published-document)
- `result.finishReason` = `"stop"`
- `result.providerRequestId` = `"fake-req-001"`
- `result.timing` = `{ "queue_ms": 1, "provider_ms": 5, "total_ms": 6 }`

The 16 KiB truncation flag (`truncated: true`, payload sliced) is **not** exercised here — FakeAdapter bodies are tiny. See unprobeable notes after [§3.3.16](#3316-installation-purge-deletes-envelopes).

#### 3.3.12 Who can read the envelope

**Do:** clinic lookup with the same AAT (Completed reads R2 `result` only):

```bash
curl -s "$GATEWAY/v1/requests/<REFERENCE>" \
  -H "Authorization: Bearer $AAT"
```

**Expect:** `{ "state": "Completed", "result": { …same CanonicalResult as the envelope… } }`. The HTTP body has **no** `context`, `prompt`, or `attempts`. `getRequest` pulls those off the envelope internally and returns `result`.

**Do:** no bearer; then operator support lookup:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "$GATEWAY/v1/requests/<REFERENCE>"

curl -s -X POST "$GATEWAY/control/support/lookup?reference=<REFERENCE>" \
  -H "Authorization: Bearer $AAT"

curl -s -X POST "$GATEWAY/control/support/lookup?reference=<REFERENCE>" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

**Expect:** GET without AAT → **401**. Support lookup with the clinic AAT → **401** (`requireOperator`). Support lookup with the operator bearer → 200 and `envelope` equal to `/tmp/envelope.json` (all four keys). `wrangler r2 object get` of `request/<R0>/envelope` is the same full document — that CLI is operator-local persist, not a clinic API.

**Do:** if you have a second installation’s AAT, `GET /v1/requests/<REFERENCE>` with that token.

**Expect:** **404** (`getRequest` scopes by `installation_id`). The other clinic cannot read this envelope.

#### 3.3.13 Failed terminal, one envelope

**Do:** publish `standard` version `3` with a catch-all that still targets `fake`, plus an override that **excludes** `fake` for **I0** (empty chain after override). Canary it; restart the Worker; POST a new request (new idempotency key).

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/3/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"document\": {
      \"schema_version\": 1,
      \"policy_id\": \"standard\",
      \"policy_version\": 3,
      \"defaults\": { \"cost_class\": \"standard\", \"max_parallel_attempts\": 1 },
      \"rules\": [{
        \"rule_id\": \"catch-all\",
        \"match\": {},
        \"requires\": { \"structured_output\": false, \"min_context_window\": 0, \"languages\": [] },
        \"targets\": [{
          \"provider_id\": \"fake\",
          \"model_id\": \"fake-v1\",
          \"features\": {
            \"structured_output\": true,
            \"min_context_window\": 128000,
            \"languages\": [\"en\"],
            \"latency_class\": \"standard\",
            \"cost_class\": \"standard\"
          },
          \"max_attempts\": 2,
          \"timeout_ms\": 30000
        }]
      }],
      \"overrides\": [{
        \"installation_id\": \"$INSTALLATION_ID\",
        \"exclude_providers\": [\"fake\"]
      }]
    }
  }"

curl -s -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/3/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
```

After SSE `failed`, look up the new `request_id` (**R1**) and get `request/<R1>/envelope`.

**Expect:** `state = Failed`. `payload_pointer = request/<R1>/envelope`. Still **one** object — not `envelope-failed`, not a second put on **R0**. Envelope keys are still `context`, `prompt`, `attempts`, `result`.

- `attempts[0].payload.reason` = `"no_provider_attempt"`
- `attempts[0].payload.excluded` is a non-empty array (`installation_excluded` for `fake`)
- `attempts[0].truncated` = `false`
- `result.finishReason` = `"provider_unavailable"` (placeholder CanonicalResult; taxonomy code, not `"stop"`)
- `result.finalContent.text` = `""`
- `result.providerModel.provider` = `""`
- `result.providerRequestId` = `""`

**Do:** `GET /v1/requests/<FAILED_REFERENCE>` with the AAT.

**Expect:** `{ "state": "Failed", "terminal_error_code": "provider_unavailable" }`. Failed lookup does **not** return envelope `result`. Support lookup still returns the full envelope.

#### 3.3.14 Cancelled terminal, one envelope

**Do:** restore a fake-success canary ([§3.3.9](#339-config-cache-loads-the-published-document) `standard` v2) **or** point at a hanging real provider. POST `/v1/requests` and abort the client after SSE `accepted` while invocation is in flight (`Ctrl+C`, or `curl --max-time` once `accepted` has arrived). Then D1 + `wrangler r2 object get` for that `request_id`.

**Expect:** `state = Cancelled`. One object at `request/{request_id}/envelope`. Same four keys. `result.finishReason` = `"cancelled"` (placeholder). `usage_event` exists; `ai_attempt` only if invocation recorded attempts.

On the FakeAdapter success path the invoke finishes in milliseconds — abort often loses the race and you get [§3.3.10](#3310-complete-a-request-envelope-key) instead. Treat a reliable Cancelled envelope as **unprobeable on fake-success**; use a slow/unavailable provider if you need this terminal.

#### 3.3.15 Retention purge deletes the envelope

Visit-summary `Governance.retentionClass` is `diagnostic_30d`. Journal rows themselves last **90 days**; that is the horizon this file names. Diagnostic purge can delete the object sooner and null `payload_pointer` while the D1 row remains.

Worker must be running with `--test-scheduled` ([§3.1](#31-setup)).

**Do:** keep **R0**’s envelope. Backdate it past 30 days but **inside** 90 days, then fire the 03:00 UTC cron:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request SET created_at = datetime('now','-31 days'), completed_at = datetime('now','-31 days') WHERE request_id = '<R0>'"

curl -s "$GATEWAY/__scheduled?cron=0+3+*+*+*"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id, payload_pointer FROM ai_request WHERE request_id = '<R0>'"

npx wrangler r2 object get \
  ai-platform-development/request/<R0>/envelope \
  --file /tmp/envelope-after-30d.json --local --env development
```

**Expect:** the row is still there (`90d` journal not elapsed). `payload_pointer` is **NULL**. Get of `request/<R0>/envelope` fails. Support lookup for that reference returns `envelope: null` (outside the diagnostic class).

**Do:** complete a **new** request (**RJ**), backdate `created_at` past 90 days, fire the same cron:

```bash
npx wrangler d1 execute ai-platform-development --local --env development --command \
  "UPDATE ai_request SET created_at = datetime('now','-91 days'), completed_at = datetime('now','-91 days') WHERE request_id = '<RJ>'"

curl -s "$GATEWAY/__scheduled?cron=0+3+*+*+*"

npx wrangler d1 execute ai-platform-development --local --env development --command \
  "SELECT request_id FROM ai_request WHERE request_id = '<RJ>'"

npx wrangler r2 object get \
  ai-platform-development/request/<RJ>/envelope \
  --file /tmp/envelope-after-90d.json --local --env development
```

**Expect:** no D1 row. Get fails. Journal purge deletes the envelope (using `payload_pointer` or the derived `request/{request_id}/envelope` key) **before** dropping the row so a long diagnostic class cannot orphan PII. Waiting ninety calendar days on the wall clock is not required — backdating is the live probe.

#### 3.3.16 Installation purge deletes envelopes

Destructive. Throwaway local only.

**Do:** complete one more request (**R3**), confirm the envelope gets, then:

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/installations/$INSTALLATION_ID/purge" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"

npx wrangler r2 object get \
  ai-platform-development/request/<R3>/envelope \
  --file /tmp/envelope-after-purge.json --local --env development
```

**Expect:** HTTP 200. Get fails. Purge deletes by the derived key `request/{request_id}/envelope` even when `payload_pointer` is already NULL, so mid-sequence nulls cannot leave PII behind.

---

**Unprobeable with these live tools**

| Claim | Why |
| ----- | --- |
| `attempts[].truncated = true` / first 16 KiB kept | FakeAdapter (and typical local provider bodies) are far under `ENVELOPE_RAW_BODY_BYTE_LIMIT` (16 KiB). Needs a provider response larger than that cap. |
| `httpMetadata.contentType = application/json` on the routing-policy object | Publish sets it on `R2.put`. `wrangler r2 object get` has `--file` / `--pipe` only — no metadata printout. The body being JSON is the probeable half ([§3.3.5](#335-key-naming-content-type-and-d1-pointer)). |
| Exhaustive bucket listing (“nothing else exists”) | Wrangler 4.86 has no `r2 object list`. [§3.3.8](#338-what-is-not-stored-in-r2) uses negative gets for every claimed-absent key. |
| Cancelled envelope on FakeAdapter success | Invoke finishes before a client abort is reliable ([§3.3.14](#3314-cancelled-terminal-one-envelope)). |
| Wall-clock 90-day wait | [§3.3.15](#3315-retention-purge-deletes-the-envelope) backdates `created_at` / `completed_at` and runs `0 3 * * *` instead. |
