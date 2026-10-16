# Stage 08 catalog-vs-code conflicts

Catalog remains the journey spec. CODE (migrations) is authoritative for
assertions in the Stage 08 catalog SQL files. Tests follow CODE.

## S08-069

- **Catalog claim:** `GRANT EXECUTE … TO authenticated` only → function-level deny for `anon` (PostgREST HTTP 401/403). Same class as S02-002 (`permission denied for function get_visit_chief_complaint`).
- **Code behavior:** `public.get_visit_chief_complaint` is SECURITY INVOKER. Migrations grant `EXECUTE` to `authenticated` without `REVOKE … FROM PUBLIC` / `anon`. PostgreSQL default EXECUTE-to-PUBLIC remains, so `anon` enters the wrapper and is denied when resolving `auth_internal.get_visit_chief_complaint` (no USAGE on schema `auth_internal`). Observed: SQLSTATE `42501`, message `permission denied for schema auth_internal`. No `rpc_result` is returned.
- **File:line:** `backend/supabase/migrations/20260802120000_context_provider_chief_complaint.sql:65` (`GRANT EXECUTE ON FUNCTION public.get_visit_chief_complaint(uuid) TO authenticated;`); restated at `backend/supabase/migrations/20260805120000_e3_review_recorded_at_created_at.sql:69`. Contrast: `get_ai_availability` revokes FROM PUBLIC/anon (`20260802140000_ai_availability_flag.sql:39`, `20260821120000_fix_get_ai_availability_security_definer.sql:13`) — that is why S02-002 can ILIKE the function name.
- **Register 5 #12:** assert SQLSTATE `42501`, not PostgREST HTTP 401/403.
