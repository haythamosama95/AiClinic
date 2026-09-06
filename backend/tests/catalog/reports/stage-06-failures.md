# Stage 06 catalog SQL — failure report

Branch: `ai/e2e-stage-06-minting-aat-pgtap` (`f3af3813`)  
Command: `bash backend/tests/catalog/run.sh` (from repo root)  
Local DB: `127.0.0.1:54322` (user `postgres`; password from `backend/local/.env` `POSTGRES_PASSWORD`)  
Runner iteration: 2  
`psql -v ON_ERROR_STOP=1` per file. No test/harness/migration/Worker files were modified. No commit.

## Counts

| Scope | Passed | Skipped | Failed | Missing |
| --- | ---: | ---: | ---: | ---: |
| Files (`run.sh`) | 6 | 0 | 0 | 0 |
| S06-001 … S06-047 | 47 | 0 | 0 | 0 |
| S02-001 … S02-027 | 27 | 0 | 0 | 0 |
| Harness smoke (HARNESS-001 … 003) | 3 | 0 | 0 | 0 |

Stage 02 still passed? **yes** (S02-001 … S02-027, both Stage 02 files).  
Harness smoke passed? **yes** (HARNESS-001 … 003).  
`run.sh` summary line: `catalog SQL harness: 6 passed, 0 failed.`

S06 passed: **47** (all recorded `t` in `catalog_results`; `fail_if_any` did not raise on any Stage 06 file).  
S06 failed: **0**.  
S06 skipped: **0**. S06-041 … S06-047 clinic-half blocks exist in `stage-06-verify-and-handoff.sql` and **passed**. Platform HTTP is Register 5 #17 and is **not** a skip of those IDs (noted in `detail` only).  
S06 missing: **0**.

Green: **yes** (zero failures, all 47 S06 recorded pass, Stage 02 pass).

## File outcomes

| File | Outcome |
| --- | --- |
| `harness-smoke.sql` | **Passed.** 3/3 recorded `t`; `fail_if_any` did not raise; ROLLBACK. |
| `stage-02-availability-and-enroll.sql` | **Passed.** 14/14 recorded `t` (S02-001 … S02-014); `fail_if_any` did not raise; ROLLBACK. |
| `stage-02-revoke-rotate-availability.sql` | **Passed.** 13/13 recorded `t` (S02-015 … S02-027); `fail_if_any` did not raise; ROLLBACK. |
| `stage-06-happy-path-and-lifecycle.sql` | **Passed.** 16/16 recorded `t` (S06-017 … S06-032); `fail_if_any` did not raise; ROLLBACK. |
| `stage-06-issuer-guards.sql` | **Passed.** 16/16 recorded `t` (S06-001 … S06-016); `fail_if_any` did not raise; ROLLBACK. |
| `stage-06-verify-and-handoff.sql` | **Passed.** 15/15 recorded `t` (S06-033 … S06-047); `fail_if_any` did not raise; ROLLBACK. S06-041 … S06-047 clinic-half passed; platform HTTP half noted as Register 5 #17 in `detail`. |

File run order from `stage-*.sql` glob: Stage 02 files, then `stage-06-happy-path-and-lifecycle.sql`, then `stage-06-issuer-guards.sql`, then `stage-06-verify-and-handoff.sql`.

## Failures

Zero failures. No `fail_if_any` RAISE. No `ON_ERROR_STOP` abort. Every Stage 06 file dumped `catalog_results` and completed `fail_if_any` without raising.

## Traceability

Every id is pass / fail / skip / missing.

| ID | Result |
| --- | --- |
| S06-001 | pass |
| S06-002 | pass |
| S06-003 | pass |
| S06-004 | pass |
| S06-005 | pass |
| S06-006 | pass |
| S06-007 | pass |
| S06-008 | pass |
| S06-009 | pass |
| S06-010 | pass |
| S06-011 | pass |
| S06-012 | pass |
| S06-013 | pass |
| S06-014 | pass |
| S06-015 | pass |
| S06-016 | pass |
| S06-017 | pass |
| S06-018 | pass |
| S06-019 | pass |
| S06-020 | pass |
| S06-021 | pass |
| S06-022 | pass |
| S06-023 | pass |
| S06-024 | pass |
| S06-025 | pass |
| S06-026 | pass |
| S06-027 | pass |
| S06-028 | pass |
| S06-029 | pass |
| S06-030 | pass |
| S06-031 | pass |
| S06-032 | pass |
| S06-033 | pass |
| S06-034 | pass |
| S06-035 | pass |
| S06-036 | pass |
| S06-037 | pass |
| S06-038 | pass |
| S06-039 | pass |
| S06-040 | pass |
| S06-041 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |
| S06-042 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |
| S06-043 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |
| S06-044 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |
| S06-045 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |
| S06-046 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |
| S06-047 | pass (clinic-half; platform HTTP is Register 5 #17, not a skip of the ID) |

S02-001 … S02-027: pass (regression check: Stage 06 run did **not** break Stage 02).  
HARNESS-001 … HARNESS-003: pass.

## Full `run.sh` stdout/stderr

```
== catalog SQL: harness-smoke.sql ==
BEGIN
CREATE TABLE
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
 catalog_common_setup 
----------------------
 
(1 row)

DO
DO
DO
                   test_name                    | passed |                                                                                   detail                                                                                    
------------------------------------------------+--------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 HARNESS-001 — bootstrap admin exists           | t      | ok
 HARNESS-002 — common setup stashes Sunrise ids | t      | org=e907a477-05af-42f2-8124-3938b4f9166c branch=6e25637d-5c1a-4797-9f29-b28f2486e4fe admin=47b8e53e-c437-4385-84ba-6efe518a9444 doctor=c9987cf4-5204-4033-bd95-d381f9f4bfe2
 HARNESS-003 — empty keystore after reset       | t      | keys=0 issuance=0 flag={"enrolled": false, "platform_base_url": null}
(3 rows)

 fail_if_any 
-------------
 
(1 row)

ROLLBACK
PASS  harness-smoke.sql
== catalog SQL: stage-02-availability-and-enroll.sql ==
BEGIN
CREATE TABLE
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
 catalog_common_setup 
----------------------
 
(1 row)

CREATE TABLE
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
                                      test_name                                       | passed |                                                                                              detail                                                                                              
--------------------------------------------------------------------------------------+--------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 S02-001 — Availability flag returns the seeded default before any enrollment         | t      | flag={"enrolled": false, "platform_base_url": null} keys=0
 S02-002 — Availability flag and keypair RPCs are denied to anon                      | t      | avail_sqlstate=42501 avail_msg=permission denied for function get_ai_availability enroll_sqlstate=42501 enroll_msg=permission denied for function enroll_installation_keypair keys=0
 S02-003 — Rotate before any enroll fails with INSTALLATION_NOT_ENROLLED              | t      | success=false code=INSTALLATION_NOT_ENROLLED msg=Enroll an installation keypair before rotating. keys=0
 S02-004 — Enroll as a non-administrator (doctor) is FORBIDDEN                        | t      | success=false code=FORBIDDEN msg=Only administrators may enroll installation keys. keys=0
 S02-005 — Rotate as a non-administrator (doctor) is FORBIDDEN                        | t      | success=false code=FORBIDDEN msg=Only administrators may rotate installation keys. keys=0
 S02-006 — Revoke as a non-administrator (doctor) is FORBIDDEN, even with a blank kid | t      | success=false code=FORBIDDEN msg=Only administrators may revoke installation keys. keys=0
 S02-007 — Enroll as a deactivated administrator is FORBIDDEN                         | t      | setup=ok admin_active=false success=false code=FORBIDDEN msg=Only administrators may enroll installation keys. keys=0
 S02-008 — Enroll as an auth user with no staff row is FORBIDDEN                      | t      | success=false code=FORBIDDEN msg=Only administrators may enroll installation keys. keys=0
 S02-009 — First enroll (happy path) mints installation I0 and key K0                 | t      | success=true code=<null> kid=4b1c3649-ba71-4e2e-ada1-bcc2a149c648 iid=c9cfd7e3-8065-4314-a34f-d893cb02b5dd x_len=43 keys=1 data_keys={installation_id,kid,public_jwk}
 S02-010 — Keystore is not readable by authenticated clients                          | t      | sqlstate=42501 msg=permission denied for schema ai_internal
 S02-011 — Keypair enrollment does not touch the availability flag                    | t      | flag={"enrolled": false, "platform_base_url": null}
 S02-012 — Second enroll while an active key exists fails with ALREADY_ENROLLED       | t      | success=false code=ALREADY_ENROLLED msg=An active installation key already exists. Use rotate_installation_key() to rotate keys. keys=1 k0_active=true
 S02-013 — Rotate (happy path) adds key K1 under the same installation I0             | t      | success=true code=<null> k1=2668772b-f3d4-4965-b3d8-a5f70e94bee2 iid=c9cfd7e3-8065-4314-a34f-d893cb02b5dd keys=2
 S02-014 — Revoke the superseded key K0 (happy path)                                  | t      | success=true code=<null> payload_kid=4b1c3649-ba71-4e2e-ada1-bcc2a149c648 row_revoked_at=2026-09-06 15:33:04.555661+00 payload_revoked_at=2026-09-06 15:33:04.555661+00 keys=2 k1_untouched=true
(14 rows)

 fail_if_any 
-------------
 
(1 row)

ROLLBACK
PASS  stage-02-availability-and-enroll.sql
== catalog SQL: stage-02-revoke-rotate-availability.sql ==
BEGIN
CREATE TABLE
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
 catalog_common_setup 
----------------------
 
(1 row)

CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
                                           test_name                                            | passed |                                                                                                                                                                 detail                                                                                                                                                                  
------------------------------------------------------------------------------------------------+--------+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 S02-015 — Re-revoking an already-revoked key is idempotent                                     | t      | success=true error_code=<null> data={"kid": "65ff8d58-ec04-4545-9102-5f10f25e4063", "revoked_at": "2026-09-06T15:33:04.644537+00:00"} t0=2026-09-06 15:33:04.644537+00 updated_at_unchanged=true
 S02-016 — Revoke with a blank kid fails with INVALID_INPUT                                     | t      | empty=[false,INVALID_INPUT,Key id is required.] ws=[false,INVALID_INPUT,Key id is required.]
 S02-017 — Revoke with an unknown kid fails with KEY_NOT_FOUND                                  | t      | success=false error_code=KEY_NOT_FOUND error_message=Installation key was not found.
 S02-018 — Revoke with a soft-deleted kid fails with KEY_NOT_FOUND                              | t      | success=false error_code=KEY_NOT_FOUND error_message=Installation key was not found. still_deleted=true
 S02-019 — Revoking the last active key fails with CANNOT_REVOKE_LAST_ACTIVE_KEY                | t      | success=false error_code=CANNOT_REVOKE_LAST_ACTIVE_KEY error_message=Cannot revoke the last active installation key. Rotate a replacement key first. active_before=1 k1_revoked_at=<null>
 S02-020 — Production rotation order: rotate to K2, then revoke K1 succeeds                     | t      | rotate_ok=true k2=a95c4891-e124-4317-8325-41551adfc8f0 revoke_ok=true revoke_code=<null> rows=3 active=1
 S02-021 — Single-installation trigger rejects a second installation_id                         | t      | raised=true sqlstate=P0001 message=SINGLE_INSTALLATION_VIOLATION distinct_installation_id=1
 S02-022 — Recovery re-enroll after all keys are revoked reuses installation I0                 | t      | success=true error_code=<null> kx=75d6956f-d292-47ca-b473-9cc69de5b497 installation_id=93402c4b-67cb-44c0-a29a-a9c819ec60c9 active_before=0 active_after=1
 S02-023 — Rotate succeeds when every key is revoked but rows exist                             | t      | success=true error_code=<null> k3=ad492b9c-52bc-4d3c-9cc0-89242bf007da installation_id=93402c4b-67cb-44c0-a29a-a9c819ec60c9 active_before=0 active_after=1
 S02-024 — Availability flag flip after Stage 3 platform enrollment                             | t      | set_success=true set_data={"enrolled": true, "platform_base_url": "http://127.0.0.1:8787"} get={"enrolled": true, "platform_base_url": "http://127.0.0.1:8787"} updated_by=a0000000-0000-4000-8000-000000000001 created_by=<null> created_before=<null> set_err=<none>: get_err=<none>:
 S02-025 — Availability falls back to the COALESCE default when the row is missing/soft-deleted | t      | got={"enrolled": false, "platform_base_url": null} call_err=<none>:
 S02-026 — Administrator holds the ai.visit_summary grant; doctor does not                      | t      | admin_access=true admin_visit_summary=true doctor_access=true granted_summary_others=0 false_rows_visible_to_admin=2 call_err=<none>:
 S02-027 — Stage 3 handoff: enroll output is exactly what platform enrollment consumes          | t      | handoff={"kid": "ad492b9c-52bc-4d3c-9cc0-89242bf007da", "algorithm": "EdDSA", "public_key": "T5a01Dgk3StFF4x5PFDrGeNn0kkq23SUEc_BvST8vcE", "installation_id": "93402c4b-67cb-44c0-a29a-a9c819ec60c9"} rpc_kid=ad492b9c-52bc-4d3c-9cc0-89242bf007da newest_kid=ad492b9c-52bc-4d3c-9cc0-89242bf007da has_row_secret=true call_err=<none>:
(13 rows)

 fail_if_any 
-------------
 
(1 row)

ROLLBACK
PASS  stage-02-revoke-rotate-availability.sql
== catalog SQL: stage-06-happy-path-and-lifecycle.sql ==
BEGIN
CREATE TABLE
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
                                              test_name                                              | passed |                                                                                                                                                                                                             detail                                                                                                                                                                                                             
-----------------------------------------------------------------------------------------------------+--------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 S06-017 — Role without any ai.* grant is AI_ACCESS_DENIED                                           | t      | sqlstate=P0001 sqlerrm=AI_ACCESS_DENIED issuance=0
 S06-018 — Role whose ai.* grant was revoked is AI_ACCESS_DENIED                                     | t      | setup=ok sqlstate=P0001 sqlerrm=AI_ACCESS_DENIED issuance=0
 S06-019 — Happy path: doctor mints a fully-populated AAT                                            | t      | jws=true header=true claims=true lifetime=true ledger=true keys=true settings=true audit=true pub=true kid=e4beeffd-ba97-4fae-8e54-8867221de75d iss=493b4803-9202-4855-b087-702afda89fa7 sub=ce3b2d30-b0f2-4ff7-8406-dcb26876bb74 scopes=["ai.access"] delta=600 payload_iat=1788708785 ledger_iat=2026-09-06 15:33:05+00 ledger_iat_epoch=1788708785 to_ts_eq=true issuance=1 created_by=af6d2b32-8f60-450c-9209-a170539b928e
 S06-020 — Administrator mint carries both granted ai.* scopes, sorted                               | t      | role=administrator scopes=["ai.access", "ai.visit_summary"] kid=e4beeffd-ba97-4fae-8e54-8867221de75d delta=600 actor=3da88564-4957-4e32-a46a-7454f9262e7d
 S06-021 — Caller-supplied p_scopes subset is ignored                                                | t      | scopes=["ai.access", "ai.visit_summary"] actor=3da88564-4957-4e32-a46a-7454f9262e7d
 S06-022 — Caller-supplied scope the role lacks (or bogus scope) is ignored                          | t      | scopes=["ai.access"] actor=ce3b2d30-b0f2-4ff7-8406-dcb26876bb74
 S06-023 — Caller-supplied empty scope array is ignored                                              | t      | raised=false sqlstate=<none> sqlerrm=<none> scopes=["ai.access"]
 S06-024 — Branch claim is the primary active branch, not an arbitrary one                           | t      | create=ok br_a=ec8c2ece-0f15-430c-913a-945a8a6abadf br_b=e4e62d37-c870-4346-8f31-3fc258c021eb claim=ec8c2ece-0f15-430c-913a-945a8a6abadf
 S06-025 — Successive mints get unique jti with stable identity claims                               | t      | j0=193bf892-f21b-42f2-bd3e-55f201573234 j1=b025fa60-c3c0-41ee-a5a1-909ef98dbdf5 distinct=true dup_jti=0 iat0=1788708785 iat1=1788708785
 S06-026 — Missing app_settings rows fall back to built-in defaults                                  | t      | aud=ai-platform ver=1 delta=600
 S06-027 — After additive rotation the new kid signs and old tokens still verify                     | t      | rotate=ok k1=1f7261fa-0249-4add-8478-a9f0055dd6c8 mint_kid=1f7261fa-0249-4add-8478-a9f0055dd6c8 iss=493b4803-9202-4855-b087-702afda89fa7 verify_aat0=true k0_revoked=<null>
 S06-028 — After revoking the old kid, minting continues on the new kid and old-kid tokens die       | t      | revoke=ok mint_kid=1f7261fa-0249-4add-8478-a9f0055dd6c8 expected_k1=1f7261fa-0249-4add-8478-a9f0055dd6c8 verify_aat0=false
 S06-029 — Re-enrollment after a zero-active-keystore recovers minting with the same installation id | t      | enroll=ok k2=97ed45b5-b5e6-42ec-a75d-fb18559f1b76 iid=493b4803-9202-4855-b087-702afda89fa7 mint_kid=97ed45b5-b5e6-42ec-a75d-fb18559f1b76 iss=493b4803-9202-4855-b087-702afda89fa7
 S06-030 — The ver claim comes from ai.aat.ver                                                       | t      | ver=2
 S06-031 — The aud claim comes from ai.aat.audience                                                  | t      | aud=clinic-portal
 S06-032 — Lifetime boundary: exp − iat exactly 600 seconds                                          | t      | delta=600 iat=1788708785 exp=1788709385
(16 rows)

 fail_if_any 
-------------
 
(1 row)

ROLLBACK
PASS  stage-06-happy-path-and-lifecycle.sql
== catalog SQL: stage-06-issuer-guards.sql ==
BEGIN
CREATE TABLE
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
                                   test_name                                   | passed |                                            detail                                             
-------------------------------------------------------------------------------+--------+-----------------------------------------------------------------------------------------------
 S06-001 — Anonymous role cannot execute the issuer at all                     | t      | sqlstate=42501 message=permission denied for function issue_ai_token issuance=0
 S06-002 — Authenticated role without JWT claims is UNAUTHENTICATED            | t      | sqlstate=P0001 message=UNAUTHENTICATED issuance=0
 S06-003 — Expired clinic session JWT is SESSION_EXPIRED                       | t      | sqlstate=P0001 message=SESSION_EXPIRED issuance=0
 S06-004 — Auth user with no staff row is STAFF_NOT_FOUND                      | t      | sqlstate=P0001 message=STAFF_NOT_FOUND issuance=0
 S06-005 — Deactivated staff member is STAFF_NOT_FOUND                         | t      | sqlstate=P0001 message=STAFF_NOT_FOUND active=false issuance=0
 S06-006 — Soft-deleted staff member is STAFF_NOT_FOUND                        | t      | sqlstate=P0001 message=STAFF_NOT_FOUND deleted=true issuance=0
 S06-007 — Bootstrap admin before clinic setup is BRANCH_NOT_FOUND             | t      | sqlstate=P0001 message=BRANCH_NOT_FOUND issuance=0
 S06-008 — Staff with no branch assignment is BRANCH_NOT_FOUND                 | t      | sqlstate=P0001 message=BRANCH_NOT_FOUND issuance=0 staff=c66b3776-5b09-4b9d-9aa5-9760e6284d44
 S06-009 — Staff whose only branch is inactive is BRANCH_NOT_FOUND             | t      | sqlstate=P0001 message=BRANCH_NOT_FOUND issuance=0
 S06-010 — Mint before any key is enrolled is INSTALLATION_NOT_ENROLLED        | t      | sqlstate=P0001 message=INSTALLATION_NOT_ENROLLED keys=0 issuance=0
 S06-011 — Mint when the only key is revoked is INSTALLATION_NOT_ENROLLED      | t      | sqlstate=P0001 message=INSTALLATION_NOT_ENROLLED issuance=0
 S06-012 — Mint when the only key is soft-deleted is INSTALLATION_NOT_ENROLLED | t      | sqlstate=P0001 message=INSTALLATION_NOT_ENROLLED issuance=0
 S06-013 — Minting at the per-actor ceiling is RATE_LIMITED (boundary)         | t      | sqlstate=P0001 message=RATE_LIMITED before=2 after=2
 S06-014 — The rate ceiling is per actor, not per installation                 | t      | compact=true sub=ee4cf588-fe9f-45a0-ae61-57bbaf824272 adm_rows=1
 S06-015 — Mints older than the window do not count                            | t      | compact=true before=2 after=3 fresh=1
 S06-016 — Rate check fires before the scope check                             | t      | sqlstate=P0001 message=RATE_LIMITED before=2 after=2
(16 rows)

 fail_if_any 
-------------
 
(1 row)

ROLLBACK
PASS  stage-06-issuer-guards.sql
== catalog SQL: stage-06-verify-and-handoff.sql ==
BEGIN
CREATE TABLE
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE TABLE
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
CREATE FUNCTION
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
DO
                                    test_name                                     | passed |                                                                                                       detail                                                                                                        
----------------------------------------------------------------------------------+--------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 S06-033 — Non-numeric rate-ceiling setting fails with an uncoded cast error      | t      | sqlstate=22023 msg=cannot cast jsonb string to type numeric issuance_before=0 issuance_after=0
 S06-034 — Clinic self-test verify_aat accepts a freshly minted token             | t      | verified=true alg=EdDSA kid_match=true iss_match=true auth_sqlstate=42501
 S06-035 — verify_aat rejects a tampered payload                                  | t      | verified=false role=administrator
 S06-036 — verify_aat rejects malformed tokens without throwing                   | t      | all six inputs returned false without exception
 S06-037 — verify_aat rejects alg ≠ EdDSA or a missing kid                        | t      | hs256=false missing_kid=false
 S06-038 — verify_aat rejects unknown and revoked kids                            | t      | revoked_kid_verify=false unknown_kid_verify=false rotated=9e74fd51-5393-477f-9fb6-90ac4fe31119
 S06-039 — verify_aat rejects an iss that does not match the key's installation   | t      | verified=false iss_ne_i0=true kid_match=true
 S06-040 — verify_aat does not evaluate exp                                       | t      | verified=true exp=1788708786 clock=1788708787 exp_lt_clock=true
 S06-041 — Minted-then-rejected: wrong audience                                   | t      | aud=clinic-portal iss_match=true compact_jws=true kid_in_keystore=true | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)
 S06-042 — Minted-then-rejected: expired AAT                                      | t      | clinic_verify=true exp=1788708786 exp_lt_clock=true | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)
 S06-043 — Default lifetime within platform cap: seed-default tokens are accepted | t      | exp_minus_iat=600 unexpired=true kid_active=true | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)
 S06-044 — Minted-then-rejected: kid unknown to the platform                      | t      | kid=478c0cdb-107b-4b02-bf9b-e929793e9ab8 kid_is_k1=true iss_match=true clinic_verify=true | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection); platform would reject unknown K1
 S06-045 — Minted-then-rejected: kid revoked platform-side                        | t      | mint_kid=981438e1-8280-4add-95b8-aa38c94b892a kid_was_k0=true after_revoke_verify=false | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)
 S06-046 — Minted-then-rejected: ver unknown or retired platform-side             | t      | ver=2 clinic_verify=true kid_active=true | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection)
 S06-047 — Minted-then-rejected: installation unknown to the platform             | t      | iss_match=true compact_jws=true kid_bound_to_i0=true | platform HTTP half is skipped — Register 5 #17 (Stage 7/9 execute identity rejection); minting does not register platform D1 state
(15 rows)

 fail_if_any 
-------------
 
(1 row)

ROLLBACK
PASS  stage-06-verify-and-handoff.sql
catalog SQL harness: 6 passed, 0 failed.
```
