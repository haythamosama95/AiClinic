# Contract: Diagnosis Catalog & Visit Coded Diagnosis (014, P3)

Org-scoped coded-diagnosis catalog reusing the 013 catalog pattern, plus visit-level coded-diagnosis lines that coexist with the free-text `visit_clinical_notes.diagnosis`. All scoped to `jwt_organization_id()`; visit lines scoped via `assert_visit_branch_scope`.

## Authorization summary

| RPC | Permission |
| --- | ---------- |
| `search_diagnosis_codes` | `visits.create` OR `visits.edit_soap` |
| `create_catalog_diagnosis_code` | `visits.edit_soap` |
| `create_visit_diagnosis_code` | `visits.edit_soap` |
| `archive_visit_diagnosis_code` | `visits.edit_soap` |

---

## RPC: `search_diagnosis_codes`

| Parameter | Type | Required | Default |
| --------- | ---- | -------- | ------- |
| `p_query` | text | No | `''` |
| `p_limit` | int | No | `20` (clamped 1–50) |

**Rules**: Match `name ILIKE '%q%' OR code ILIKE '%q%'` on non-deleted org rows; order by `name ASC`.

**Returns** `data.items`:

```json
[{ "id": "uuid", "code": "I10", "name": "Essential hypertension" }]
```

---

## RPC: `create_catalog_diagnosis_code`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_name` | text | Yes (≤200, normalized) |
| `p_code` | text | No (≤20) |

**Rules**: Idempotent on duplicate `lower(trim(name))` within org → return success with existing `id` (`CATALOG_DUPLICATE` handled as success).

**Returns** `data`: `{ "id": "uuid", "code": "string|null", "name": "string", "created": true|false }`

---

## RPC: `create_visit_diagnosis_code`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_id` | uuid | Yes |
| `p_label` | text | Yes (≤200, normalized) |
| `p_code` | text | No (≤20) |
| `p_diagnosis_code_id` | uuid | No (catalog link; null for custom) |

**Returns** `data`: `{ "visit_diagnosis_code_id": "uuid" }`. Multiple lines per visit allowed.

## RPC: `archive_visit_diagnosis_code`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_visit_diagnosis_code_id` | uuid | Yes |

Soft delete. Returns `{ "id": "uuid" }`.

---

## Client integration notes

1. `diagnosis_autocomplete_field.dart` wraps the existing `CatalogAutocompleteField`, calling `search_diagnosis_codes` with 300ms debounce.
2. On selecting a catalog match → `create_visit_diagnosis_code` with `p_diagnosis_code_id`. On custom entry → normalize, `create_visit_diagnosis_code` (no id), then `SaveToCatalogDialog` → optional `create_catalog_diagnosis_code`.
3. Free-text `diagnosis` continues to save via `save_visit_documentation` (013, unchanged); coded diagnosis is **optional and never blocks** free-text-only assessment (FR-023).
4. Errors: `FORBIDDEN`, `NOT_FOUND` (visit out of scope), `INVALID_INPUT`.
