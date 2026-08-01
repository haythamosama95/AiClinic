import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/add_patient_form_fields.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/duplicate_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_registration_notifier.dart';

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
  void _handleOpenChange(bool open) {
    if (!open) {
      ref.read(patientRegistrationProvider.notifier).reset();
    }
    widget.onOpenChange(open);
  }

  Future<void> _handleSubmit() async {
    final result = await ref
        .read(patientRegistrationProvider.notifier)
        .submit();
    if (!mounted || result == null) {
      return;
    }
    appToast(
      context,
      AppToastInput(
        message: 'Patient created — MRN ${result.mrn}',
        variant: AppToastVariant.success,
      ),
    );
    _handleOpenChange(false);
    widget.onSuccess(result.patientId);
  }

  Future<void> _handleRegisterAnyway() async {
    final result = await ref
        .read(patientRegistrationProvider.notifier)
        .registerAnyway();
    if (!mounted || result == null) {
      return;
    }
    appToast(
      context,
      AppToastInput(
        message: 'Patient created — MRN ${result.mrn}',
        variant: AppToastVariant.success,
      ),
    );
    _handleOpenChange(false);
    widget.onSuccess(result.patientId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientRegistrationProvider);
    final notifier = ref.read(patientRegistrationProvider.notifier);
<<<<<<< HEAD
    final reducedMotion = AppMotion.prefersReducedMotion(context);
=======
>>>>>>> master

    ref.listen<String?>(
      patientRegistrationProvider.select((s) => s.pendingOpenPatientId),
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
          title: 'Add patient',
          description: 'Register a new patient at your active branch.',
          size: AppDialogSize.lg,
<<<<<<< HEAD
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                variant: AppButtonVariant.secondary,
                disabled: state.submitting,
                onPressed: state.submitting
                    ? null
                    : () => _handleOpenChange(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.space2),
              AppButton(
                variant: AppButtonVariant.primary,
                loading: state.submitting,
                leadingIcon: const Icon(Icons.person_add, size: 16),
                onPressed: state.submitting ? null : _handleSubmit,
                child: const Text('Register patient'),
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
=======
          footer: Consumer(
            builder: (context, ref, _) {
              final submitting = ref.watch(
                patientRegistrationProvider.select((state) => state.submitting),
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    disabled: submitting,
                    onPressed: submitting ? null : () => _handleOpenChange(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    loading: submitting,
                    leadingIcon: const Icon(Icons.person_add, size: 16),
                    onPressed: submitting ? null : _handleSubmit,
                    child: const Text('Register patient'),
                  ),
                ],
              );
            },
          ),
          child: Consumer(
            builder: (context, ref, _) {
              final registrationState = ref.watch(patientRegistrationProvider);
              final registrationNotifier = ref.read(
                patientRegistrationProvider.notifier,
              );
              return AddPatientFormFields(
                values: registrationState.values,
                errors: registrationState.errors,
                trimmedName: registrationState.trimmedName,
                showPreview: registrationState.showPreview,
                reducedMotion: AppMotion.prefersReducedMotion(context),
                autoFocus: widget.open,
                onSubmit: _handleSubmit,
                onFieldChange: registrationNotifier.updateField,
              );
            },
>>>>>>> master
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
