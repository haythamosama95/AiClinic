# Setup verification checklist

Use this checklist after following the workstation guides to confirm User Story 2 acceptance: a new operator can reach the unauthenticated startup experience using only documented steps.

## Prerequisites installed

- [ ] Git is installed and the repository is cloned locally.
- [ ] Docker Engine is installed and `docker compose version` succeeds.
- [ ] Flutter stable is installed with Windows desktop enabled (`flutter doctor` shows no blocking issues).
- [ ] `curl` is available in the shell used for backend validation.

## Server node (receptionist PC or developer host)

Complete [server-node.md](./server-node.md) first when this machine hosts the clinic-local stack.

- [ ] `backend/local/.env` exists (copied from `.env.example` if needed).
- [ ] `docker compose up -d` in `backend/local` reports all services running.
- [ ] `./backend/tests/connectivity_smoke.sh` prints only `PASS` lines and exits `0`.
- [ ] `./backend/tests/validate_local_stack.sh` completes successfully.
- [ ] Supabase Studio opens at `http://127.0.0.1:54323` (default port) when accessed from the server machine.
- [ ] `SUPABASE_PUBLIC_URL` in `.env` matches the URL clients will use (loopback for solo dev, LAN IP for clinic clients).

## Deployment profile

Complete [client-workstation.md](./client-workstation.md) for profile placement and field values.

- [ ] `deployment-profile.json` exists at one of the supported lookup paths (see [deployment-profile contract](../../specs/001-project-scaffolding/contracts/deployment-profile.md)).
- [ ] `deployment_mode` is `local`.
- [ ] `supabase_url` matches `SUPABASE_PUBLIC_URL` on the server node.
- [ ] `supabase_anon_key` matches `SUPABASE_ANON_KEY` in `backend/local/.env`.
- [ ] Optional `source_device_role` is set to `server-node` or `client-node` when documenting the machine role.

## Flutter startup experience

- [ ] From `frontend/`, `flutter pub get` completes without errors.
- [ ] `flutter analyze` reports no issues.
- [ ] `flutter test` passes.
- [ ] `flutter run -d windows` reaches the unauthenticated entry screen with a valid profile and running stack.
- [ ] With the stack stopped (or wrong `supabase_url`), the entry screen shows degraded/unreachable status—not a crash.
- [ ] With the profile removed or invalid, setup guidance appears and protected routes stay blocked.

## LAN client (when applicable)

Skip this section for single-machine development on loopback.

- [ ] Server firewall allows inbound TCP on `SUPABASE_HTTP_PORT` (default `54321`) from clinic LAN devices.
- [ ] A second machine on the LAN can `curl` the server gateway health URL successfully.
- [ ] Client `deployment-profile.json` uses the receptionist PC LAN IP, not `127.0.0.1`.
- [ ] Client `flutter run` shows healthy or degraded connectivity based on actual reachability.

## Documentation sign-off

- [ ] Operator can name which guide they followed: [developer-workstation.md](./developer-workstation.md), [server-node.md](./server-node.md), or [client-workstation.md](./client-workstation.md).
- [ ] No undocumented manual steps were required beyond this checklist and linked guides.
- [ ] Backup expectations in [troubleshooting.md](./troubleshooting.md) are understood for the target deployment tier.

When every applicable box is checked, User Story 2 independent testing is satisfied for that environment.
