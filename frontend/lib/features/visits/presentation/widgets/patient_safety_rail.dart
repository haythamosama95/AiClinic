import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Persistent read-only patient safety surface (014 US3/US6 / FR-010–012).
class PatientSafetyRail extends ConsumerWidget {
  const PatientSafetyRail({required this.patientId, this.phase, super.key});

  final String patientId;
  final EncounterPhase? phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.visitTheme;
    final safetyAsync = ref.watch(patientSafetyProvider(patientId));

    return Semantics(
      label: phase == null ? 'Patient safety context' : 'Patient safety context for ${phase!.label}',
      child: AppNotchedCard(
        key: const Key('patient_safety_rail'),
        titleIcon: Icons.health_and_safety_outlined,
        title: Text('Safety', style: theme.title(size: 15)),
        description: Text('Read-only patient context', style: theme.caption(size: 11.5)),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
          child: safetyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: SpacingTokens.md),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => _DegradedAlertsLine(theme: theme),
            data: (safety) => _SafetyBody(theme: theme, safety: safety),
          ),
        ),
      ),
    );
  }
}

class _SafetyBody extends StatelessWidget {
  const _SafetyBody({required this.theme, required this.safety});

  final VisitTheme theme;
  final PatientSafetyContext safety;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!safety.hasStructuredData) _DegradedAlertsLine(theme: theme) else const SizedBox.shrink(),
        if (!safety.hasStructuredData) const SizedBox(height: SpacingTokens.md),
        _SafetyCategory(
          key: const Key('patient_safety_allergies'),
          icon: Icons.warning_amber_outlined,
          label: 'Allergies',
          emptyMessage: 'No allergies recorded.',
          items: safety.allergies
              .map((a) => a.reaction?.trim().isNotEmpty == true ? '${a.substance} — ${a.reaction}' : a.substance)
              .toList(),
        ),
        const SizedBox(height: SpacingTokens.sm),
        _SafetyCategory(
          key: const Key('patient_safety_medications'),
          icon: Icons.medication_outlined,
          label: 'Current medications',
          emptyMessage: 'No current medications recorded.',
          items: safety.currentMedications.map((m) => m.name).toList(),
        ),
        const SizedBox(height: SpacingTokens.sm),
        _SafetyCategory(
          key: const Key('patient_safety_conditions'),
          icon: Icons.favorite_border,
          label: 'Chronic conditions',
          emptyMessage: 'No chronic conditions recorded.',
          items: safety.chronicConditions.map((c) => c.name).toList(),
        ),
        const SizedBox(height: SpacingTokens.sm),
        _SafetyCategory(
          key: const Key('patient_safety_last_vitals'),
          icon: Icons.monitor_heart_outlined,
          label: 'Last vitals',
          emptyMessage: 'No prior vitals on file.',
          items: safety.lastVitals.items.map((v) {
            final unit = v.unit?.trim();
            return unit == null || unit.isEmpty ? '${v.name}: ${v.value}' : '${v.name}: ${v.value} $unit';
          }).toList(),
        ),
      ],
    );
  }
}

class _DegradedAlertsLine extends StatelessWidget {
  const _DegradedAlertsLine({required this.theme});

  final VisitTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('patient_safety_alerts_line'),
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.hairlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm + 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.notifications_none_outlined, size: 16, color: theme.mutedInk),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: Text('Alerts: none documented', style: theme.caption(color: theme.mutedInk)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyCategory extends StatelessWidget {
  const _SafetyCategory({
    required this.icon,
    required this.label,
    required this.emptyMessage,
    required this.items,
    super.key,
  });

  final IconData icon;
  final String label;
  final String emptyMessage;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.mutedInk.withValues(alpha: 0.85)),
        const SizedBox(width: SpacingTokens.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.eyebrow(size: 10)),
              const SizedBox(height: 2),
              if (items.isEmpty)
                Text(emptyMessage, style: theme.caption(size: 11.5))
              else
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(item, style: theme.caption(size: 11.5)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
