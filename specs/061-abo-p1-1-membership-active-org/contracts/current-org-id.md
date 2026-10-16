# Contract: `public.current_org_id()`

**Unit**: P1.1 · **Frozen for**: P1.2, P5.1, P5.2 · **Requirements**: FR-005, FR-006, FR-008

## 1. Signature

```sql
public.current_org_id() RETURNS uuid
```

`LANGUAGE plpgsql`, `STABLE`, `SECURITY DEFINER`, `SET search_path = public`. A missing or non-uuid claim returns NULL rather than raising.

`EXECUTE` is granted to `authenticated`, matching `public.jwt_organization_id()`.

## 2. Resolution

On every call the function reads `public.request_jwt_claims()` and re-reads `ai_internal.membership`. It does not cache a previous result.

1. Let `sub` be `request_jwt_claims() ->> 'sub'`, cast to `uuid`. A missing or non-uuid `sub` yields NULL.
2. Let `org` be the `active_org` claim when that claim is present and non-empty. When `active_org` is absent, `org` is the legacy `organization_id` claim. A missing, empty, or non-uuid organisation claim yields NULL.
3. Return `org` only when a row exists in `ai_internal.membership` for `(user_id, organization_id) = (sub, org)`. Otherwise return NULL.

A crafted claim that names an organisation with no membership returns NULL (E2E-P1.1-05). A pre-retrofit token, and the pre-existing H-BK suites' psql impersonation, set only `organization_id`. That claim is the fallback. The membership re-check is the same for both claims (FR-005).

`org` for tenant scope always comes from this function, never from an argument (FR-006, 04 §2.1).

## 3. Dependents

`public.jwt_organization_id()` is replaced so its body is `SELECT public.current_org_id()`. Existing RLS policies and tenant RPCs keep calling `public.jwt_organization_id()` and inherit the re-check (FR-008, rule S5). Their bodies are not rewritten.

When this function returns NULL, an existing `SECURITY DEFINER` path that already raises on a null organisation still raises. `public.list_appointments` reaches `auth_internal.assert_appointment_branch`, which raises `FORBIDDEN` when `public.jwt_organization_id()` is NULL (E2E-P1.1-04). RLS predicates that compare `organization_id` to `public.jwt_organization_id()` match no rows.
