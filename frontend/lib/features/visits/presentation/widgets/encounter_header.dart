import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Top-of-page encounter header with back, encounter metadata, patient snapshot, and actions (014 US1).
class EncounterHeader extends ConsumerWidget {
  const EncounterHeader({
    required this.visit,
    required this.onBack,
    this.onEdit,
    this.beforeTrailing,
    this.trailing,
    super.key,
  });

  final VisitDetail visit;
  final VoidCallback onBack;
  final VoidCallback? onEdit;
  final Widget? beforeTrailing;
  final Widget? trailing;

  static final _dateFormat = DateFormat.yMMMd();
  static final _timeFormat = DateFormat.jm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.visitTheme;
    final patientAsync = ref.watch(patientDetailProvider(visit.patientId));

    return Semantics(
      label: 'Encounter header',
      child: DecoratedBox(
        key: const Key('encounter_header'),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.tileRadius),
          border: Border.all(color: theme.hairlineSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 720;

              final encounterDetails = _EncounterDetails(visit: visit);
              final patientDetails = patientAsync.when(
                loading: () => const _PatientDetailsLine(name: '…', ageLabel: null),
                error: (_, _) => const _PatientDetailsLine(name: 'Patient unavailable', ageLabel: null),
                data: (detail) {
                  final age = PatientPresentationFormatting.ageYears(detail.dateOfBirth);
                  return _PatientDetailsLine(name: detail.fullName, ageLabel: age == null ? null : '$age yrs');
                },
              );

              final actions = _HeaderActions(onEdit: onEdit, beforeTrailing: beforeTrailing, trailing: trailing);
              final contextSections = isCompact
                  ? Wrap(
                      spacing: 0,
                      runSpacing: SpacingTokens.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        encounterDetails,
                        _HeaderSectionDivider(theme: theme),
                        patientDetails,
                      ],
                    )
                  : Row(
                      children: [
                        Flexible(child: encounterDetails),
                        _HeaderSectionDivider(theme: theme),
                        Flexible(child: patientDetails),
                      ],
                    );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AppIconButton(
                    key: const Key('encounter_header_back'),
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back',
                    onPressed: onBack,
                  ),
                  const SizedBox(width: SpacingTokens.md),
                  Expanded(child: contextSections),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String formatVisitDateTime(VisitDetail visit) {
    final dateLabel = _dateFormat.format(visit.visitDate.toLocal());
    final updatedAt = visit.updatedAt;
    if (updatedAt == null) {
      return dateLabel;
    }
    return '$dateLabel · ${_timeFormat.format(updatedAt.toLocal())}';
  }
}

class _EncounterDetails extends StatelessWidget {
  const _EncounterDetails({required this.visit});

  final VisitDetail visit;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final visitType = visit.visitType?.trim();
    final hasVisitType = visitType != null && visitType.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ENCOUNTER', style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
        const SizedBox(height: SpacingTokens.xs),
        Wrap(
          spacing: SpacingTokens.md,
          runSpacing: SpacingTokens.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _EncounterHeaderItem(
              key: const Key('encounter_header_date'),
              icon: Icons.calendar_today_outlined,
              value: EncounterHeader.formatVisitDateTime(visit),
            ),
            _EncounterHeaderItem(
              key: const Key('encounter_header_doctor'),
              icon: Icons.person_outline,
              value: visit.doctorName,
            ),
            if (hasVisitType)
              _EncounterHeaderItem(
                key: const Key('encounter_header_visit_type'),
                icon: Icons.label_outline,
                value: visitType,
              ),
          ],
        ),
      ],
    );
  }
}

class _PatientDetailsLine extends StatelessWidget {
  const _PatientDetailsLine({required this.name, this.ageLabel});

  final String name;
  final String? ageLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('PATIENT', style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
        const SizedBox(height: SpacingTokens.xs),
        Wrap(
          spacing: SpacingTokens.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              name,
              key: const Key('encounter_header_patient_name'),
              style: theme.bodyStrong(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (ageLabel != null)
              Text(ageLabel!, key: const Key('encounter_header_patient_age'), style: theme.caption()),
          ],
        ),
      ],
    );
  }
}

class _HeaderSectionDivider extends StatelessWidget {
  const _HeaderSectionDivider({required this.theme});

  final VisitTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md),
      child: SizedBox(height: 36, child: VerticalDivider(width: 1, thickness: 1, color: theme.hairlineSoft)),
    );
  }
}

class _HeaderActions extends StatelessWidget {
  const _HeaderActions({this.onEdit, this.beforeTrailing, this.trailing});

  final VoidCallback? onEdit;
  final Widget? beforeTrailing;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (onEdit != null) {
      children.add(
        AppIconButton(
          key: const Key('encounter_header_edit'),
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit documentation',
          onPressed: onEdit,
        ),
      );
    }

    if (beforeTrailing != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: SpacingTokens.sm));
      }
      children.add(beforeTrailing!);
    }

    if (trailing != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: SpacingTokens.sm));
      }
      children.add(trailing!);
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _EncounterHeaderItem extends StatelessWidget {
  const _EncounterHeaderItem({required this.icon, required this.value, super.key});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.mutedInk),
        const SizedBox(width: SpacingTokens.xs),
        Flexible(
          child: Text(value, style: theme.bodyStrong(size: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
