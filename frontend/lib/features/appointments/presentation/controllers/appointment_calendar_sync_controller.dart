import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_geometry.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/controllers/appointment_calendar_reschedule_controller.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/core/domain/clinic/staff_list_item.dart';

/// Syncfusion controller, data-source sync, and calendar view/date alignment.
class AppointmentCalendarSyncController {
  AppointmentCalendarSyncController() : dataSource = AppointmentCalendarDataSource(const []);

  final CalendarController calendarController = CalendarController();
  final AppointmentCalendarDataSource dataSource;

  AppointmentCalendarMode? _lastMode;
  DateTime? _lastSyncedFocusDate;
  int _itemsFingerprint = 0;
  int _resourceFingerprint = 0;
  int _statusFilterFingerprint = 0;
  int _themeFingerprint = -1;
  Brightness _syncedBrightness = Brightness.light;
  Map<String, AppointmentListItem> _itemsById = {};
  List<AppointmentListItem>? _pendingItems;

  AppointmentListItem? itemById(String? id) => id == null ? null : _itemsById[id];

  void onStateChanged({
    required AppointmentCalendarState next,
    required List<AppointmentListItem> visibleItems,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
    required Set<AppointmentStatus> highlightedStatuses,
    required Brightness brightness,
    required bool hasActiveGesture,
  }) {
    _itemsById = {for (final item in next.items) item.id: item};

    if (next.loading) {
      return;
    }

    syncCalendarView(next);

    if (hasActiveGesture) {
      _pendingItems = visibleItems;
      return;
    }

    syncDataSource(
      visibleItems,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
      highlightedStatuses: highlightedStatuses,
      brightness: brightness,
    );
    _pendingItems = null;
  }

  void applyPendingSync({
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
    required Set<AppointmentStatus> highlightedStatuses,
    required Brightness brightness,
  }) {
    final pending = _pendingItems;
    if (pending == null) {
      return;
    }

    syncDataSource(
      pending,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
      highlightedStatuses: highlightedStatuses,
      brightness: brightness,
    );
    _pendingItems = null;
  }

  void syncDataSource(
    List<AppointmentListItem> items, {
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
    required Set<AppointmentStatus> highlightedStatuses,
    required Brightness brightness,
  }) {
    final itemsFingerprint = Object.hashAll(
      items.map(
        (item) => Object.hash(
          item.id,
          item.startTime,
          item.endTime,
          item.status,
          item.doctorId,
          item.patientName,
          item.doctorName,
        ),
      ),
    );
    final resourceFingerprint = Object.hash(
      includeDoctorResources,
      Object.hashAll(doctors.map((doctor) => doctor.id)),
      evenResourceRowColor,
      oddResourceRowColor,
    );
    final statusFilterFingerprint = Object.hashAll(
      highlightedStatuses.toList()..sort((a, b) => a.index.compareTo(b.index)),
    );
    final themeFingerprint = brightness.index;
    if (itemsFingerprint == _itemsFingerprint &&
        resourceFingerprint == _resourceFingerprint &&
        statusFilterFingerprint == _statusFilterFingerprint &&
        themeFingerprint == _themeFingerprint) {
      return;
    }
    _itemsFingerprint = itemsFingerprint;
    _resourceFingerprint = resourceFingerprint;
    _statusFilterFingerprint = statusFilterFingerprint;
    _themeFingerprint = themeFingerprint;
    _syncedBrightness = brightness;
    dataSource.updateItems(
      items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
      highlightedStatuses: highlightedStatuses,
      brightness: brightness,
    );
  }

  void syncCalendarView(AppointmentCalendarState state) {
    final view = calendarViewFor(state.mode);
    if (_lastMode != state.mode) {
      _lastMode = state.mode;
      calendarController.view = view;
    }
    if (_lastSyncedFocusDate != state.focusDate) {
      _lastSyncedFocusDate = state.focusDate;
      calendarController.displayDate = state.focusDate;
    }
  }

  Future<void> onViewChanged(
    ViewChangedDetails details, {
    required AppointmentCalendarController controller,
    required AppointmentCalendarState state,
  }) async {
    final visible = details.visibleDates;
    if (visible.isEmpty) {
      return;
    }

    final calendarView = calendarController.view;
    AppointmentCalendarMode? syncedMode;
    if (calendarView != null) {
      syncedMode = modeForCalendarView(calendarView);
      if (syncedMode != state.mode) {
        await controller.setMode(syncedMode);
      }
    }

    final anchor = visible[visible.length ~/ 2];
    final normalized = DateTime(anchor.year, anchor.month, anchor.day);
    final effectiveMode = syncedMode ?? state.mode;
    if (isSameCalendarPeriod(normalized, state.focusDate, effectiveMode)) {
      return;
    }
    await controller.setFocusDate(normalized);
  }

  void revertItems(
    List<AppointmentListItem> items, {
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
    Brightness? brightness,
  }) {
    dataSource.updateItems(
      items,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
      brightness: brightness ?? _syncedBrightness,
    );
  }

  void applySnappedPreview({
    required List<AppointmentListItem> items,
    required String appointmentId,
    required DateTime newStart,
    required DateTime newEnd,
    required List<StaffListItem> doctors,
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    final previewItems = [
      for (final entry in items)
        if (entry.id == appointmentId) entry.copyWith(startTime: newStart, endTime: newEnd) else entry,
    ];
    revertItems(
      previewItems,
      doctors: doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
  }

  void applyDragPreview(CalendarDragSession session) {
    final duration = session.item.endTime.difference(session.item.startTime);
    final previewEnd = session.previewStart.add(duration);
    final previewItems = [
      for (final entry in session.baseItems)
        if (entry.id == session.item.id)
          entry.copyWith(startTime: session.previewStart, endTime: previewEnd)
        else
          entry,
    ];
    revertItems(
      previewItems,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
  }

  void applyResizePreview(CalendarResizeSession session) {
    final previewItems = [
      for (final entry in session.baseItems)
        if (entry.id == session.item.id)
          entry.copyWith(startTime: session.previewStart, endTime: session.previewEnd)
        else
          entry,
    ];
    revertItems(
      previewItems,
      doctors: session.doctors,
      includeDoctorResources: session.includeDoctorResources,
      evenResourceRowColor: session.evenResourceRowColor,
      oddResourceRowColor: session.oddResourceRowColor,
    );
  }

  void dispose() {
    calendarController.dispose();
  }

  static CalendarView calendarViewFor(AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => CalendarView.day,
      AppointmentCalendarMode.week => CalendarView.week,
      AppointmentCalendarMode.month => CalendarView.month,
      AppointmentCalendarMode.schedule => CalendarView.schedule,
      AppointmentCalendarMode.doctors => CalendarView.timelineDay,
    };
  }

  static double syncfusionViewHeaderHeight(AppointmentCalendarMode mode, bool usesCustomViewHeader) {
    if (usesCustomViewHeader) {
      return 0;
    }

    return switch (mode) {
      AppointmentCalendarMode.month => 25,
      AppointmentCalendarMode.schedule => 0,
      _ => AppointmentCalendarGeometry.viewHeaderHeight,
    };
  }

  static AppointmentCalendarMode modeForCalendarView(CalendarView view) {
    return switch (view) {
      CalendarView.day => AppointmentCalendarMode.day,
      CalendarView.week => AppointmentCalendarMode.week,
      CalendarView.month => AppointmentCalendarMode.month,
      CalendarView.schedule => AppointmentCalendarMode.schedule,
      CalendarView.timelineDay => AppointmentCalendarMode.doctors,
      _ => AppointmentCalendarMode.week,
    };
  }

  static bool isSameCalendarPeriod(DateTime a, DateTime b, AppointmentCalendarMode mode) {
    return switch (mode) {
      AppointmentCalendarMode.day => a.year == b.year && a.month == b.month && a.day == b.day,
      AppointmentCalendarMode.doctors => a.year == b.year && a.month == b.month && a.day == b.day,
      AppointmentCalendarMode.week => weekStart(a) == weekStart(b),
      AppointmentCalendarMode.schedule => weekStart(a) == weekStart(b),
      AppointmentCalendarMode.month => a.year == b.year && a.month == b.month,
    };
  }

  static DateTime weekStart(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    return dayStart.subtract(Duration(days: dayStart.weekday - DateTime.monday));
  }
}
