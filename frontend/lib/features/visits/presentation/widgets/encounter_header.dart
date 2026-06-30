import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Persistent encounter metadata header (014 US1).
class EncounterHeader extends StatelessWidget {
  const EncounterHeader({required this.visit, super.key});

  final VisitDetail visit;

  static final _dateFormat = DateFormat.yMMMd();
  static final _timeFormat = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final visitType = visit.visitType?.trim();
    final hasVisitType = visitType != null && visitType.isNotEmpty;

    return Semantics(
      label: 'Encounter header',
      child: AppNotchedCard(
        key: const Key('encounter_header'),
        titleIcon: Icons.event_note_outlined,
        title: Text('Encounter', style: theme.title()),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
          child: Wrap(
            spacing: SpacingTokens.lg,
            runSpacing: SpacingTokens.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _EncounterHeaderItem(
                key: const Key('encounter_header_date'),
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value: _formatVisitDateTime(visit),
              ),
              _EncounterHeaderItem(
                key: const Key('encounter_header_doctor'),
                icon: Icons.person_outline,
                label: 'Doctor',
                value: visit.doctorName,
              ),
              _EncounterHeaderStatus(status: visit.status),
              if (hasVisitType)
                _EncounterHeaderItem(
                  key: const Key('encounter_header_visit_type'),
                  icon: Icons.label_outline,
                  label: 'Visit type',
                  value: visitType,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatVisitDateTime(VisitDetail visit) {
    final dateLabel = _dateFormat.format(visit.visitDate.toLocal());
    final updatedAt = visit.updatedAt;
    if (updatedAt == null) {
      return dateLabel;
    }
    return '$dateLabel · ${_timeFormat.format(updatedAt.toLocal())}';
  }
}

class _EncounterHeaderStatus extends StatelessWidget {
  const _EncounterHeaderStatus({required this.status});

  final VisitStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final (variant, icon) = switch (status) {
      VisitStatus.inProgress => (AppBadgeVariant.primary, Icons.pending_outlined),
      VisitStatus.completed => (AppBadgeVariant.muted, Icons.check_circle_outline),
    };

    return Column(
      key: const Key('encounter_header_status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('STATUS', style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
        const SizedBox(height: SpacingTokens.xs + 1),
        AppBadge(label: status.label, variant: variant, icon: Icon(icon)),
      ],
    );
  }
}

class _EncounterHeaderItem extends StatelessWidget {
  const _EncounterHeaderItem({required this.icon, required this.label, required this.value, super.key});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.mutedInk),
        const SizedBox(width: SpacingTokens.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
            const SizedBox(height: SpacingTokens.xs + 1),
            Text(value, style: theme.bodyStrong()),
          ],
        ),
      ],
    );
  }
}
