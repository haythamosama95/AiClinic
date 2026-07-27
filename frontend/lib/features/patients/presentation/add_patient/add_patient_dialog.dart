import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/add_patient_form_fields.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/duplicate_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_form_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_form_state.dart';

/// Add-patient registration dialog (web `AddPatientDialog`).
class AddPatientDialog extends ConsumerStatefulWidget {
  const AddPatientDialog({
    required this.open,
    required this.onOpenChange,
    required this.onSuccess,
    super.key,
  });

  final bool open;
  final ValueChanged<bool> onOpenChange;
  final ValueChanged<String> onSuccess;

  @override
  ConsumerState<AddPatientDialog> createState() => _AddPatientDialogState();
}

class _AddPatientDialogState extends ConsumerState<AddPatientDialog> {
  PatientFormArgs get _formArgs => PatientFormArgs.create;

  void _handleOpenChange(bool open) {
    if (!open) {
      ref.read(patientFormNotifierProvider(_formArgs).notifier).reset();
    }
    widget.onOpenChange(open);
  }

  Future<void> _handleSubmit() async {
    final outcome = await ref.read(patientFormNotifierProvider(_formArgs).notifier).submit();
    final patientId = outcome.patientId;
    if (!mounted || patientId == null) {
      return;
    }
    _handleOpenChange(false);
    widget.onSuccess(patientId);
  }

  Future<void> _handleRegisterAnyway() async {
    final outcome = await ref.read(patientFormNotifierProvider(_formArgs).notifier).submitAnyway();
    final patientId = outcome.patientId;
    if (!mounted || patientId == null) {
      return;
    }
    _handleOpenChange(false);
    widget.onSuccess(patientId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientFormNotifierProvider(_formArgs));
    final notifier = ref.read(patientFormNotifierProvider(_formArgs).notifier);
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final l10n = context.l10n;

    ref.listen<String?>(
      patientFormNotifierProvider(_formArgs).select((s) => s.pendingOpenPatientId),
      (previous, next) {
        if (next == null) {
          return;
        }
        _handleOpenChange(false);
        widget.onSuccess(next);
        notifier.clearPendingOpenPatient();
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppDialog(
          open: widget.open,
          onOpenChange: _handleOpenChange,
          title: l10n.patientsListAddPatient,
          description: l10n.addPatientDescription,
          size: AppDialogSize.lg,
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                variant: AppButtonVariant.secondary,
                disabled: state.submitting,
                onPressed: state.submitting ? null : () => _handleOpenChange(false),
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: AppSpacing.space2),
              AppButton(
                variant: AppButtonVariant.primary,
                loading: state.submitting,
                leadingIcon: const Icon(Icons.person_add, size: 16),
                onPressed: state.submitting ? null : _handleSubmit,
                child: Text(l10n.registerPatient),
              ),
            ],
          ),
          child: AddPatientFormFields(
            values: state.values,
            errors: state.errors,
            trimmedName: state.trimmedName,
            showPreview: state.showPreview,
            reducedMotion: reducedMotion,
            autoFocus: widget.open,
            onSubmit: _handleSubmit,
            onFieldChange: notifier.updateField,
          ),
        ),
        DuplicatePatientDialog(
          open: state.duplicateOpen,
          onOpenChange: notifier.setDuplicateOpen,
          candidates: state.duplicateCandidates,
          loading: state.submitting,
          onRegisterAnyway: _handleRegisterAnyway,
          onOpenPatient: notifier.openExistingPatient,
        ),
      ],
    );
  }
}
