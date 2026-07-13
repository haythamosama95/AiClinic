import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_booking_summary_card.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_picker.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_form_layout.dart';

/// Step 1 of the book-appointment dialog: patient, branch, and doctor preference.
class AppointmentBookingStep1 extends StatelessWidget {
  const AppointmentBookingStep1({
    required this.branchId,
    required this.branches,
    required this.branchesLoading,
    required this.branchesError,
    required this.doctors,
    required this.selectedPatient,
    required this.selectedDoctorId,
    required this.canEdit,
    required this.canChangeBranch,
    required this.fallbackBranchName,
    required this.onPatientChanged,
    required this.onBranchChanged,
    required this.onDoctorChanged,
    this.patientError,
    this.branchError,
    this.notesField,
    super.key,
  });

  final String branchId;
  final List<BranchListItem> branches;
  final bool branchesLoading;
  final bool branchesError;
  final List<StaffListItem> doctors;
  final PatientListItem? selectedPatient;
  final String? selectedDoctorId;
  final bool canEdit;
  final bool canChangeBranch;
  final String? fallbackBranchName;
  final ValueChanged<PatientListItem?> onPatientChanged;
  final ValueChanged<String> onBranchChanged;
  final ValueChanged<String?> onDoctorChanged;
  final String? patientError;
  final String? branchError;
  final Widget? notesField;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final branchDoctors = doctors.where((doctor) => doctor.isAssignedToBranch(branchId)).length;
    final branchName = _branchLabel(branchId);
    final doctorLabel = _doctorLabel();
    final useTwoColumns = setupFormUseTwoColumns(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _InfoCard(colors: colors),
        const SizedBox(height: AppSpacing.space6),
        PatientPicker(
          branchId: branchId,
          scope: PatientListScope.allBranches,
          hint: 'Search by name or MRN.',
          value: selectedPatient,
          enabled: canEdit,
          requiredMark: true,
          validationError: patientError,
          onChanged: onPatientChanged,
          searchFieldKey: const Key('appointment_booking_patient_search'),
          clearButtonKey: const Key('patient_picker_clear'),
        ),
        const SizedBox(height: AppSpacing.space4),
        if (useTwoColumns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _branchFormField(context, colors)),
              const SizedBox(width: AppSpacing.space3),
              Expanded(child: _doctorField(context, colors, branchDoctors)),
            ],
          )
        else ...[
          _branchFormField(context, colors),
          const SizedBox(height: AppSpacing.space4),
          _doctorField(context, colors, branchDoctors),
        ],
        if (notesField != null) ...[
          const SizedBox(height: AppSpacing.space4),
          notesField!,
        ],
        if (branchId.isNotEmpty && selectedPatient != null) ...[
          const SizedBox(height: AppSpacing.space6),
          AppBookingSummaryCard(
            items: [
              AppBookingSummaryItem(icon: Icons.person_outline, label: 'Patient', value: selectedPatient!.fullName),
              AppBookingSummaryItem(icon: Icons.business_outlined, label: 'Branch', value: branchName),
              AppBookingSummaryItem(icon: Icons.medical_services_outlined, label: 'Preference', value: doctorLabel),
            ],
          ),
        ],
      ],
    );
  }

  Widget _branchFormField(BuildContext context, AppSemanticColors colors) {
    return AppFormField(
      id: 'book_appointment_branch',
      label: 'Branch',
      requiredMark: true,
      error: branchError,
      hint: 'Only active branches with scheduling are listed.',
      child: _branchField(context, colors),
    );
  }

  Widget _doctorField(BuildContext context, AppSemanticColors colors, int branchDoctors) {
    if (doctors.isNotEmpty) {
      return AppointmentDoctorSelector(
        key: const Key('doctor_selector'),
        branchId: branchId,
        doctors: doctors,
        value: selectedDoctorId,
        enabled: canEdit && branchId.isNotEmpty,
        hint: branchId.isEmpty
            ? 'Select a branch first.'
            : '$branchDoctors doctor${branchDoctors == 1 ? '' : 's'} schedule at this branch.',
        onChanged: onDoctorChanged,
      );
    }

    return AppFormField(
      id: 'book_appointment_doctor',
      label: 'Preferred doctor',
      hint: branchId.isEmpty ? 'Select a branch first.' : 'Any available doctor',
      child: Text(
        branchId.isEmpty
            ? 'Select a branch first.'
            : 'No active doctors are configured. You can still book without a preferred doctor.',
        style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
      ),
    );
  }

  Widget _branchField(BuildContext context, AppSemanticColors colors) {
    if (branchesLoading) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (branches.isEmpty) {
      return Text(
        fallbackBranchName?.trim().isNotEmpty == true ? fallbackBranchName!.trim() : 'Branch',
        style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
      );
    }

    return AppSelect(
      key: const Key('appointment_booking_branch'),
      options: [for (final branch in branches) AppSelectOption(value: branch.id, label: branch.name)],
      value: branchId,
      disabled: !canChangeBranch,
      placeholder: 'Select branch',
      onChanged: canChangeBranch ? onBranchChanged : null,
    );
  }

  String _branchLabel(String id) {
    final branch = branches.where((item) => item.id == id).firstOrNull;
    if (branch != null) {
      return branch.name;
    }
    return fallbackBranchName?.trim().isNotEmpty == true ? fallbackBranchName!.trim() : '—';
  }

  String _doctorLabel() {
    final doctorId = selectedDoctorId?.trim();
    if (doctorId == null || doctorId.isEmpty) {
      return 'Any doctor';
    }
    final doctor = doctors.where((item) => item.id == doctorId).firstOrNull;
    return doctor?.fullName ?? '—';
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.colors});

  final AppSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Text(
          'Start by choosing who is visiting and which branch they will attend. '
          'You can optionally name a preferred doctor — or leave that open to see every available slot.',
          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
