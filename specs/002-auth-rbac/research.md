# Research: Auth and RBAC

## Decision 1: Supabase GoTrue + PostgreSQL custom claims hook

- **Decision**: Use GoTrue email/password auth with a PostgreSQL `get_custom_claims(uid)` function invoked via the standard Supabase custom access token hook.
- **Rationale**: Matches `docs/architecture/09-security-rbac.md` and roadmap V1-1; keeps JWT claims (`organization_id`, `branch_ids`, `role`, `staff_member_id`) authoritative for RLS.
- **Alternatives considered**: Client-only role storage (rejected — violates constitution). Custom auth microservice (rejected — violates layer boundaries).

## Decision 2: Bootstrap administrator without pre-seeded organization

- **Decision**: Seed only the bootstrap auth user + `staff_members` row with `is_bootstrap_admin = true` and no branch assignments. `get_custom_claims` returns `setup_required: true` and null/empty org claims until organization exists. Bootstrap RPCs (`bootstrap_create_organization`, `bootstrap_create_branch`) run as `SECURITY DEFINER` with guards: caller is bootstrap admin, org count = 0 for create org.
- **Rationale**: Spec clarification C requires admin-created org/branch with no pre-seed; RLS cannot scope bootstrap admin to a non-existent tenant without a controlled elevated path.
- **Alternatives considered**: Pre-seed org/branch (rejected by clarification). Service-role-only bootstrap from Flutter (rejected — exposes service key on desktop).

## Decision 3: No session persistence across application restarts

- **Decision**: Configure Supabase auth client to avoid restoring sessions from platform storage on cold start; always present login after process exit. In-process refresh continues via SDK while app runs.
- **Rationale**: Spec requires sign-out on app close; Supabase Flutter defaults may persist session locally.
- **Alternatives considered**: Persist session with explicit logout only (rejected by clarification). Encrypted local session cache (rejected — unnecessary complexity for V1-1).

## Decision 4: Idle timeout via client activity listener

- **Decision**: 15-minute `Timer` reset on keyboard and pointer events at app root (`Listener` / focus scope); on fire call `signOut()` and clear auth state.
- **Rationale**: Spec defines activity as keyboard/pointer only; background token refresh must not reset timer.
- **Alternatives considered**: OS-level idle detection (rejected — platform variance). Server-side session TTL only (rejected — does not meet 15-minute workstation policy while app open).

## Decision 5: Admin password reset via Auth Admin API from RPC

- **Decision**: `admin_reset_staff_password` RPC validates caller role, then uses `auth.users` update through Supabase `supabase_auth_admin` pattern (or edge-less SQL `auth.update_user` via security definer wrapper documented in migration). Returned password is the caller-supplied new value (display only — not read from hash).
- **Rationale**: Passwords are hashed; admins only see values they set. Matches FR-024.
- **Alternatives considered**: Store recoverable passwords (rejected — security). Email self-service reset (rejected — spec).

## Decision 6: Staff creation uses Auth Admin + staff row in one RPC

- **Decision**: `create_staff_account` RPC creates `auth.users` entry, `staff_members`, and `staff_branch_assignments` transactionally; enforces FR-022c owner-creation rules.
- **Rationale**: Keeps provisioning atomic and branch-scoped; prevents orphan auth users.
- **Alternatives considered**: Client creates auth user then staff row (rejected — partial failure risk).

## Decision 7: Subscription cache present but non-blocking

- **Decision**: Create and seed `subscription_cache`; no check in `get_custom_claims` or login path that blocks on `valid_until`.
- **Rationale**: Clarification + `docs/architecture/10-resilience-and-scale.md` graceful degradation; enforcement deferred.
- **Alternatives considered**: Soft warning banner on expiry (deferred — not in V1-1 spec).

## Decision 8: Permission matrix seeded statically

- **Decision**: Seed `roles_permissions` from architecture permission keys; owner receives all grants; other roles per documented operational subsets (see `data-model.md`).
- **Rationale**: V1-1 requires five-role defaults; UI editing deferred to V1-2.
- **Alternatives considered**: Empty matrix configured manually (rejected — blocks testing).

## Decision 9: Flutter auth module + router integration

- **Decision**: New `features/auth` module; extend existing `GoRouter` with `authSessionProvider` listenable; map `startupEntry` CTA to login.
- **Rationale**: Aligns with `docs/architecture/07-frontend.md` feature-first layout; preserves V1-0 startup investment.
- **Alternatives considered**: Fold auth into `startup` feature (rejected — blurs lifecycle boundaries).

## Decision 10: JWT `branch_ids` encoding

- **Decision**: Encode `branch_ids` claim as comma-separated UUID string per RLS examples in `docs/architecture/05-database.md`; client parses to list; active branch held separately in client session state.
- **Rationale**: Matches documented policy pattern `string_to_array(auth.jwt() ->> 'branch_ids', ',')`.
- **Alternatives considered**: JSON array in claim (rejected — diverges from architecture examples without migration benefit).
