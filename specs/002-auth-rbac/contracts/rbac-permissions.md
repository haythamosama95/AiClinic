# Contract: RBAC Permissions

## Purpose

Defines how permissions are resolved and enforced in V1-1.

## Resolution Order

1. Load grants from `roles_permissions` where `role = session.role` and `is_granted = true`
2. Cache in `AuthSessionContext.permissions` for session lifetime
3. UI checks permission before showing/enabling controls
4. RPCs re-check role/permission for mutating operations
5. RLS enforces org/branch isolation regardless of client

## Client API

```dart
bool hasPermission(String key);
bool hasAnyPermission(Iterable<String> keys);
void requirePermission(String key); // throws / shows denied snackbar
```

## Permission-Denied UX

| Situation              | Behavior                             |
| ---------------------- | ------------------------------------ |
| Control not permitted  | Hidden or disabled                   |
| Route/action attempted | Brief plain-language message + block |

## Branch Scope

| Check               | Rule                                                |
| ------------------- | --------------------------------------------------- |
| Active branch       | Must be in `branch_ids` assignment set              |
| Data reads (future) | Filtered by RLS using JWT `branch_ids`              |
| Branch selector     | Lists only assigned branches; updates client active |

## Blocked: No branch assignment

- User may be authenticated
- `activeBranchId` null
- Branch-scoped permissions treated as denied
- Shell shows administrator-contact message

## RLS Expectations (V1-1 tables)

| Table                      | Isolation pattern                       |
| -------------------------- | --------------------------------------- |
| `organizations`            | `id = jwt.organization_id`              |
| `branches`                 | `organization_id = jwt.organization_id` |
| `staff_members`            | Via assignments in org branches         |
| `staff_branch_assignments` | Branch in jwt `branch_ids`              |
| `roles_permissions`        | Read-only for authenticated users       |

Bootstrap RPCs use `SECURITY DEFINER` with explicit caller checks — not broad RLS bypass.

## Refresh

- Permissions refreshed on login and explicit session refresh after role change
- No mid-session poll in V1-1

## Out of Scope

- Per-organization custom permission overrides
- Permission matrix UI editing
