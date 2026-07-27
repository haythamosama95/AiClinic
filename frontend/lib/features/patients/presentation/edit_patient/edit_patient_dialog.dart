import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_dialog.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/components/app_skeletonizer_zone.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/add_patient_form_fields.dart';
import 'package:ai_clinic/features/patients/presentation/add_patient/duplicate_patient_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_form_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_form_state.dart';

/// Edit-patient dialog (synthesized from the add-patient flow).
class EditPatientDialog extends ConsumerStatefulWidget {
  const EditPatientDialog({required this.patientId, super.key});

  final String patientId;

  @override
  ConsumerState<EditPatientDialog> createState() => _EditPatientDialogState();
}

class _EditPatientDialogState extends ConsumerState<EditPatientDialog> {
  PatientFormArgs get _formArgs => PatientFormArgs.edit(patientId: widget.patientId);

  void _close() {
    ref.read(patientFormNotifierProvider(_formArgs).notifier).reset();
    Navigator.of(context).pop();
  }

  void _handleOpenChange(bool open) {
    if (!open) {
      _close();
    }
  }

  Future<void> _handleSubmit() async {
    final outcome = await ref.read(patientFormNotifierProvider(_formArgs).notifier).submit();
    if (!mounted || !outcome.succeeded) {
      return;
    }
    ref.invalidate(patientDetailProvider(widget.patientId));
    _close();
  }

  Future<void> _handleSaveAnyway() async {
    final outcome = await ref.read(patientFormNotifierProvider(_formArgs).notifier).submitAnyway();
    if (!mounted || !outcome.succeeded) {
      return;
    }
    ref.invalidate(patientDetailProvider(widget.patientId));
    _close();
  }

  void _handleStaleReload() {
    ref.read(patientFormNotifierProvider(_formArgs).notifier).confirmStaleReload();
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientFormNotifierProvider(_formArgs));
    final notifier = ref.read(patientFormNotifierProvider(_formArgs).notifier);
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    ref.listen<String?>(
      patientFormNotifierProvider(_formArgs).select((s) => s.pendingOpenPatientId),
      (previous, next) {
        if (next == null) {
          return;
        }
        _close();
        context.nav.pushPatientDetail(next);
        notifier.clearPendingOpenPatient();
      },
    );

    final identitySubtitle = state.showPreview ? '${context.l10n.editingSuffix} · ${state.trimmedName}' : null;
    final l10n = context.l10n;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppDialog(
          open: true,
          onOpenChange: _handleOpenChange,
          title: l10n.editPatient,
          description: l10n.editPatientDescription,
          size: AppDialogSize.lg,
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                variant: AppButtonVariant.secondary,
                disabled: state.submitting,
                onPressed: state.submitting ? null : _close,
                child: Text(l10n.cancel),
              ),
              const SizedBox(width: AppSpacing.space2),
              AppButton(
                variant: AppButtonVariant.primary,
                loading: state.submitting,
                leadingIcon: const Icon(Icons.save, size: 16),
                onPressed: state.submitting || !state.hydrated ? null : _handleSubmit,
                child: Text(l10n.saveChanges),
              ),
            ],
          ),
          child: state.hydrated
              ? AddPatientFormFields(
                  values: state.values,
                  errors: state.errors,
                  trimmedName: state.trimmedName,
                  showPreview: state.showPreview,
                  reducedMotion: reducedMotion,
                  autoFocus: true,
                  branchName: state.branchName,
                  branchBannerLabel: '${l10n.registeredAt} ',
                  identityPreviewSubtitle: identitySubtitle,
                  fieldIdPrefix: 'edit-patient',
                  onSubmit: _handleSubmit,
                  onFieldChange: notifier.updateField,
                )
              : const AppSkeletonizerZone(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSkeleton(variant: SkeletonVariant.rectangular, height: 44),
                      SizedBox(height: AppSpacing.space6),
                      AppSkeleton(variant: SkeletonVariant.rectangular, height: 72),
                      SizedBox(height: AppSpacing.space6),
                      AppSkeleton(variant: SkeletonVariant.rectangular, height: 220),
                    ],
                  ),
                ),
        ),
        DuplicatePatientDialog(
          open: state.duplicateOpen,
          onOpenChange: notifier.setDuplicateOpen,
          candidates: state.duplicateCandidates,
          loading: state.submitting,
          onRegisterAnyway: _handleSaveAnyway,
          onOpenPatient: notifier.openExistingPatient,
        ),
        AppDialog(
          open: state.staleUpdateOpen,
          onOpenChange: notifier.setStaleUpdateOpen,
          title: l10n.recordChangedTitle,
          description: l10n.recordChangedDescription,
          size: AppDialogSize.sm,
          barrierDismissible: false,
          footer: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                variant: AppButtonVariant.secondary,
                onPressed: () => notifier.setStaleUpdateOpen(false),
                child: Text(l10n.keepEditing),
              ),
              const SizedBox(width: AppSpacing.space2),
              AppButton(
                variant: AppButtonVariant.primary,
                onPressed: _handleStaleReload,
                child: Text(l10n.reload),
              ),
            ],
          ),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
