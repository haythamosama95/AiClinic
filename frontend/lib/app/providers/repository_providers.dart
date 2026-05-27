// Re-exports for cross-feature repository provider access.
//
// Features that need access to repositories from other features should import
// from here rather than reaching into `features/*/data/` directly.
export 'package:ai_clinic/features/settings/data/branch_repository.dart' show branchRepositoryProvider;
export 'package:ai_clinic/features/settings/data/staff_admin_repository.dart' show staffAdminRepositoryProvider;
export 'package:ai_clinic/features/patients/data/patient_repository.dart' show patientRepositoryProvider;
