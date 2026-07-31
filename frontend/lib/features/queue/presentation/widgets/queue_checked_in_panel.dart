import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_flow_pulse.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';

/// Checked-in patients waiting list with sort toggle and flow pulse
/// (web `CheckedInPanel`).
class QueueCheckedInPanel extends StatefulWidget {
  const QueueCheckedInPanel({
    required this.patients,
    required this.now,
    this.embedded = false,
    super.key,
  });

  final List<AppointmentListItem> patients;
  final DateTime now;
  final bool embedded;

  @override
  State<QueueCheckedInPanel> createState() => _QueueCheckedInPanelState();
}

class _QueueCheckedInPanelState extends State<QueueCheckedInPanel> {
  static const _sortLongestWait = 'longest_wait';
  static const _sortNextInOrder = 'next_in_order';

  String _sort = _sortLongestWait;

  static final _timeFormat = DateFormat('h:mm a');

  List<AppointmentListItem> get _sortedPatients {
    if (_sort == _sortNextInOrder) {
      final list = List<AppointmentListItem>.of(widget.patients);
      list.sort((a, b) => a.startTime.compareTo(b.startTime));
      return list;
    }
    return queueCheckedInPatients(widget.patients, widget.now);
  }

  int get _maxWait {
    final sorted = _sortedPatients;
    if (sorted.isEmpty) {
      return 0;
    }
    return sorted
        .map((patient) => queueWaitMinutes(patient, widget.now))
        .reduce((a, b) => a > b ? a : b);
  }

  double _waitSeverity(int maxWait) => queueFlowPulseSeverity(maxWait);

  String get _sortHint => _sort == _sortNextInOrder
      ? 'Earliest appointment first'
      : 'Longest wait first';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final sortedPatients = _sortedPatients;

    return Semantics(
      container: true,
      label: 'Checked in waiting panel',
      child: DecoratedBox(
        decoration: widget.embedded
            ? const BoxDecoration()
            : BoxDecoration(
                color: colors.surfaceDefault,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: colors.borderDefault),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, colors),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.space4,
                AppSpacing.space3,
                AppSpacing.space4,
                0,
              ),
              child: QueueFlowPulse(
                severity: _waitSeverity(_maxWait),
                patientCount: sortedPatients.length,
              ),
            ),
            Flexible(
              child: _buildPatientList(context, colors, sortedPatients),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppSemanticColors colors) {
    return DecoratedBox(
      decoration: widget.embedded
          ? const BoxDecoration()
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.borderDefault),
              ),
            ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.space4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.start,
          spacing: AppSpacing.space2,
          runSpacing: AppSpacing.space2,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Checked in — waiting',
                  style: AppTypography.bodySm(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  _sortHint,
                  style: AppTypography.caption(context).copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            AppSegmentedControl<String>(
              ariaLabel: 'Sort checked-in patients',
              size: AppSegmentedControlSize.sm,
              value: _sort,
              onChanged: (value) => setState(() => _sort = value),
              options: const [
                SegmentedOption(
                  value: _sortLongestWait,
                  label: Text('Longest wait'),
                ),
                SegmentedOption(
                  value: _sortNextInOrder,
                  label: Text('Next in order'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientList(
    BuildContext context,
    AppSemanticColors colors,
    List<AppointmentListItem> sortedPatients,
  ) {
    if (sortedPatients.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.space4,
          0,
          AppSpacing.space4,
          AppSpacing.space4,
        ),
        child: Text(
          'No patients currently waiting',
          style: AppTypography.bodySm(context).copyWith(
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: widget.embedded
          ? const BoxConstraints(maxHeight: 448)
          : const BoxConstraints(),
      child: ListView.separated(
        shrinkWrap: widget.embedded,
        padding: EdgeInsets.zero,
        itemCount: sortedPatients.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          thickness: 1,
          color: colors.borderSubtle,
        ),
        itemBuilder: (context, index) {
          return _CheckedInPatientRow(
            patient: sortedPatients[index],
            index: index,
            now: widget.now,
            timeFormat: _timeFormat,
          );
        },
      ),
    );
  }
}

class _CheckedInPatientRow extends StatelessWidget {
  const _CheckedInPatientRow({
    required this.patient,
    required this.index,
    required this.now,
    required this.timeFormat,
  });

  final AppointmentListItem patient;
  final int index;
  final DateTime now;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final waitMinutes = queueWaitMinutes(patient, now);
    final wait = Duration(minutes: waitMinutes);
    final tier = AppointmentQueueDisplay.waitTierFor(wait);
    final isWarning = tier == AppointmentQueueWaitTier.warning;
    final isCritical = tier == AppointmentQueueWaitTier.critical;

    final backgroundColor = isCritical
        ? colors.statusDangerSurface.withValues(alpha: 0.5)
        : isWarning
            ? colors.statusWarningSurface.withValues(alpha: 0.5)
            : null;

    final waitColor = isCritical
        ? colors.statusDangerFg
        : isWarning
            ? colors.statusWarningFg
            : colors.actionPrimary;

    final preferredDoctor =
        patient.doctorName?.trim().isNotEmpty == true
            ? patient.doctorName!.trim()
            : 'Any provider';

    return ColoredBox(
      color: backgroundColor ?? Colors.transparent,
      child: AppCard(
        variant: CardVariant.flat,
        padding: CardPadding.sm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.patientName,
                        style: AppTypography.bodySm(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        preferredDoctor,
                        style: AppTypography.caption(context).copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: AppSpacing.space2,
                      vertical: AppSpacing.space1,
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: AppTypography.mono(context).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppointmentQueueDisplay.formatDurationLabel(wait),
                  style: AppTypography.mono(context).copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: waitColor,
                  ),
                ),
                if (isWarning || isCritical)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: colors.statusDangerFg,
                      ),
                      const SizedBox(width: AppSpacing.space1),
                      Text(
                        isCritical ? 'Critical wait' : 'Long wait',
                        style: AppTypography.caption(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.statusDangerFg,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.space1),
            Wrap(
              spacing: AppSpacing.space3,
              children: [
                Text(
                  'Appt ${timeFormat.format(patient.startTime.toLocal())}',
                  style: AppTypography.caption(context).copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (patient.checkedInAt != null)
                  Text(
                    'Arr ${timeFormat.format(patient.checkedInAt!.toLocal())}',
                    style: AppTypography.caption(context).copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
