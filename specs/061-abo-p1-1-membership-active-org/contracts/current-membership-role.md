# Contract: `public.current_membership_role()`

**Unit**: P1.1 · **Frozen for**: P1.2, P5.1, P5.2 · **Requirements**: FR-007

## 1. Signature

```sql
public.current_membership_role() RETURNS public.staff_role
```

`STABLE`, `SECURITY DEFINER`, `SET search_path = public`.

`EXECUTE` is granted to `authenticated`.

## 2. Resolution

Return `ai_internal.membership.role` for `(user_id, organization_id) = (sub, public.current_org_id())`.

When `current_org_id()` is NULL, or that membership row is absent, return NULL.

`sub` is the `sub` claim, as in `current_org_id()`.

## 3. Authority

The returned value is the membership role. The staff roles are `administrator`, `doctor`, `receptionist`, and `lab_staff`.

Billing authority is the membership role `administrator`. This function does not read `public.roles_permissions`. An update to `public.roles_permissions` does not change the returned role (E2E-P1.1-06, T-2).
