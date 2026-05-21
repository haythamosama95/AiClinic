# Bootstrap administrator (first-run)

V1-1 auth/RBAC ships a **bootstrap administrator** account used only for first-time clinic setup: creating the single organization, the first branch, and the first owner (or other staff) before day-to-day operations.

This account is **not** a substitute for an owner. After setup, use owner or administrator accounts for ongoing staff management.

## Default credentials (local development)

Values come from `backend/seed/bootstrap_admin.env.example` and the seed migration `20260516100400_auth_rbac_seed.sql`.

| Field     | Default value          |
| --------- | ---------------------- |
| Username  | `admin`                |
| Password  | `admin`                |
| Full name | `Clinic Administrator` |

GoTrue stores the username in the `auth.users.email` column (Supabase password grant requirement). In Studio that column shows the username, not an email address.

Override locally by copying the example file (never commit real secrets):

```bash
cp backend/seed/bootstrap_admin.env.example backend/seed/bootstrap_admin.env
# edit backend/seed/bootstrap_admin.env
```

Smoke scripts and `backend/local/.env` may reference the same variables:

- `BOOTSTRAP_ADMIN_USERNAME`
- `BOOTSTRAP_ADMIN_PASSWORD`
- `BOOTSTRAP_ADMIN_FULL_NAME`
- `BOOTSTRAP_ADMIN_USER_ID` (fixed UUID in seed; used by SQL tests)

## Security expectations

1. **Change the password** after first sign-in. The Flutter app shows a dismissible first-sign-in warning; changing the password in Supabase Studio or a future profile screen is recommended before production use.
2. **Do not share** bootstrap credentials on clinic LAN workstations after the owner account exists.
3. **One organization per installation** in V1-1. The bootstrap admin cannot create a second organization (`ORG_ALREADY_EXISTS`).
4. **RLS still applies** after setup. The bootstrap flag (`is_bootstrap_admin`) does not bypass tenant isolation for routine data access.

## First-run flow (happy path)

```text
App launch (no session)
  → Startup health OK
  → Login
  → Sign in as bootstrap admin
  → (Optional) dismiss shipped-password warning
  → Clinic bootstrap wizard
       1. Organization name (+ optional logo, currency, timezone)
       2. First branch name (+ optional code, address, phone, maps URL)
  → Create staff (e.g. owner or receptionist)
  → Sign out
  → Sign in as new staff → placeholder shell
```

### Preconditions

| Step                | Database state                                       |
| ------------------- | ---------------------------------------------------- |
| Sign in             | Seeded `staff_members` row with `is_bootstrap_admin` |
| Create organization | Zero non-deleted `organizations` rows                |
| Create branch       | Organization exists                                  |
| Create staff        | ≥1 organization **and** ≥1 branch                    |

### Owner creation rule (FR-022c)

| Caller                        | May create `owner` role? |
| ----------------------------- | ------------------------ |
| Bootstrap admin, no owner yet | Yes (first owner only)   |
| Administrator, owner exists   | No                       |
| Owner                         | Yes                      |

## Database setup

From repository root with the local stack running ([developer-workstation.md](./developer-workstation.md)):

```bash
cd backend
supabase db reset   # applies all migrations including seed
```

Verify bootstrap admin:

```bash
./backend/tests/auth_flow_smoke.sh
```

## Troubleshooting

| Symptom                             | Likely cause                                      | Action                                                        |
| ----------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| Invalid login                       | Migrations not applied or wrong username/password | `supabase db reset`; confirm `.env` matches seed              |
| Stuck on bootstrap after org exists | `setup_required` still true                       | Ensure organization + branch created; re-login                |
| `ORG_ALREADY_EXISTS`                | Organization already created                      | Use owner/admin; do not re-run org step                       |
| `NOT_BOOTSTRAP_ADMIN`               | Signed in as non-bootstrap user                   | Sign in as bootstrap admin or owner/admin for branch create   |
| Missing custom claims               | GoTrue hook not loaded                            | Restart auth per [backend/README.md](../../backend/README.md) |

## Related documentation

- Feature quickstart: [specs/002-auth-rbac/quickstart.md](../../specs/002-auth-rbac/quickstart.md)
- RPC contracts: [specs/002-auth-rbac/contracts/bootstrap-provisioning.md](../../specs/002-auth-rbac/contracts/bootstrap-provisioning.md)
- Security model: [docs/architecture/09-security-rbac.md](../architecture/09-security-rbac.md)
