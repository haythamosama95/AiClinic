# Contract: `public.set_active_organization(uuid)`

**Unit**: P1.1 · **Requirements**: FR-004

Later units consume `current_org_id()` and `current_membership_role()`, not this RPC. The RPC's result body is the wire shape E2E-P1.1-02 and E2E-P1.1-03 assert.

## 1. Signature

```sql
public.set_active_organization(p_organization_id uuid) RETURNS public.rpc_result
```

`VOLATILE`, `SECURITY DEFINER`, `SET search_path = public`.

`EXECUTE` is granted to `authenticated` and revoked from `PUBLIC` and `anon`.

The caller is the `sub` claim from `public.request_jwt_claims()`, which is the source H-BK psql impersonation and PostgREST both populate. The function takes no user-id argument.

## 2. Result

`public.rpc_result` is `(success boolean, data jsonb, error_code text, error_message text)`.

### 2.1 Success

A live `ai_internal.membership` row exists for `(sub, p_organization_id)`.

The function upserts `ai_internal.user_active_organization` for that user and organisation and sets `updated_at` to `now()`.

```text
success = true
data = {"organization_id": "<p_organization_id>"}
error_code = null
error_message = null
```

The already issued JWT is not rewritten. `active_org` changes on the next access-token hook run (`public.get_custom_claims(jsonb)`), which reads the stored row (E2E-P1.1-02).

### 2.2 No membership

No live membership for `(sub, p_organization_id)`, including a null `sub` or a null `p_organization_id`.

```text
success = false
data = null
error_code = 'FORBIDDEN'
error_message = 'You do not have a membership in that organisation.'
```

`ai_internal.user_active_organization` is not written. The next hook run therefore emits the same `active_org` as before the call (E2E-P1.1-03).

## 3. What this RPC does not do

It does not choose the tenant for any other table. Tenant scope stays `public.current_org_id()` (FR-006). It is the only way to change the active organisation after sign-in (OQ-2).
