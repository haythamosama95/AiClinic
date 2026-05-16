# Contract: Auth Session

## Purpose

Defines client and backend behavior for staff authentication, session lifecycle, and post-login context in V1-1.

## Sign-In

| Input           | Validation              | Success                        | Failure                   |
| --------------- | ----------------------- | ------------------------------ | ------------------------- |
| email, password | Non-empty, email format | JWT issued; load staff context | Generic error; no session |

- Must call `supabase.auth.signInWithPassword`
- On success, invoke post-login loader: staff profile, branch assignments, permissions, setup flags
- Inactive staff or missing `staff_members` row → deny with actionable message; no partial state

## Session Claims (JWT)

Required custom claims after setup complete:

| Claim             | Type   | Notes                                     |
| ----------------- | ------ | ----------------------------------------- |
| `organization_id` | uuid   | Null only during bootstrap/setup          |
| `branch_ids`      | string | Comma-separated UUIDs                     |
| `role`            | string | `staff_role` enum value                   |
| `staff_member_id` | uuid   |                                           |
| `setup_required`  | bool   | True when org missing and bootstrap admin |

## Session Lifecycle

| Event                      | Behavior                                       |
| -------------------------- | ---------------------------------------------- |
| App process exit           | Session ended; no restore on next launch       |
| In-app token refresh       | Automatic via SDK while running                |
| 15 min no keyboard/pointer | `signOut()` + clear `AuthSessionContext`       |
| Explicit logout            | `signOut()` + clear context; navigate to login |
| Refresh failure            | Redirect login with session-ended message      |

## Post-Login Navigation

| Condition                     | Destination                     |
| ----------------------------- | ------------------------------- |
| `setup_required == true`      | Clinic bootstrap wizard         |
| Authenticated, setup complete | Authenticated placeholder shell |
| No branch assignments         | Shell blocked state             |

## Route Guard Rules

- Unauthenticated → `/login` (except public startup/login/forgot-password)
- Authenticated + setup required → `/bootstrap` (cannot access staff provision)
- Authenticated + setup complete → `/home` (placeholder shell)
- Protected feature routes under `/app/*` require authenticated + setup complete + branch scope (if route requires branch)

## Forgot Password

- UI shows static message: contact clinic administrator
- No API call to self-service reset

## Out of Scope

- SSO, MFA, email reset links
- Subscription-based login block
- Persisted “remember me” across restarts
