# Deferred auth tests (spec002 Phase 5+)

Tests listed in the auth logging plan appendix are intentionally **not** implemented yet.
Add them when the corresponding `tasks.md` phases land:

- **Phase 5 (US5)**: ~~bootstrap wizard FE tests, `bootstrap_rpc.sql` happy-path flows~~ (done in T029/T030)
- **Phase 6 (US6)**: `create_staff_rpc.sql`, staff provisioning integration
- **Phase 7 (US2)**: idle timeout, in-app refresh failure
- **Phase 8 (US3)**: branch selector, no-branch panel, per-role E2E sign-in
- **Phase 9–10 (US4, US7)**: password reset flows beyond static forgot-password page

Current stage coverage lives in `jwt_claims_contract.sql`, `auth_security_extensions.sql`, and Flutter tests under `frontend/test/`.
