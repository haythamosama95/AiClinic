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
import 'package:ai_clinic/features/patients/presentation/providers/patient_edit_notifier.dart';

/// Edit-patient dialog (synthesized from the add-patient flow).
class EditPatientDialog extends ConsumerStatefulWidget {
  const EditPatientDialog({required this.patientId, super.key});

  final String patientId;

  @override
  ConsumerState<EditPatientDialog> createState() => _EditPatientDialogState();
}

class _EditPatientDialogState extends ConsumerState<EditPatientDialog> {
  var _exitCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromDetail());
  }

  void _hydrateFromDetail() {
    if (!mounted) {
      return;
    }
    final detail = ref
        .read(patientDetailProvider(widget.patientId))
        .asData
        ?.value;
    if (detail != null) {
      ref
          .read(patientEditProvider(widget.patientId).notifier)
          .preloadFromDetail(detail);
    }
  }

  void _completeExit() {
    if (_exitCompleted || !mounted) {
      return;
    }
    _exitCompleted = true;
    ref.read(patientEditProvider(widget.patientId).notifier).reset();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _dismissInnerOverlay() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _handleOpenChange(bool open) {
    if (!open) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeExit());
    }
  }

  Future<void> _handleSubmit() async {
    final success = await ref
        .read(patientEditProvider(widget.patientId).notifier)
        .submit();
    if (!mounted || !success) {
      return;
    }
    ref.invalidate(patientDetailProvider(widget.patientId));
    _dismissInnerOverlay();
  }

  Future<void> _handleSaveAnyway() async {
    final success = await ref
        .read(patientEditProvider(widget.patientId).notifier)
        .saveAnyway();
    if (!mounted || !success) {
      return;
    }
    ref.invalidate(patientDetailProvider(widget.patientId));
    _dismissInnerOverlay();
  }

  Future<void> _handleStaleReload() async {
    final notifier = ref.read(patientEditProvider(widget.patientId).notifier);
    notifier.confirmStaleReload();
    await ref.read(patientDetailProvider(widget.patientId).future);
    if (!mounted) {
      return;
    }
    notifier.setStaleUpdateOpen(false);
    Navigator.of(context, rootNavigator: true).pop();
    _dismissInnerOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(patientEditProvider(widget.patientId));
    final notifier = ref.read(patientEditProvider(widget.patientId).notifier);
    final reducedMotion = AppMotion.prefersReducedMotion(context);

    ref.listen<String?>(
      patientEditProvider(
        widget.patientId,
      ).select((s) => s.pendingOpenPatientId),
      (previous, next) {
        if (next == null) {
          return;
        }
        _dismissInnerOverlay();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          context.nav.pushPatientDetail(next);
          notifier.clearPendingOpenPatient();
        });
      },
    );

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
          footer: Consumer(
            builder: (context, ref, _) {
              final editState = ref.watch(patientEditProvider(widget.patientId));
              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    disabled: editState.submitting,
                    onPressed: editState.submitting ? null : _dismissInnerOverlay,
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  AppButton(
                    variant: AppButtonVariant.primary,
                    loading: editState.submitting,
                    leadingIcon: const Icon(Icons.save, size: 16),
                    onPressed: editState.submitting || !editState.hydrated
                        ? null
                        : _handleSubmit,
                    child: Text(l10n.saveChanges),
                  ),
                ],
              );
            },
          ),
          child: Consumer(
            builder: (context, ref, _) {
              final editState = ref.watch(patientEditProvider(widget.patientId));
              final editNotifier = ref.read(
                patientEditProvider(widget.patientId).notifier,
              );
              final identitySubtitle = editState.showPreview
                  ? '${context.l10n.editingSuffix} · ${editState.trimmedName}'
                  : null;

              if (!editState.hydrated) {
                return const AppSkeletonizerZone(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSkeleton(
                        variant: SkeletonVariant.rectangular,
                        height: 44,
                      ),
                      SizedBox(height: AppSpacing.space6),
                      AppSkeleton(
                        variant: SkeletonVariant.rectangular,
                        height: 72,
                      ),
                      SizedBox(height: AppSpacing.space6),
                      AppSkeleton(
                        variant: SkeletonVariant.rectangular,
                        height: 220,
                      ),
                    ],
                  ),
                );
              }

              return AddPatientFormFields(
                values: editState.values,
                errors: editState.errors,
                trimmedName: editState.trimmedName,
                showPreview: editState.showPreview,
                reducedMotion: reducedMotion,
                autoFocus: true,
                branchName: editState.branchName,
                branchBannerLabel: '${l10n.registeredAt} ',
                identityPreviewSubtitle: identitySubtitle,
                fieldIdPrefix: 'edit-patient',
                onSubmit: _handleSubmit,
                onFieldChange: editNotifier.updateField,
              );
            },
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
          title: 'Record changed',
          description:
              'This record was modified by someone else. Reload and discard your edits?',
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
                child: const Text('Reload'),
              ),
            ],
          ),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
