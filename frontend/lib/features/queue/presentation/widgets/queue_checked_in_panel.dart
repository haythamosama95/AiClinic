import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/core/ui/components/app_segmented_control.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/queue/domain/queue_display.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_flow_card.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_flow_pulse.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_secretary_utils.dart';

/// Checked-in patients waiting list with sort toggle and flow pulse
/// (web `CheckedInPanel`).
class QueueCheckedInPanel extends StatefulWidget {
  const QueueCheckedInPanel({required this.patients, required this.now, this.embedded = false, super.key});

  final List<AppointmentListItem> patients;
  final DateTime now;
  final bool embedded;

  @override
  State<QueueCheckedInPanel> createState() => _QueueCheckedInPanelState();
}

class _QueueCheckedInPanelState extends State<QueueCheckedInPanel> {
  static const _sortLongestWait = 'longest_wait';
  static const _sortNextInOrder = 'next_in_order';

  String _sort = _sortNextInOrder;

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
    return sorted.map((patient) => queueWaitMinutes(patient, widget.now)).reduce((a, b) => a > b ? a : b);
  }

  double _waitSeverity(int maxWait) => queueFlowPulseSeverity(maxWait);

  String get _sortHint => _sort == _sortNextInOrder ? 'Earliest appointment first' : 'Longest wait first';

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
          mainAxisSize: widget.embedded ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, colors),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.space4, AppSpacing.space3, AppSpacing.space4, 0),
              child: QueueFlowPulse(severity: _waitSeverity(_maxWait), patientCount: sortedPatients.length),
            ),
            if (widget.embedded)
              _buildPatientList(context, colors, sortedPatients)
            else
              Flexible(child: _buildPatientList(context, colors, sortedPatients)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppSemanticColors colors) {
    final titleColumn = Column(
      crossAxisAlignment: widget.embedded ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          'Checked in — waiting',
          textAlign: widget.embedded ? TextAlign.center : null,
          style: AppTypography.bodySm(context).copyWith(fontWeight: FontWeight.w600, color: colors.textPrimary),
        ),
        Text(
          _sortHint,
          textAlign: widget.embedded ? TextAlign.center : null,
          style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
        ),
      ],
    );

    final sortControl = AppSegmentedControl<String>(
      ariaLabel: 'Sort checked-in patients',
      size: AppSegmentedControlSize.sm,
      value: _sort,
      onChanged: (value) => setState(() => _sort = value),
      options: const [
        SegmentedOption(value: _sortNextInOrder, label: Text('Next in order')),
        SegmentedOption(value: _sortLongestWait, label: Text('Longest wait')),
      ],
    );

    return DecoratedBox(
      decoration: widget.embedded
          ? const BoxDecoration()
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.borderDefault)),
            ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.space4),
        child: widget.embedded
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.space2,
                children: [
                  titleColumn,
                  Center(child: sortControl),
                ],
              )
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [titleColumn, sortControl],
              ),
      ),
    );
  }

  Widget _buildPatientList(BuildContext context, AppSemanticColors colors, List<AppointmentListItem> sortedPatients) {
    if (sortedPatients.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.space4, 0, AppSpacing.space4, AppSpacing.space4),
        child: Text(
          'No patients currently waiting',
          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.space3,
        AppSpacing.space2,
        AppSpacing.space3,
        AppSpacing.space3,
      ),
      child: ConstrainedBox(
        constraints: widget.embedded ? const BoxConstraints(maxHeight: 448) : const BoxConstraints(),
        child: QueueFlowList(
          child: ListView.separated(
            shrinkWrap: widget.embedded,
            physics: widget.embedded ? const ClampingScrollPhysics() : null,
            padding: EdgeInsets.zero,
            itemCount: sortedPatients.length,
            separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: colors.borderDefault),
            itemBuilder: (context, index) {
              return _CheckedInPatientRow(
                patient: sortedPatients[index],
                index: index,
                now: widget.now,
                timeFormat: _timeFormat,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CheckedInPatientRow extends StatelessWidget {
  const _CheckedInPatientRow({required this.patient, required this.index, required this.now, required this.timeFormat});

  final AppointmentListItem patient;
  final int index;
  final DateTime now;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final waitMinutes = queueWaitMinutes(patient, now);
    final wait = Duration(minutes: waitMinutes);
    final tier = AppointmentQueueDisplay.waitTierFor(wait);

    return QueueWaitingPatientRow(
      patientName: patient.patientName,
      queuePosition: index + 1,
      wait: wait,
      tier: tier,
      appointmentTimeLabel: 'Appt ${timeFormat.format(patient.startTime.toLocal())}',
      arrivalTimeLabel: patient.checkedInAt != null ? 'Arr ${timeFormat.format(patient.checkedInAt!.toLocal())}' : null,
    );
  }
}
