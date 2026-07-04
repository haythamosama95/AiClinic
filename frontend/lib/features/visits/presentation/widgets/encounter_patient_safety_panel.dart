import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Patient safety context — allergies, medications, conditions (014 US6).
class EncounterPatientSafetyPanel extends ConsumerWidget {
  const EncounterPatientSafetyPanel({
    required this.visitId,
    required this.patientId,
    required this.canEdit,
    super.key,
  });

  final String visitId;
  final String patientId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safetyAsync = ref.watch(patientSafetyProvider(patientId));
    final docState = ref.watch(visitDocumentationProvider(visitId)).value;

    return safetyAsync.when(
      loading: () => const Center(child: AppSpinner()),
      error: (error, _) => AppErrorState(
        message: error.toString(),
        onRetry: () => ref.invalidate(patientSafetyProvider(patientId)),
      ),
      data: (base) {
        final safety = docState?.effectivePatientSafety(base) ?? base;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SafetySection(
              title: 'Allergies',
              emptyMessage: 'No known allergies recorded.',
              lines: [
                for (final allergy in safety.allergies)
                  _formatAllergy(allergy),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            _SafetySection(
              title: 'Current medications',
              emptyMessage: 'No current medications recorded.',
              lines: [
                for (final med in safety.currentMedications) _formatMedication(med),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            _SafetySection(
              title: 'Chronic conditions',
              emptyMessage: 'No chronic conditions recorded.',
              lines: [
                for (final condition in safety.chronicConditions) _formatCondition(condition),
              ],
            ),
            if (!safety.lastVitals.isEmpty) ...[
              const SizedBox(height: AppSpacing.s4),
              _SafetySection(
                title: 'Last visit vitals',
                emptyMessage: '',
                lines: [
                  for (final vital in safety.lastVitals.items)
                    '${vital.name}: ${vital.value}${vital.unit != null ? ' ${vital.unit}' : ''}',
                ],
              ),
            ],
            if (canEdit) ...[
              const SizedBox(height: AppSpacing.s4),
              AppButton(
                label: 'Add allergy',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: LucideIcons.plus,
                onPressed: () => _showAddAllergy(context, ref),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _formatAllergy(PatientAllergy allergy) {
    if (allergy.reaction != null && allergy.reaction!.trim().isNotEmpty) {
      return '${allergy.substance} · ${allergy.reaction}';
    }
    return allergy.substance;
  }

  static String _formatMedication(PatientMedication med) {
    if (med.note != null && med.note!.trim().isNotEmpty) {
      return '${med.name} · ${med.note}';
    }
    return med.name;
  }

  static String _formatCondition(PatientChronicCondition condition) {
    if (condition.note != null && condition.note!.trim().isNotEmpty) {
      return '${condition.name} · ${condition.note}';
    }
    return condition.name;
  }

  Future<void> _showAddAllergy(BuildContext context, WidgetRef ref) async {
    final substanceController = TextEditingController();
    final reactionController = TextEditingController();

    await showAppDialog<void>(
      context,
      size: AppDialogSize.sm,
      semanticLabel: 'Add allergy',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Add allergy',
          onClose: () => close(),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFormField(
                label: 'Substance',
                child: AppTextField(controller: substanceController, hintText: 'Penicillin'),
              ),
              const SizedBox(height: AppSpacing.s3),
              AppFormField(
                label: 'Reaction',
                child: AppSelect<String?>(
                  placeholder: 'Optional',
                  options: [
                    const AppSelectOption<String?>(value: null, label: 'None'),
                    for (final entry in AllergySeverityOptions.items.entries)
                      AppSelectOption<String?>(value: entry.key, label: entry.value),
                  ],
                  onChanged: (value) => reactionController.text = value ?? '',
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: () => close(),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  AppButton(
                    label: 'Add',
                    size: AppButtonSize.sm,
                    onPressed: () {
                      final substance = substanceController.text.trim();
                      if (substance.isEmpty) return;
                      ref.read(visitDocumentationProvider(visitId).notifier).stageCreateAllergy(
                            substance: substance,
                            reaction: reactionController.text.trim().isEmpty
                                ? null
                                : reactionController.text.trim(),
                          );
                      close();
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    substanceController.dispose();
    reactionController.dispose();
  }
}

class _SafetySection extends StatelessWidget {
  const _SafetySection({
    required this.title,
    required this.emptyMessage,
    required this.lines,
  });

  final String title;
  final String emptyMessage;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: typography.bodyStrong.copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.s1),
        if (lines.isEmpty)
          Text(emptyMessage, style: typography.bodySm.copyWith(color: colors.textTertiary))
        else
          for (final line in lines)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s0_5),
              child: Text(line, style: typography.bodySm.copyWith(color: colors.textSecondary)),
            ),
      ],
    );
  }
}
