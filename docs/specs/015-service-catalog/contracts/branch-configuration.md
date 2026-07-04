# Contract: Branch Configuration, Promotions, Copy & New-Branch Setup RPCs

**Feature**: 015-service-catalog | **Migration**: `20260712090500_service_catalog_rpcs.sql`

Same conventions as `service-management.md` (auth_internal + public wrapper, `rpc_result`, `services.manage`, org/branch scope, audit). Branch-scope check via `public.jwt_branch_ids()` where relevant.

## `configure_service_branch`

Set per-branch activation and/or price override for an **already assigned** branch.

**Params**: `p_service_id uuid`, `p_branch_id uuid`, `p_expected_updated_at timestamptz`, `p_status text` (`active`|`inactive`), `p_price_override numeric` (nullable; explicit NULL clears override)

**Behavior**: assert `services.manage`; require an existing non-deleted `service_branches` row → `BRANCH_NOT_ASSIGNED`; branch in org → `BRANCH_NOT_IN_ORG`; concurrency vs row `updated_at` → `STALE_SERVICE_BRANCH`; validate override `>= 0` → `INVALID_PRICE`; **invariant guard**: if the row has an active `promotion_price` and the new effective price (`override` if provided else service default) would be `< promotion_price`, reject → `PROMO_EXCEEDS_PRICE`; apply; audit `service.branch.configure` with old/new (`status`, `price_override`).

**Success data**: `{ "service_branch_id": uuid, "updated_at": timestamptz }`

## `set_service_promotion`

Create/replace or clear the single promotion window for a (service, branch).

**Params**: `p_service_id uuid`, `p_branch_id uuid`, `p_expected_updated_at timestamptz`, `p_promotion_price numeric` (nullable), `p_start_date date` (nullable), `p_end_date date` (nullable)

**Behavior**: assert `services.manage`; require assigned row → `BRANCH_NOT_ASSIGNED`; concurrency → `STALE_SERVICE_BRANCH`.
- **Clear**: all three params NULL → set promotion columns NULL; audit `service.promotion.clear`.
- **Set/replace**: require all three present → `PROMO_INCOMPLETE`; `start <= end` → `PROMO_DATE_RANGE`; `promotion_price >= 0` → `INVALID_PRICE`; `promotion_price <= effective price` (override if set else default) → `PROMO_EXCEEDS_PRICE`; overwrite the single stored window; audit `service.promotion.set` with old/new.

**Success data**: `{ "service_branch_id": uuid, "has_promotion": boolean, "updated_at": timestamptz }`

## `copy_service_branch_configuration`

Copy assignment + activation + override + promotion from a source branch to a target branch.

**Params**: `p_source_branch_id uuid`, `p_target_branch_id uuid`, `p_mode text` (`replace`|`merge`), `p_service_ids uuid[]` (nullable ⇒ all services configured at source)

**Behavior**: assert `services.manage`; both branches in org and in `jwt_branch_ids()` → `BRANCH_NOT_IN_ORG`; source ≠ target → `INVALID_COPY_TARGET`.
- **merge**: for each source `service_branches` row without a matching non-deleted target row, create the target row copying status/override/promotion; leave existing target rows untouched.
- **replace**: for each copied service, overwrite the target row (create if missing) to match source; per-copied-service the target is made to match source. (Confirmation is enforced client-side before invoking; server is idempotent.)
- Re-validate the `promotion_price ≤ effective price` invariant per created/overwritten row (source values are already consistent, but default price differences are impossible since default is service-level, so this holds by construction).
- Audit `service.branch.copy` with `{ source_branch_id, target_branch_id, mode, affected_service_ids }`.

**Success data**: `{ "affected_service_ids": uuid[], "created_count": int, "overwritten_count": int }`

## `setup_new_branch_services` (FR-031)

Populate a newly created branch's catalog configuration. Thin orchestration over the primitives above; the UI presents the three methods.

**Params**: `p_target_branch_id uuid`, `p_method text` (`select`|`copy_all`|`copy_modify`), `p_service_ids uuid[]` (for `select`), `p_source_branch_id uuid` (for `copy_all`/`copy_modify`), `p_mode text` (default `merge`)

**Behavior**: assert `services.manage`; target branch in org.
- `select`: assign the listed services to the target (status `active`, no override/promotion) — reuses assignment logic.
- `copy_all` / `copy_modify`: delegate to `copy_service_branch_configuration(source, target, mode, NULL)`; `copy_modify` simply returns success so the client can open the branch configuration matrix for edits afterward.
- Audit `service.branch.setup` with method + affected services.

**Success data**: `{ "target_branch_id": uuid, "assigned_service_ids": uuid[] }`

> New-branch onboarding integrates with `003-org-branch-management`: after branch creation the client offers this setup step. No auto-assignment occurs (FR-031).

## Error codes (this file)

`FORBIDDEN`, `BRANCH_NOT_ASSIGNED`, `BRANCH_NOT_IN_ORG`, `STALE_SERVICE_BRANCH`, `INVALID_PRICE`, `PROMO_INCOMPLETE`, `PROMO_DATE_RANGE`, `PROMO_EXCEEDS_PRICE`, `INVALID_COPY_TARGET`.
