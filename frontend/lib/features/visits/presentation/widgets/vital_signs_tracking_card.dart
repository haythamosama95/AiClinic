import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/bmi.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Visit vital signs card for the Findings & Diagnosis step (014 US2) — mirrors the
/// right-column [PatientHealthTrackingCard] shell on Intake.
class VitalSignsTrackingCard extends ConsumerWidget {
  const VitalSignsTrackingCard({
    required this.visitId,
    required this.vitalSigns,
    required this.predefinedVitalSigns,
    required this.canEdit,
    required this.onChanged,
    this.expandBody = false,
    this.deferPersistence = false,
    super.key,
  });

  final String visitId;
  final List<VisitVitalSign> vitalSigns;
  final List<CatalogItem> predefinedVitalSigns;
  final bool canEdit;
  final VoidCallback onChanged;
  final bool expandBody;
  final bool deferPersistence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.visitTheme;
    final hasVitalSigns = vitalSigns.isNotEmpty;

    return KeyedSubtree(
      key: const Key('vital_signs_tracking_card'),
      child: _VitalSignsShell(
        expandBody: expandBody,
        headerTrailing: canEdit && hasVitalSigns
            ? AppIconButton(
                key: const Key('vital_sign_add_button'),
                icon: Icon(Icons.add_rounded, size: HealthProfileCardTokens.addIconSize, color: theme.pulse),
                tooltip: 'Add vital sign',
                onPressed: () => showVitalSignAddDialog(
                  context: context,
                  visitId: visitId,
                  predefinedVitalSigns: predefinedVitalSigns,
                  onRefresh: onChanged,
                  deferPersistence: deferPersistence,
                ),
              )
            : null,
        child: _VitalSignsBody(
          visitId: visitId,
          vitalSigns: vitalSigns,
          predefinedVitalSigns: predefinedVitalSigns,
          canEdit: canEdit,
          onChanged: onChanged,
          expandBody: expandBody,
          deferPersistence: deferPersistence,
        ),
      ),
    );
  }
}

class _VitalSignsShell extends StatelessWidget {
  const _VitalSignsShell({required this.child, required this.expandBody, this.headerTrailing});

  final Widget child;
  final bool expandBody;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final cardTheme = context.healthProfileCardTheme;
    final colors = context.semanticColors;
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: cardTheme.pulseCardGradient)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SpacingTokens.md,
                    SpacingTokens.md,
                    SpacingTokens.md,
                    SpacingTokens.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        VisitPanelKind.vitalSigns.icon,
                        size: HealthProfileCardTokens.shellIconSize,
                        color: theme.pulse,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Expanded(child: Text('Vital signs', style: cardTheme.shellTitle)),
                      Text('Current visit', style: cardTheme.shellSubtitle),
                      if (headerTrailing != null) ...[const SizedBox(width: SpacingTokens.xs), headerTrailing!],
                    ],
                  ),
                ),
                if (expandBody) Expanded(child: body) else body,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalSignsBody extends StatelessWidget {
  const _VitalSignsBody({
    required this.visitId,
    required this.vitalSigns,
    required this.predefinedVitalSigns,
    required this.canEdit,
    required this.onChanged,
    required this.expandBody,
    required this.deferPersistence,
  });

  final String visitId;
  final List<VisitVitalSign> vitalSigns;
  final List<CatalogItem> predefinedVitalSigns;
  final bool canEdit;
  final VoidCallback onChanged;
  final bool expandBody;
  final bool deferPersistence;

  @override
  Widget build(BuildContext context) {
    final list = VitalSignList(
      visitId: visitId,
      vitalSigns: vitalSigns,
      predefinedVitalSigns: predefinedVitalSigns,
      canEdit: canEdit,
      onChanged: onChanged,
      sectionTitle: 'Vital signs',
      sectionKind: VisitPanelKind.vitalSigns,
      showSectionCard: false,
      embeddedInTrackingCard: true,
      expandBody: expandBody,
      deferPersistence: deferPersistence,
    );

    if (vitalSigns.isEmpty) {
      return expandBody ? SizedBox.expand(child: list) : list;
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        list,
        BmiChip(vitalSigns: vitalSigns),
      ],
    );

    if (!expandBody) return content;

    return SingleChildScrollView(child: content);
  }
}

/// Read-only vital signs for the detail view right column.
class VitalSignsTrackingCardReadOnly extends StatelessWidget {
  const VitalSignsTrackingCardReadOnly({required this.vitalSigns, this.expandBody = false, super.key});

  final List<VisitVitalSign> vitalSigns;
  final bool expandBody;

  @override
  Widget build(BuildContext context) {
    return _VitalSignsShell(
      expandBody: expandBody,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VitalSignsReadOnly(vitalSigns: vitalSigns, expandBody: expandBody),
          BmiChip(vitalSigns: vitalSigns),
        ],
      ),
    );
  }
}

/// Derived BMI chip — client-side only (FR-025).
class BmiChip extends StatelessWidget {
  const BmiChip({required this.vitalSigns, super.key});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final bmi = deriveBmiFromVitalSigns(vitalSigns);
    if (bmi == null) {
      return const SizedBox.shrink();
    }

    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(top: SpacingTokens.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          key: const Key('encounter_objective_bmi_chip'),
          decoration: BoxDecoration(
            color: theme.pulse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(theme.tileRadius),
            border: Border.all(color: theme.pulse.withValues(alpha: 0.24)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed_outlined, size: 16, color: theme.pulseDeep),
                const SizedBox(width: SpacingTokens.sm),
                Text('BMI ${bmi.displayValue}', style: theme.bodyStrong(color: theme.pulseDeep)),
                const SizedBox(width: SpacingTokens.sm),
                Text(
                  '(${bmi.heightCm.toStringAsFixed(0)} cm · ${bmi.weightKg.toStringAsFixed(0)} kg)',
                  style: theme.caption(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VitalSignsReadOnly extends StatelessWidget {
  const _VitalSignsReadOnly({required this.vitalSigns, this.expandBody = false});

  final List<VisitVitalSign> vitalSigns;
  final bool expandBody;

  @override
  Widget build(BuildContext context) {
    if (vitalSigns.isEmpty) {
      return EncounterFieldEmptyState(
        key: const Key('visit_detail_vital_signs_empty'),
        icon: VisitPanelKind.vitalSigns.icon,
        text: 'No vital signs recorded',
        expand: expandBody,
      );
    }

    return Wrap(
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.sm,
      children: [for (final sign in vitalSigns) VitalSignCardView(sign: sign)],
    );
  }
}
