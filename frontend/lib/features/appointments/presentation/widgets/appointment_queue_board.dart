import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_presentation_formatting.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_status_actions.dart';

/// Builds queue board columns of [AppointmentCard] widgets for [CalendarQueuePattern].
List<CalendarQueueColumn> buildAppointmentQueueColumns({
  required BuildContext context,
  required List<AppointmentListItem> items,
  required String branchLabel,
  AppointmentQueueShiftDoctorLookup shiftLookup = AppointmentQueueShiftDoctorLookup.empty,
  DateTime? now,
}) {
  final referenceNow = now ?? clock.now();
  final partition = AppointmentQueueDisplay.partition(items, now: referenceNow);

  final scheduleItems = partition.schedule
      .where(
        (item) => item.status != AppointmentStatus.checkedIn && item.status != AppointmentStatus.inProgress,
      )
      .toList(growable: false);
  final waitingItems = partition.waiting;
  final inSessionItems = partition.schedule
      .where((item) => item.status == AppointmentStatus.inProgress)
      .toList(growable: false);

  List<Widget> cardsFor(List<AppointmentListItem> columnItems) {
    return [
      for (final item in columnItems)
        _QueueAppointmentCard(
          item: item,
          branchLabel: branchLabel,
          shiftLookup: shiftLookup,
          dimmed: AppointmentQueueDisplay.isScheduleRowDimmed(item),
        ),
    ];
  }

  return [
    CalendarQueueColumn(
      title: 'Schedule',
      cards: cardsFor(scheduleItems),
      emptyLabel: 'No appointments scheduled',
    ),
    CalendarQueueColumn(
      title: 'Waiting',
      cards: cardsFor(waitingItems),
      emptyLabel: 'No patients waiting',
    ),
    CalendarQueueColumn(
      title: 'In session',
      cards: cardsFor(inSessionItems),
      emptyLabel: 'No active sessions',
    ),
  ];
}
class _QueueAppointmentCard extends StatelessWidget {
  const _QueueAppointmentCard({
    required this.item,
    required this.branchLabel,
    required this.shiftLookup,
    required this.dimmed,
  });

  final AppointmentListItem item;
  final String branchLabel;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final doctorPresentation = AppointmentQueueDisplay.queueDoctorPresentation(item, shiftLookup: shiftLookup);
    final doctorLabel = doctorPresentation.displayNames.isEmpty ? item.doctorDisplayName : doctorPresentation.displayNames;

    final card = AppointmentCard(
      time: AppointmentPresentationFormatting.appointmentCardTimeLabel(item),
      patient: item.patientName,
      doctor: doctorLabel,
      status: AppointmentPresentationFormatting.cardStatusFor(item.status),
      branch: branchLabel,
    );

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.nav.pushAppointmentDetail(item.id, preview: item),
          borderRadius: AppRadii.lgAll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              card,
              const SizedBox(height: AppSpacing.s2),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppointmentStatusActions.fromListItem(item: item, compact: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
