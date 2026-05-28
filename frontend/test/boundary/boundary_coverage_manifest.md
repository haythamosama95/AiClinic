# Boundary coverage manifest

Columns: `scenario` | `type` | `error_code` | `owner` | `backend_ref`

Only rows with `owner=boundary` must have `ManifestScenario('scenario')` in `test/boundary/**`.

| scenario                                                | type       | error_code             | owner    | backend_ref                                      |
| ------------------------------------------------------- | ---------- | ---------------------- | -------- | ------------------------------------------------ |
| auth.signIn.success                                     | happy      |                        | boundary | auth_flow_smoke.sh                               |
| auth.signIn.wrongPassword                               | negative   |                        | boundary |                                                  |
| auth.signIn.emptyCredentials                            | negative   |                        | boundary |                                                  |
| auth.signOut.clearsSession                              | happy      |                        | boundary |                                                  |
| auth.refreshSession.afterBootstrap                      | happy      |                        | boundary |                                                  |
| auth.clearPersistedSessionOnColdStart                   | happy      |                        | boundary |                                                  |
| auth.aggressive.signOutThenRpc                          | aggressive | FORBIDDEN              | boundary |                                                  |
| auth.aggressive.switchUser                              | aggressive |                        | boundary |                                                  |
| bootstrap.createOrganization.createBranch.success       | happy      |                        | boundary | bootstrap_rpc.sql                                |
| bootstrap.resetInstallation.success                     | happy      |                        | boundary | dev_reset_clinic_installation.sql                |
| bootstrap.INVALID_INPUT.emptyOrgName                    | negative   | INVALID_INPUT          | boundary | bootstrap_rpc.sql                                |
| bootstrap.ORG_ALREADY_EXISTS                            | negative   | ORG_ALREADY_EXISTS     | boundary | bootstrap_rpc.sql                                |
| bootstrap.ORG_NOT_FOUND.branchBeforeOrg                 | negative   | ORG_NOT_FOUND          | boundary | bootstrap_rpc.sql                                |
| bootstrap.NOT_BOOTSTRAP_ADMIN.resetDenied               | negative   | NOT_BOOTSTRAP_ADMIN    | boundary | dev_reset_safety.sql                             |
| bootstrap.FORBIDDEN.resetProduction                     | aggressive | FORBIDDEN              | boundary | dev_reset_safety.sql                             |
| provisioning.createStaffAccount.success                 | happy      |                        | boundary | create_staff_rpc.sql                             |
| provisioning.createStaffAccount.perRole.owner           | happy      |                        | boundary | create_staff_rpc.sql                             |
| provisioning.createStaffAccount.perRole.administrator   | happy      |                        | boundary | create_staff_rpc.sql                             |
| provisioning.createStaffAccount.perRole.doctor          | happy      |                        | boundary | create_staff_rpc.sql                             |
| provisioning.createStaffAccount.perRole.receptionist    | happy      |                        | boundary | create_staff_rpc.sql                             |
| provisioning.createStaffAccount.perRole.lab_staff       | happy      |                        | boundary | create_staff_rpc.sql                             |
| provisioning.FORBIDDEN.generic                          | negative   | FORBIDDEN              | boundary | create_staff_rpc.sql                             |
| provisioning.INVALID_INPUT.username                     | negative   | INVALID_INPUT          | boundary | create_staff_rpc.sql                             |
| provisioning.INVALID_INPUT.password                     | negative   | INVALID_INPUT          | boundary | create_staff_rpc.sql                             |
| provisioning.INVALID_INPUT.fullName                     | negative   | INVALID_INPUT          | boundary | create_staff_rpc.sql                             |
| provisioning.INVALID_INPUT.emptyBranches                | negative   | INVALID_INPUT          | boundary | create_staff_rpc.sql                             |
| provisioning.resetStaffPassword.FORBIDDEN               | negative   | FORBIDDEN              | boundary | admin_reset_staff_password.sql                   |
| provisioning.resetStaffPassword.INVALID_INPUT           | negative   | INVALID_INPUT          | boundary | admin_reset_staff_password.sql                   |
| provisioning.aggressive.emptyBranchListServer           | aggressive | INVALID_INPUT          | boundary | create_staff_rpc.sql                             |
| provisioning.aggressive.primaryBranchNullVsSet          | aggressive |                        | boundary | create_staff_rpc.sql                             |
| provisioning.resetStaffPassword.success                 | happy      |                        | boundary | admin_reset_staff_password.sql                   |
| provisioning.listOrgStaffMembers                        | happy      |                        | boundary |                                                  |
| provisioning.listBranchesByIds.empty                    | happy      |                        | boundary |                                                  |
| provisioning.listBranchesByIds.validAndMissing          | happy      |                        | boundary |                                                  |
| provisioning.ORG_SETUP_INCOMPLETE                       | negative   | ORG_SETUP_INCOMPLETE   | boundary | create_staff_rpc.sql                             |
| provisioning.USERNAME_EXISTS                            | negative   | USERNAME_EXISTS        | boundary | create_staff_rpc.sql                             |
| provisioning.WEAK_PASSWORD                              | negative   | WEAK_PASSWORD          | boundary | create_staff_rpc.sql                             |
| provisioning.INVALID_BRANCH                             | negative   | INVALID_BRANCH         | boundary | create_staff_rpc.sql                             |
| provisioning.FORBIDDEN_OWNER_CREATE                     | negative   | FORBIDDEN_OWNER_CREATE | boundary | create_staff_rpc.sql                             |
| provisioning.resetStaffPassword.STAFF_NOT_FOUND         | negative   | STAFF_NOT_FOUND        | boundary | admin_reset_staff_password.sql                   |
| permission.loadGrantedPermissions.owner                 | happy      |                        | boundary |                                                  |
| permission.loadGrantedPermissions.administrator         | happy      |                        | boundary |                                                  |
| permission.loadGrantedPermissions.doctor                | happy      |                        | boundary |                                                  |
| permission.loadGrantedPermissions.receptionist          | happy      |                        | boundary |                                                  |
| permission.loadGrantedPermissions.lab_staff             | happy      |                        | boundary |                                                  |
| permission.aggressive.revokeShrinksGrants               | aggressive |                        | boundary | patient_management_roles.sql                     |
| sessionContext.load.afterSignIn                         | happy      |                        | boundary | jwt_claims_contract.sql                          |
| sessionContext.refreshSession.reloadClaims              | happy      |                        | boundary |                                                  |
| sessionContext.inactiveStaff                            | negative   |                        | boundary |                                                  |
| sessionContext.multiBranchPrimary                       | happy      |                        | boundary |                                                  |
| sessionContext.setupRequired                            | happy      |                        | boundary | jwt_claims_contract.sql                          |
| sessionContext.missingStaffMemberIdClaim                | negative   |                        | boundary |                                                  |
| sessionContext.aggressive.refreshThenLoad               | aggressive |                        | boundary |                                                  |
| organization.fetchProfile.success                       | happy      |                        | boundary | org_branch_management_crud.sql                   |
| organization.fetchProfile.nullUnknown                   | happy      |                        | boundary |                                                  |
| organization.updateOrganization.success                 | happy      |                        | boundary | org_branch_management_crud.sql                   |
| organization.INVALID_INPUT.client                       | negative   | INVALID_INPUT          | boundary |                                                  |
| organization.FORBIDDEN.update                           | negative   | FORBIDDEN              | boundary | org_branch_management_crud.sql                   |
| branch.listBranches.allActiveInactive                   | happy      |                        | boundary |                                                  |
| branch.listBranches.activeOnly                          | happy      |                        | boundary |                                                  |
| branch.listBranches.inactiveOnly                        | happy      |                        | boundary |                                                  |
| branch.createBranch.success                             | happy      |                        | boundary | org_branch_management_crud.sql                   |
| branch.updateBranch.success                             | happy      |                        | boundary |                                                  |
| branch.updateBranch.fullOptional                        | happy      |                        | boundary |                                                  |
| branch.BRANCH_NOT_FOUND                                 | negative   | BRANCH_NOT_FOUND       | boundary | org_branch_management_rls.sql                    |
| branch.setBranchActive.deactivateNonLast                | happy      |                        | boundary |                                                  |
| branch.DUPLICATE_CODE                                   | negative   | DUPLICATE_CODE         | boundary | org_branch_management_crud.sql                   |
| branch.INVALID_INPUT.client                             | negative   | INVALID_INPUT          | boundary |                                                  |
| branch.LAST_ACTIVE_BRANCH                               | negative   | LAST_ACTIVE_BRANCH     | boundary | org_branch_management_crud.sql                   |
| branch.FORBIDDEN.receptionistCreate                     | negative   | FORBIDDEN              | boundary | org_branch_management_extended.sql               |
| staffAdmin.listStaff.filters                            | happy      |                        | boundary |                                                  |
| staffAdmin.fetchStaffMember.nested                      | happy      |                        | boundary |                                                  |
| staffAdmin.updateStaffMember.success                    | happy      |                        | boundary |                                                  |
| staffAdmin.setStaffActive.success                       | happy      |                        | boundary |                                                  |
| staffAdmin.organizationHasOwner                         | happy      |                        | boundary |                                                  |
| staffAdmin.organizationHasOwner.false                   | happy      |                        | boundary |                                                  |
| staffAdmin.INVALID_INPUT.emptyName                      | negative   | INVALID_INPUT          | boundary |                                                  |
| staffAdmin.INVALID_INPUT.emptyBranches                  | negative   | INVALID_INPUT          | boundary |                                                  |
| staffAdmin.FORBIDDEN_OWNER_CREATE                       | negative   | FORBIDDEN_OWNER_CREATE | boundary | org_branch_management_crud.sql                   |
| staffAdmin.FORBIDDEN.lastOwner                          | negative   | LAST_OWNER             | boundary | org_branch_management_crud.sql                   |
| staffAdmin.STAFF_NOT_FOUND                              | negative   | STAFF_NOT_FOUND        | boundary | org_branch_management_rls.sql                    |
| staffAdmin.INVALID_BRANCH                               | negative   | INVALID_BRANCH         | boundary | org_branch_management_crud.sql                   |
| staffAdmin.aggressive.crossOrgStaff                     | aggressive | CROSS_ORG_DENIED       | boundary | org_branch_management_rls.sql                    |
| rolePermissions.fetchMatrix.success                     | happy      |                        | boundary |                                                  |
| rolePermissions.updateRolePermission.grant              | happy      |                        | boundary |                                                  |
| rolePermissions.updateRolePermission.revoke             | happy      |                        | boundary |                                                  |
| rolePermissions.INVALID_PERMISSION                      | negative   | INVALID_PERMISSION     | boundary |                                                  |
| rolePermissions.FORBIDDEN.nonOwner                      | negative   | FORBIDDEN              | boundary | auth_rbac_extended.sql                           |
| rolePermissions.INVALID_INPUT.emptyKey                  | negative   |                        | boundary |                                                  |
| patients.searchPatients.branchName                      | happy      |                        | boundary | patient_management_search_advanced.sql           |
| patients.searchPatients.branchPhone                     | happy      |                        | boundary | patient_management_search_advanced.sql           |
| patients.searchPatients.INVALID_INPUT                   | negative   | INVALID_INPUT          | boundary | patient_management_search_advanced.sql           |
| patients.searchPatients.orgScope                        | happy      |                        | boundary |                                                  |
| patients.searchPatients.emptyBrowse                     | happy      |                        | boundary |                                                  |
| patients.searchPatients.pagination                      | happy      |                        | boundary |                                                  |
| patients.searchPatients.BRANCH_REQUIRED                 | negative   | BRANCH_REQUIRED        | boundary | patient_management_crud.sql                      |
| patients.getPatient.success                             | happy      |                        | boundary |                                                  |
| patients.getPatient.NOT_FOUND                           | negative   | NOT_FOUND              | boundary | patient_management_rls.sql                       |
| patients.getPatient.PATIENT_ARCHIVED                    | negative   | PATIENT_ARCHIVED       | boundary | patient_management_crud.sql                      |
| patients.getPatient.crossOrgNOT_FOUND                   | aggressive | NOT_FOUND              | boundary | patient_management_rls.sql                       |
| patients.getPatient.INVALID_INPUT.client                | negative   | INVALID_INPUT          | boundary |                                                  |
| patients.checkDuplicates.success                        | happy      |                        | boundary |                                                  |
| patients.checkDuplicates.INVALID_INPUT                  | negative   | INVALID_INPUT          | boundary | patient_management_extended.sql                  |
| patients.createPatient.minimal                          | happy      |                        | boundary | patient_management_crud.sql                      |
| patients.createPatient.fullDemographics                 | happy      |                        | boundary |                                                  |
| patients.createPatient.INVALID_INPUT.name               | negative   | INVALID_INPUT          | boundary |                                                  |
| patients.createPatient.INVALID_INPUT.phone              | negative   | INVALID_INPUT          | boundary |                                                  |
| patients.createPatient.FORBIDDEN                        | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.createPatient.DUPLICATE_WARNING                | negative   | DUPLICATE_WARNING      | boundary | patient_management_crud.sql                      |
| patients.createPatient.acknowledgeDuplicate             | happy      |                        | boundary |                                                  |
| patients.updatePatient.success                          | happy      |                        | boundary | patient_management_crud.sql                      |
| patients.updatePatient.acknowledgeDuplicate             | happy      |                        | boundary | patient_management_crud.sql                      |
| patients.updatePatient.DUPLICATE_WARNING                | negative   | DUPLICATE_WARNING      | boundary | patient_management_crud.sql                      |
| patients.updatePatient.STALE_PATIENT                    | negative   | STALE_PATIENT          | boundary | patient_management_crud.sql                      |
| patients.updatePatient.PATIENT_ARCHIVED                 | negative   | PATIENT_ARCHIVED       | boundary | patient_management_extended.sql                  |
| patients.updatePatient.NOT_FOUND                        | negative   | NOT_FOUND              | boundary | patient_management_extended.sql                  |
| patients.updatePatient.FORBIDDEN                        | negative   | FORBIDDEN              | boundary | patient_management_crud.sql                      |
| patients.archivePatient.success                         | happy      |                        | boundary |                                                  |
| patients.archivePatient.FORBIDDEN.receptionist          | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.archivePatient.FORBIDDEN.lab                   | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.archivePatient.NOT_FOUND                       | negative   | NOT_FOUND              | boundary | patient_management_crud.sql                      |
| patients.archivePatient.crossOrgNOT_FOUND               | aggressive | NOT_FOUND              | boundary | patient_management_rls.sql                       |
| patients.aggressive.concurrentDuplicatePhone            | aggressive | DUPLICATE_PHONE        | boundary | patient_management_concurrent.sql                |
| patients.revoke.create.FORBIDDEN                        | aggressive | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.revoke.view.search.FORBIDDEN                   | aggressive | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.revoke.view.get.FORBIDDEN                      | aggressive | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.revoke.create.afterRevokeRestore               | aggressive |                        | boundary | patient_management_roles.sql                     |
| patients.revoke.view.checkDuplicates.FORBIDDEN          | aggressive | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.revoke.edit.update.FORBIDDEN                   | aggressive | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patients.revoke.delete.archive.FORBIDDEN                | aggressive | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patientRole.owner.search                                | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.owner.create                                | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.owner.get                                   | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.owner.update                                | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.owner.checkDuplicates                       | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.owner.archive                               | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.administrator.search                        | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.administrator.create                        | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.administrator.get                           | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.administrator.update                        | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.administrator.checkDuplicates               | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.administrator.archive                       | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.doctor.search                               | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.doctor.create                               | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.doctor.get                                  | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.doctor.update                               | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.doctor.checkDuplicates                      | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.doctor.archive                              | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.receptionist.search                         | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.receptionist.create                         | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.receptionist.get                            | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.receptionist.update                         | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.receptionist.checkDuplicates                | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.receptionist.archive                        | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.lab_staff.search                            | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.lab_staff.create                            | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patientRole.lab_staff.get                               | happy      |                        | boundary | patient_management_roles.sql                     |
| patientRole.lab_staff.update                            | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patientRole.lab_staff.checkDuplicates                   | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| patientRole.lab_staff.archive                           | negative   | FORBIDDEN              | boundary | patient_management_roles.sql                     |
| postgrest.staff_members.read                            | happy      |                        | boundary |                                                  |
| postgrest.branches.read                                 | happy      |                        | boundary |                                                  |
| postgrest.organizations.read                            | happy      |                        | boundary |                                                  |
| postgrest.roles_permissions.read                        | happy      |                        | boundary |                                                  |
| postgrest.staff_branch_assignments.read                 | happy      |                        | boundary |                                                  |
| postgrest.aggressive.foreignOrgBranchesEmpty            | aggressive |                        | boundary | org_branch_management_rls.sql                    |
| postgrest.staff_members.rlsDenied                       | aggressive |                        | boundary |                                                  |
| postgrest.branches.rlsDenied                            | aggressive |                        | boundary |                                                  |
| postgrest.organizations.rlsDenied                       | aggressive |                        | boundary |                                                  |
| postgrest.roles_permissions.rlsDenied                   | aggressive |                        | boundary |                                                  |
| postgrest.staffMemberDetail.nestedShape                 | happy      |                        | boundary |                                                  |
| postgrest.aggressive.crossOrgPatientInvisible           | aggressive |                        | boundary | patient_management_rls.sql                       |
| patients.PGRST202.missingRpc                            | negative   | RPC_NOT_APPLIED        | unit     | patient_repository_postgrest_error_test.dart     |
| patients.malformed.successPayload                       | negative   |                        | unit     | patient_repository_get_test.dart                 |
| appointments.getSettings.success                        | happy      |                        | boundary | appointment_management_grants.sql                |
| appointments.createAppointment.planned.success          | happy      |                        | boundary | appointment_management_crud.sql                  |
| appointments.createAppointment.SCHEDULE_CONFLICT        | negative   | SCHEDULE_CONFLICT      | boundary | appointment_management_crud.sql                  |
| appointments.createAppointment.planned.noDoctor         | happy      |                        | boundary | appointment_management_crud.sql                  |
| appointments.createAppointment.FORBIDDEN.lab_staff      | negative   | FORBIDDEN              | boundary | appointment_management_crud.sql                  |
| appointments.getSettings.FORBIDDEN.lab_staff            | negative   | FORBIDDEN              | boundary | appointment_management_crud.sql                  |
| appointments.getSettings.FORBIDDEN.unauthenticated      | negative   | FORBIDDEN              | boundary |                                                  |
| appointments.updateAppointmentStatus.lifecycle.success  | happy      |                        | boundary | appointment_management_crud.sql                  |
| appointments.updateAppointmentStatus.INVALID_TRANSITION | negative   | INVALID_TRANSITION     | boundary | appointment_management_crud.sql                  |
| appointments.PGRST202.missingRpc                        | negative   | RPC_NOT_APPLIED        | unit     | appointment_repository_postgrest_error_test.dart |
| appointments.grants.authInternalExecute                 | happy      |                        | backend  | appointment_management_grants.sql                |
| appointments.PostgREST.42501.authInternalDenied         | negative   | RPC_NOT_CONFIGURED     | unit     | appointment_repository_postgrest_error_test.dart |
