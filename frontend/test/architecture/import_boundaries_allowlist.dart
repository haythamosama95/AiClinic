/// Sanctioned import-boundary exceptions.
///
/// Each key is `'<posix lib-relative path>|<imported uri>'`.
/// Each value documents why the exception exists and which finding will remove it.
const Map<String, String> importBoundaryAllowlist = {
  // Rule 1 — core must not import features
  'lib/core/auth/auth_route_guard.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Core auth guard uses AuthSession until auth domain types move to core/domain',
  'lib/core/auth/auth_route_guard.dart|package:ai_clinic/features/auth/domain/permission_keys.dart':
      'Core auth guard uses permission keys until auth domain types move to core/domain',
  'lib/core/auth/permission_service.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Core permission service uses AuthSession until auth domain types move to core/domain',
  'lib/core/auth/permission_service.dart|package:ai_clinic/features/auth/domain/permission_keys.dart':
      'Core permission service uses permission keys until auth domain types move to core/domain',
  'lib/core/domain/clinic/staff_list_item.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'M5 — StaffRole should move to core/domain before this import is removed',
  'lib/core/ui/components/app_command_bar.dart|package:ai_clinic/features/design_system/presentation/providers/command_bar_controller.dart':
      'Design-system showcase coupling; extract command-bar controller to core/ui',
  'lib/core/ui/components/app_top_bar.dart|package:ai_clinic/features/design_system/presentation/providers/command_bar_controller.dart':
      'Design-system showcase coupling; extract command-bar controller to core/ui',
  'lib/core/ui/components/app_user_menu.dart|package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart':
      'Design-system showcase coupling; extract dev preview provider to core/ui',

  // Rule 2 — domain must not import other features
  'lib/features/appointments/domain/appointment_fetch_scope.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'M5 — deliberate until StaffRole moves to core/domain',
  'lib/features/appointments/domain/appointment_queue_shift_doctors.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'M5 — deliberate until StaffRole moves to core/domain',
  'lib/features/appointments/domain/appointment_queue_shift_doctors.dart|package:ai_clinic/features/shifts/domain/shift_list_item.dart':
      'M5 — deliberate until ShiftListItem moves to core/domain',
  'lib/features/appointments/domain/appointment_queue_shift_doctors.dart|package:ai_clinic/features/shifts/domain/shift_status.dart':
      'M5 — deliberate until shift vocabulary moves to core/domain',
  'lib/features/appointments/domain/appointment_shift_doctor_resolution.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'C3 — doctor resolution uses auth session until shared clinic types move to core/domain',
  'lib/features/appointments/domain/appointment_shift_doctor_resolution.dart|package:ai_clinic/features/shifts/domain/shift_branch_staff.dart':
      'C3 — doctor resolution uses shift staff until shared clinic types move to core/domain',
  'lib/features/appointments/domain/appointment_shift_doctor_resolution.dart|package:ai_clinic/features/shifts/domain/shift_list_item.dart':
      'C3 — doctor resolution uses shift list items until shared clinic types move to core/domain',
  'lib/features/appointments/domain/appointment_booking_patient.dart|package:ai_clinic/features/patients/domain/patient_list_item.dart':
      'Appointments booking uses patient list item until shared patient summary type exists in core/domain',
  'lib/features/clinic-management/domain/permission_matrix_row.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/clinic-management/domain/permission_matrix_view.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/clinic-management/domain/repositories/role_permissions_repository.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/clinic-management/domain/staff_list_query.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/clinic-management/domain/staff_member_detail.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/clinic-management/domain/update_staff_member_input.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/clinic-management/domain/usecases/update_role_permission.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Clinic-management domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/patients/domain/patient_visit_document.dart|package:ai_clinic/features/visits/domain/visit_attachment_item.dart':
      'Patients domain references visit attachment DTO until shared patient-visit types exist',
  'lib/features/service_catalog/domain/effective_price.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Service-catalog domain shares Money value type with billing until core/domain/money exists',
  'lib/features/service_catalog/domain/eligible_service.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Service-catalog domain shares Money value type with billing until core/domain/money exists',
  'lib/features/service_catalog/domain/service.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Service-catalog domain shares Money value type with billing until core/domain/money exists',
  'lib/features/service_catalog/domain/service_branch_config.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Service-catalog domain shares Money value type with billing until core/domain/money exists',
  'lib/features/service_catalog/domain/service_list_item.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Service-catalog domain shares Money value type with billing until core/domain/money exists',
  'lib/features/service_catalog/domain/service_promotion.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Service-catalog domain shares Money value type with billing until core/domain/money exists',
  'lib/features/settings/domain/provisioning_rules.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Settings domain uses StaffRole from auth until shared types move to core/domain',
  'lib/features/setup/domain/clinic_setup_draft_mapper.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/clinic_setup_draft_mapper.dart|package:ai_clinic/features/auth/domain/staff_username.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/clinic_setup_draft_mapper.dart|package:ai_clinic/features/clinic-management/domain/organization_profile.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/clinic_setup_draft_mapper.dart|package:ai_clinic/features/service_catalog/domain/service_list_item.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/create_staff_account_input.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/auth/domain/staff_username.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/billing/domain/money.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/clinic-management/domain/create_branch_input.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/clinic-management/domain/update_branch_input.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/clinic-management/domain/update_organization_input.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/clinic-management/domain/update_staff_member_input.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/persist_clinic_setup_draft.dart|package:ai_clinic/features/service_catalog/domain/service_list_item.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/setup/domain/staff_member_summary.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Setup orchestration crosses feature domains until setup use cases are isolated',
  'lib/features/shifts/domain/shift_branch_staff.dart|package:ai_clinic/features/auth/domain/auth_session.dart':
      'Shifts domain uses StaffRole from auth until shared types move to core/domain',

  // Rule 3 — domain must not import UI, framework, or infrastructure
  'lib/features/appointments/domain/appointment_booking_slots.dart|package:ai_clinic/core/ui/models/booking_slot.dart':
      'H2 — BookingSlot should live in core/domain or appointments/domain, not core/ui',
  'lib/features/auth/domain/repositories/auth_repository.dart|package:supabase_flutter/supabase_flutter.dart':
      'Auth repository interface leaks Supabase types until abstracted behind core/data',
  'lib/features/clinic-management/domain/usecases/clinic_management_use_case_providers.dart|package:flutter_riverpod/flutter_riverpod.dart':
      'Riverpod providers in domain/usecases until moved to application or presentation',
  'lib/features/patients/domain/usecases/patient_use_case_providers.dart|package:flutter_riverpod/flutter_riverpod.dart':
      'Riverpod providers in domain/usecases until moved to application or presentation',
  'lib/features/setup/domain/usecases/setup_use_case_providers.dart|package:flutter_riverpod/flutter_riverpod.dart':
      'Riverpod providers in domain/usecases until moved to application or presentation',
  'lib/features/visits/domain/encounter_phase.dart|package:flutter/material.dart':
      'Visits domain uses IconData until presentation mapping is extracted',

  // Rule 4 — features must not import other features data layer
  'lib/features/appointments/presentation/providers/appointment_shift_lookup_provider.dart|package:ai_clinic/features/shifts/data/shift_repository.dart':
      'M1 — shift lookup should go through appointments application/domain layer',
  'lib/features/billing/application/appointment_invoice_summary_service.dart|package:ai_clinic/features/visits/data/visit_repository.dart':
      'Billing application reaches visits data directly until visit summary port exists',
  'lib/features/billing/presentation/providers/invoice_editor_notifier.dart|package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart':
      'Billing notifier reaches service-catalog data until shared application service exists',

  // Rule 5 — features must not import other features presentation providers
  'lib/features/auth/presentation/widgets/clinic_setup_welcome_scope.dart|package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart':
      'Auth welcome scope couples to setup notifier until orchestration moves to app layer',
  'lib/features/patients/presentation/pages/patient_detail_page.dart|package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart':
      'Patients page couples to billing provider until patient-detail orchestration exists',
  'lib/features/billing/presentation/widgets/patient_invoice_card.dart|package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart':
      'Billing patient invoice card couples to clinic-management providers until shared app providers exist',

  // Rule 6 — data must not import presentation in the same feature
};
