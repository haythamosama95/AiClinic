# Contract: Catalog Queries (014)

Read and optional-create paths for organization-scoped medication, investigation, and vital sign catalogs.

## Authorization summary

| RPC | Permission |
| --- | ---------- |
| `search_medications` | `visits.create` OR `visits.edit_soap` |
| `search_investigations` | `visits.create` OR `visits.edit_soap` |
| `list_predefined_vital_signs` | `visits.create` OR `visits.edit_soap` |
| `create_catalog_medication` | `visits.edit_soap` |
| `create_catalog_investigation` | `visits.edit_soap` |
| `create_predefined_vital_sign` | `visits.edit_soap` |

All scoped to `jwt_organization_id()`.

---

## RPC: `search_medications`

| Parameter | Type | Required | Default |
| --------- | ---- | -------- | ------- |
| `p_query` | text | No | `''` |
| `p_limit` | int | No | `20` |

**Rules**:

- `p_limit` clamped 1–50
- Match `name ILIKE '%' || trim(p_query) || '%'` on non-deleted org rows
- Order by `name ASC`

**Returns** `data.items`:

```json
[
  { "id": "uuid", "name": "Amoxicillin" }
]
```

---

## RPC: `search_investigations`

Same parameters and shape as `search_medications`.

---

## RPC: `list_predefined_vital_signs`

No parameters.

**Returns** `data.items`:

```json
[
  { "id": "uuid", "name": "Blood Pressure", "default_unit": "mmHg" }
]
```

---

## RPC: `create_catalog_medication`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_name` | text | Yes |

**Rules**:

- Name max 200 chars; client-normalized before call
- On duplicate name (case-insensitive): return success with existing `id` (idempotent)

**Returns** `data`: `{ "id": "uuid", "name": "string", "created": true|false }`

---

## RPC: `create_catalog_investigation`

Same as `create_catalog_medication`.

---

## RPC: `create_predefined_vital_sign`

| Parameter | Type | Required |
| --------- | ---- | -------- |
| `p_name` | text | Yes |
| `p_default_unit` | text | No |

**Rules**: Name max 100; unit max 50; idempotent on duplicate name.

**Returns** `data`: `{ "id": "uuid", "name": "string", "default_unit": "string|null", "created": true|false }`

---

## Client integration notes

1. Debounce search calls 300ms while typing.
2. Apply `CatalogNameNormalizer` before custom entry save and catalog create.
3. Show `SaveToCatalogDialog` only after successful visit-line save with custom (non-catalog) name.
4. Predefined vital signs: use `list_predefined_vital_signs` on page load; optional search client-side filter on small list.
