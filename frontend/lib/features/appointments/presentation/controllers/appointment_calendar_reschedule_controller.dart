import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_clinic/features/appointments/presentation/formatting/appointment_range_format.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_reschedule_service.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_layout.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_reschedule_validation.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_sync_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_confirm_dialog.dart';
import 'package:ai_clinic/core/domain/clinic/branch_working_schedule.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

/// Parameters for the unified calendar reschedule pipeline.
class AppointmentRescheduleRequest {
  const AppointmentRescheduleRequest({
    required this.item,
    required this.newStart,
    required this.newEnd,
    required this.mode,
    required this.schedule,
    required this.branchAppointments,
    required this.syncContext,
    this.targetDoctorId,
    this.isResize = false,
  });

  final AppointmentListItem item;
  final DateTime newStart;
  final DateTime newEnd;
  final AppointmentCalendarMode mode;
  final BranchWorkingSchedule schedule;
  final List<AppointmentListItem> branchAppointments;
  final String? targetDoctorId;
  final bool isResize;
  final AppointmentRescheduleSyncContext syncContext;
}

/// Data-source colours and doctors needed to revert calendar tiles.
class AppointmentRescheduleSyncContext {
  const AppointmentRescheduleSyncContext({
    required this.doctors,
    required this.includeDoctorResources,
    required this.evenResourceRowColor,
    required this.oddResourceRowColor,
  });

  final List<StaffListItem> doctors;
  final bool includeDoctorResources;
  final Color evenResourceRowColor;
  final Color oddResourceRowColor;
}

/// Drag-and-drop and resize reschedule orchestration for the calendar.
class AppointmentCalendarRescheduleController {
  AppointmentCalendarRescheduleController({
    required this.sync,
    required this.onChanged,
  });

  final AppointmentCalendarSyncController sync;
  final VoidCallback onChanged;

  CalendarDragSession? dragSession;
  CalendarResizeSession? resizeSession;
  bool _isProcessing = false;

  bool get hasActiveGesture => dragSession != null || resizeSession != null;

  void onDragStart(
    AppointmentDragStartDetails details, {
    required List<AppointmentListItem> items,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final calendarAppointment = details.appointment;
    if (calendarAppointment is! Appointment) {
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      return;
    }

    final item = sync.itemById(appointmentId);
    if (item == null) {
      return;
    }

    dragSession = CalendarDragSession(
      item: item,
      previewStart: item.startTime.toLocal(),
      slotMinutes: slotMinutes,
      baseItems: items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
    onChanged();
    sync.applyDragPreview(dragSession!);
  }

  void onDragUpdate(
    AppointmentDragUpdateDetails details, {
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final session = dragSession;
    final draggingTime = details.draggingTime;
    if (session == null || draggingTime == null) {
      return;
    }

    final snappedStart = AppointmentCalendarLayout.snapTimeToSlot(draggingTime, slotMinutes: slotMinutes);
    if (snappedStart == session.previewStart) {
      return;
    }

    session.previewStart = snappedStart;
    session
      ..doctors = doctors
      ..includeDoctorResources = includeDoctorResources
      ..evenResourceRowColor = evenResourceRowColor
      ..oddResourceRowColor = oddResourceRowColor;
    sync.applyDragPreview(session);
  }

  Future<void> onDragEnd(
    AppointmentDragEndDetails details, {
    required BuildContext context,
    required WidgetRef ref,
    required List<AppointmentListItem> items,
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required int slotMinutes,
    required AppointmentRescheduleSyncContext syncContext,
    required VoidCallback onGestureComplete,
  }) async {
    if (_isProcessing) {
      return;
    }

    final session = dragSession;
    final droppingTime = details.droppingTime;
    final calendarAppointment = details.appointment;
    if (droppingTime == null || calendarAppointment is! Appointment) {
      _clearDragSession(items: items);
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      _clearDragSession(items: items);
      return;
    }

    final item = sync.itemById(appointmentId);
    if (item == null) {
      _clearDragSession(items: items);
      return;
    }

    final duration = item.endTime.difference(item.startTime);
    final newStart =
        session?.previewStart ?? AppointmentCalendarLayout.snapTimeToSlot(droppingTime, slotMinutes: slotMinutes);
    final newEnd = newStart.add(duration);

    dragSession = null;
    onChanged();

    await run(
      context: context,
      ref: ref,
      request: AppointmentRescheduleRequest(
        item: item,
        newStart: newStart,
        newEnd: newEnd,
        mode: mode,
        schedule: schedule,
        branchAppointments: items,
        targetDoctorId: doctorIdFromCalendarResource(details.targetResource),
        syncContext: syncContext,
      ),
      onComplete: onGestureComplete,
    );
  }

  void onResizeStart(
    AppointmentResizeStartDetails details, {
    required List<AppointmentListItem> items,
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final calendarAppointment = details.appointment;
    if (calendarAppointment is! Appointment) {
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      return;
    }

    final item = sync.itemById(appointmentId);
    if (item == null) {
      return;
    }

    final localStart = item.startTime.toLocal();
    final localEnd = item.endTime.toLocal();
    resizeSession = CalendarResizeSession(
      item: item,
      previewStart: localStart,
      previewEnd: localEnd,
      slotMinutes: slotMinutes,
      baseItems: items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
    onChanged();
    sync.applyResizePreview(resizeSession!);
  }

  void onResizeUpdate(
    AppointmentResizeUpdateDetails details, {
    required int slotMinutes,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final session = resizeSession;
    final resizingTime = details.resizingTime;
    if (session == null || resizingTime == null) {
      return;
    }

    final snapped = AppointmentCalendarLayout.snapTimeToSlot(resizingTime, slotMinutes: slotMinutes);
    final localStart = session.item.startTime.toLocal();
    final localEnd = session.item.endTime.toLocal();
    session.resizeFromStart ??=
        (snapped.difference(localStart).inMinutes).abs() <= (snapped.difference(localEnd).inMinutes).abs();

    if (session.resizeFromStart!) {
      session.previewStart = snapped;
      session.previewEnd = localEnd;
    } else {
      session.previewStart = localStart;
      session.previewEnd = snapped;
    }

    if (!session.previewEnd.isAfter(session.previewStart)) {
      return;
    }

    session
      ..doctors = doctors
      ..includeDoctorResources = includeDoctorResources
      ..evenResourceRowColor = evenResourceRowColor
      ..oddResourceRowColor = oddResourceRowColor;
    sync.applyResizePreview(session);
  }

  Future<void> onResizeEnd(
    AppointmentResizeEndDetails details, {
    required BuildContext context,
    required WidgetRef ref,
    required List<AppointmentListItem> items,
    required BranchWorkingSchedule schedule,
    required AppointmentCalendarMode mode,
    required int slotMinutes,
    required AppointmentRescheduleSyncContext syncContext,
    required VoidCallback onGestureComplete,
  }) async {
    if (_isProcessing) {
      return;
    }

    final calendarAppointment = details.appointment;
    final startTime = details.startTime;
    final endTime = details.endTime;
    if (calendarAppointment is! Appointment || startTime == null || endTime == null) {
      _clearResizeSession(items: items);
      return;
    }

    final appointmentId = calendarAppointment.id?.toString();
    if (appointmentId == null || appointmentId.isEmpty) {
      _clearResizeSession(items: items);
      return;
    }

    final item = sync.itemById(appointmentId);
    if (item == null) {
      _clearResizeSession(items: items);
      return;
    }

    final newStart = AppointmentCalendarLayout.snapTimeToSlot(startTime, slotMinutes: slotMinutes);
    final newEnd = AppointmentCalendarLayout.snapTimeToSlot(endTime, slotMinutes: slotMinutes);

    resizeSession = null;
    onChanged();

    await run(
      context: context,
      ref: ref,
      request: AppointmentRescheduleRequest(
        item: item,
        newStart: newStart,
        newEnd: newEnd,
        mode: mode,
        schedule: schedule,
        branchAppointments: items,
        syncContext: syncContext,
        isResize: true,
      ),
      onComplete: onGestureComplete,
    );
  }

  Future<void> run({
    required BuildContext context,
    required WidgetRef ref,
    required AppointmentRescheduleRequest request,
    required VoidCallback onComplete,
  }) async {
    final syncContext = request.syncContext;
    final items = request.branchAppointments;

    void revert() {
      sync.revertItems(
        items,
        doctors: syncContext.doctors,
        includeDoctorResources: syncContext.includeDoctorResources,
        evenResourceRowColor: syncContext.evenResourceRowColor,
        oddResourceRowColor: syncContext.oddResourceRowColor,
      );
    }

    sync.applySnappedPreview(
      items: items,
      appointmentId: request.item.id,
      newStart: request.newStart,
      newEnd: request.newEnd,
      doctors: syncContext.doctors,
      includeDoctorResources: syncContext.includeDoctorResources,
      evenResourceRowColor: syncContext.evenResourceRowColor,
      oddResourceRowColor: syncContext.oddResourceRowColor,
    );

    final isNoOp = request.isResize
        ? AppointmentRescheduleValidation.isNoOpResize(
            appointment: request.item,
            newStart: request.newStart,
            newEnd: request.newEnd,
          )
        : AppointmentRescheduleValidation.isNoOpMove(appointment: request.item, newStart: request.newStart);

    if (isNoOp) {
      revert();
      onComplete();
      return;
    }

    if (request.mode == AppointmentCalendarMode.doctors) {
      final resourceError = AppointmentRescheduleValidation.validateDoctorResourceMove(
        appointment: request.item,
        targetDoctorId: request.targetDoctorId,
      );
      if (resourceError != null) {
        revert();
        if (context.mounted) {
          appToast(context, AppToastInput(message: resourceError, variant: AppToastVariant.danger));
        }
        onComplete();
        return;
      }
    }

    final validationError = AppointmentRescheduleValidation.validateMove(
      appointment: request.item,
      newStart: request.newStart,
      newEnd: request.newEnd,
      schedule: request.schedule,
      branchAppointments: items,
    );
    if (validationError != null) {
      revert();
      if (context.mounted) {
        appToast(context, AppToastInput(message: validationError, variant: AppToastVariant.danger));
      }
      onComplete();
      return;
    }

    if (!context.mounted) {
      revert();
      onComplete();
      return;
    }

    final confirmed = await AppointmentRescheduleConfirmDialog.show(
      context,
      appointment: request.item,
      newStart: request.newStart,
      newEnd: request.newEnd,
      schedule: request.schedule,
      branchAppointments: items,
    );
    if (confirmed == null) {
      revert();
      onComplete();
      return;
    }

    final finalStart = confirmed.start;
    final finalEnd = confirmed.end;

    final postEditNoOp = request.isResize
        ? AppointmentRescheduleValidation.isNoOpResize(
            appointment: request.item,
            newStart: finalStart,
            newEnd: finalEnd,
          )
        : AppointmentRescheduleValidation.isNoOpMove(appointment: request.item, newStart: finalStart) &&
            _isSameInstant(finalEnd, request.item.endTime);

    if (postEditNoOp) {
      revert();
      onComplete();
      return;
    }

    final postEditValidationError = AppointmentRescheduleValidation.validateMove(
      appointment: request.item,
      newStart: finalStart,
      newEnd: finalEnd,
      schedule: request.schedule,
      branchAppointments: items,
    );
    if (postEditValidationError != null) {
      revert();
      if (context.mounted) {
        appToast(context, AppToastInput(message: postEditValidationError, variant: AppToastVariant.danger));
      }
      onComplete();
      return;
    }

    _isProcessing = true;
    try {
      final result = await ref.read(appointmentRescheduleServiceProvider).reschedule(
            appointmentId: request.item.id,
            startTime: finalStart,
            endTime: finalEnd,
          );
      if (!context.mounted) {
        return;
      }

      switch (result) {
        case AppointmentRescheduleSuccess():
          await ref.read(appointmentCalendarProvider.notifier).refresh();
          if (!context.mounted) {
            return;
          }
          final verb = request.isResize ? 'updated' : 'moved';
          appToast(
            context,
            AppToastInput(
              message: 'Appointment $verb to ${formatAppointmentRange(finalStart, finalEnd)}.',
              variant: AppToastVariant.success,
            ),
          );
        case AppointmentRescheduleFailure(:final userMessage):
          revert();
          appToast(context, AppToastInput(message: userMessage, variant: AppToastVariant.danger));
      }
    } finally {
      _isProcessing = false;
      onComplete();
    }
  }

  void _clearDragSession({required List<AppointmentListItem> items}) {
    final session = dragSession;
    if (session == null) {
      return;
    }

    sync.revertItems(
      items,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
    dragSession = null;
    onChanged();
  }

  void _clearResizeSession({required List<AppointmentListItem> items}) {
    final session = resizeSession;
    if (session == null) {
      return;
    }

    sync.revertItems(
      items,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
    resizeSession = null;
    onChanged();
  }

  static bool _isSameInstant(DateTime a, DateTime b) {
    return a.toUtc().millisecondsSinceEpoch == b.toUtc().millisecondsSinceEpoch;
  }
}

class CalendarDragSession {
  CalendarDragSession({
    required this.item,
    required this.previewStart,
    required this.slotMinutes,
    required this.baseItems,
    required this.doctors,
    required this.includeDoctorResources,
    required this.evenResourceRowColor,
    required this.oddResourceRowColor,
  });

  final AppointmentListItem item;
  DateTime previewStart;
  final int slotMinutes;
  final List<AppointmentListItem> baseItems;
  List<StaffListItem> doctors;
  bool includeDoctorResources;
  Color evenResourceRowColor;
  Color oddResourceRowColor;
}

class CalendarResizeSession {
  CalendarResizeSession({
    required this.item,
    required this.previewStart,
    required this.previewEnd,
    required this.slotMinutes,
    required this.baseItems,
    required this.doctors,
    required this.includeDoctorResources,
    required this.evenResourceRowColor,
    required this.oddResourceRowColor,
  });

  final AppointmentListItem item;
  DateTime previewStart;
  DateTime previewEnd;
  final int slotMinutes;
  final List<AppointmentListItem> baseItems;
  bool? resizeFromStart;
  List<StaffListItem> doctors;
  bool includeDoctorResources;
  Color evenResourceRowColor;
  Color oddResourceRowColor;
}

bool supportsCalendarDragAndDrop(AppointmentCalendarMode mode) {
  return switch (mode) {
    AppointmentCalendarMode.day => true,
    AppointmentCalendarMode.week => true,
    AppointmentCalendarMode.doctors => true,
    _ => false,
  };
}

bool usesDoctorCalendarResources(AppointmentCalendarMode mode) {
  return mode == AppointmentCalendarMode.doctors;
}

List<StaffListItem> filteredCalendarDoctors(
  List<StaffListItem> doctors, {
  required String? selectedDoctorId,
  required AppointmentCalendarMode mode,
}) {
  if (mode != AppointmentCalendarMode.doctors || selectedDoctorId == null || selectedDoctorId.isEmpty) {
    return doctors;
  }
  return doctors.where((doctor) => doctor.id == selectedDoctorId).toList(growable: false);
}
