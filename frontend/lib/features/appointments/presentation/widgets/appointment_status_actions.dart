import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_shift_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue_shift_doctor_picker_dialog.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

extension AppointmentDetailListItem on AppointmentDetail {
  AppointmentListItem toListItem() {
    return AppointmentListItem(
      id: id,
      patientId: patientId,
      patientName: patientName,
      doctorId: doctorId,
      doctorName: doctorName,
      startTime: startTime,
      endTime: endTime,
      type: type,
      status: status,
      updatedAt: updatedAt,
    );
  }
}

/// Status advance / cancel / no-show actions for appointment detail and queue rows.
class AppointmentStatusActions extends ConsumerStatefulWidget {
  const AppointmentStatusActions({
    required this.detail,
    this.compact = false,
    super.key,
  }) : listItem = null;

  const AppointmentStatusActions.fromListItem({
    required AppointmentListItem item,
    this.compact = true,
    super.key,
  }) : detail = null,
       listItem = item;

  final AppointmentDetail? detail;
  final AppointmentListItem? listItem;
  final bool compact;

  @override
  ConsumerState<AppointmentStatusActions> createState() => _AppointmentStatusActionsState();
}

class _AppointmentStatusActionsState extends ConsumerState<AppointmentStatusActions> {
  String? _busyActionKey;

  AppointmentListItem get _item {
    if (widget.detail != null) {
      return widget.detail!.toListItem();
    }
    return widget.listItem!;
  }

  bool get _isBusy => _busyActionKey != null;

  String get _organizationTimezone =>
      effectiveOrganizationTimezone(ref.read(authSessionProvider).context?.organizationTimezone);

  bool get _canCreateAppointments => AuthRouteGuard.canAccessAppointmentBooking(ref.read(authSessionProvider));

  bool get _canCancelAppointments => AuthRouteGuard.canAccessAppointmentCancelActions(ref.read(authSessionProvider));

  List<AppointmentListItem> get _siblingAppointments {
    final queueItems = ref.read(appointmentQueueProvider).items;
    if (queueItems.isNotEmpty) {
      return queueItems;
    }
    return ref.read(appointmentCalendarProvider).items;
  }

  AppointmentQueueShiftDoctorLookup get _shiftLookup =>
      ref.watch(appointmentQueueShiftDoctorLookupProvider).value ?? AppointmentQueueShiftDoctorLookup.empty;

  Future<void> _runAction(String key, Future<void> Function() action) async {
    if (_isBusy) {
      return;
    }
    setState(() => _busyActionKey = key);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busyActionKey = null);
      }
    }
  }

  void _patchQueueAfterStatusChange({
    required AppointmentStatus newStatus,
    String? doctorId,
    DateTime? updatedAt,
    DateTime? checkedInAt,
    DateTime? inProgressAt,
  }) {
    ref.read(appointmentQueueProvider.notifier).patchAppointmentStatus(
      appointmentId: _item.id,
      newStatus: newStatus,
      doctorId: doctorId,
      doctorName: doctorId == null ? null : _doctorNameForId(doctorId),
      updatedAt: updatedAt,
      checkedInAt: checkedInAt,
      inProgressAt: inProgressAt,
    );
  }

  String? _doctorNameForId(String doctorId) {
    final doctors = ref.read(appointmentCalendarDoctorsProvider).value ?? const <StaffListItem>[];
    for (final doctor in doctors) {
      if (doctor.id == doctorId) {
        return doctor.fullName;
      }
    }
    return null;
  }

  Future<String?> _resolveDoctorForStart() {
    final options = AppointmentQueueStartDoctor.optionsForStart(
      item: _item,
      siblingAppointments: _siblingAppointments,
      shiftLookup: _shiftLookup,
    );
    return showQueueShiftDoctorPickerDialog(context, options: options);
  }

  Future<void> _assignDoctorIfNeeded(String doctorId) async {
    final detail = widget.detail;
    if (detail == null) {
      return;
    }
    if (detail.doctorId?.trim() == doctorId.trim()) {
      return;
    }
    await ref.read(appointmentRepositoryProvider).updateAppointment(
      appointmentId: detail.id,
      patientId: detail.patientId,
      doctorId: doctorId,
      startTime: detail.startTime,
      endTime: detail.endTime,
      notes: detail.notes,
    );
  }

  Future<void> _revertDoctorAssignment({required String? originalDoctorId}) async {
    final detail = widget.detail;
    if (detail == null) {
      return;
    }
    final revertTo = originalDoctorId?.trim();
    try {
      await ref.read(appointmentRepositoryProvider).updateAppointment(
        appointmentId: detail.id,
        patientId: detail.patientId,
        doctorId: revertTo != null && revertTo.isNotEmpty ? revertTo : null,
        startTime: detail.startTime,
        endTime: detail.endTime,
        notes: detail.notes,
      );
    } catch (error) {
      debugPrint('AppointmentStatusActions._revertDoctorAssignment failed: $error');
    }
  }

  String _advanceStatusLabel() {
    final activeLabel = forwardStatusActionLabelFor(
      _item,
      organizationTimezone: _organizationTimezone,
      siblingAppointments: _siblingAppointments,
      shiftLookup: _shiftLookup,
    );
    if (activeLabel.isNotEmpty) {
      return activeLabel;
    }
    return switch (_item.status) {
      AppointmentStatus.scheduled => 'Confirm',
      AppointmentStatus.confirmed => 'Check in',
      AppointmentStatus.checkedIn => 'Start',
      AppointmentStatus.inProgress => 'Complete',
      _ => 'Advance status',
    };
  }

  String? _advanceStatusDisabledReason() {
    if (!_canCreateAppointments) {
      return 'You do not have permission to manage appointments.';
    }
    if (_item.status.isTerminal) {
      return 'This appointment is ${_item.status.label.toLowerCase()} and cannot be advanced further.';
    }
    if (_item.status == AppointmentStatus.inProgress) {
      return 'Complete this appointment from the visit workflow.';
    }

    final target = switch (_item.status) {
      AppointmentStatus.scheduled => AppointmentStatus.confirmed,
      AppointmentStatus.confirmed => AppointmentStatus.checkedIn,
      AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
      _ => null,
    };
    if (target == null) {
      return 'No further status change is available.';
    }
    if (!canTransitionToStatusOnDate(target, _item.startTime, organizationTimezone: _organizationTimezone)) {
      return switch (target) {
        AppointmentStatus.checkedIn => 'Check-in is only available on the appointment day.',
        AppointmentStatus.inProgress => 'Starting is only available on the appointment day.',
        _ => 'This status change is only available on the appointment day.',
      };
    }
    if (target == AppointmentStatus.inProgress) {
      return AppointmentQueueDisplay.doctorInProgressBlockReason(
        _item,
        _siblingAppointments,
        shiftLookup: _shiftLookup,
      );
    }
    return null;
  }

  String? _markNoShowDisabledReason() {
    if (!_canCancelAppointments) {
      return 'You do not have permission to cancel appointments.';
    }
    if (!canMarkNoShowAppointment(_item, organizationTimezone: _organizationTimezone)) {
      return 'No-show is only available on or after the appointment day.';
    }
    return null;
  }

  String? _cancelDisabledReason() {
    if (!_canCancelAppointments) {
      return 'You do not have permission to cancel appointments.';
    }
    if (!canCancelAppointment(_item)) {
      return 'This appointment cannot be cancelled in its current status.';
    }
    return null;
  }

  Future<void> _handleAdvanceStatus() async {
    final disabled = _advanceStatusDisabledReason();
    if (disabled != null || _isBusy) {
      return;
    }

    final target = forwardStatusTargetFor(
      _item,
      organizationTimezone: _organizationTimezone,
      siblingAppointments: _siblingAppointments,
      shiftLookup: _shiftLookup,
    );
    if (target == null) {
      return;
    }

    String? doctorIdForStart;
    if (target == AppointmentStatus.inProgress &&
        AppointmentQueueStartDoctor.requiresDoctorPicker(
          item: _item,
          shiftLookup: _shiftLookup,
          siblingAppointments: _siblingAppointments,
        )) {
      doctorIdForStart = await _resolveDoctorForStart();
      if (doctorIdForStart == null) {
        return;
      }
    }

    await _runAction('advance', () async {
      final originalDoctorId = widget.detail?.doctorId?.trim();
      var didAssignDoctor = false;
      try {
        if (doctorIdForStart != null) {
          await _assignDoctorIfNeeded(doctorIdForStart);
          didAssignDoctor = true;
        }
        final update = await ref
            .read(appointmentRepositoryProvider)
            .updateAppointmentStatus(appointmentId: _item.id, newStatus: target);
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(_item.id));
        ref.invalidate(appointmentCalendarProvider);
        _patchQueueAfterStatusChange(
          newStatus: target,
          doctorId: doctorIdForStart,
          updatedAt: update.updatedAt,
          checkedInAt: update.checkedInAt,
          inProgressAt: update.inProgressAt,
        );
        ref.showAppToast(
          message: 'Appointment marked as ${target.label.toLowerCase()}.',
          variant: AppToastVariant.success,
        );
      } on RpcFailure catch (error) {
        if (didAssignDoctor) {
          await _revertDoctorAssignment(originalDoctorId: originalDoctorId);
        }
        if (mounted) {
          ref.showAppToast(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger);
        }
      } catch (_) {
        if (didAssignDoctor) {
          await _revertDoctorAssignment(originalDoctorId: originalDoctorId);
        }
        if (mounted) {
          ref.showAppToast(message: 'Unable to update status. Try again.', variant: AppToastVariant.danger);
        }
      }
    });
  }

  Future<void> _handleCancel() async {
    if (_cancelDisabledReason() != null || _isBusy) {
      return;
    }

    final reason = await showAppointmentCancelDialog(context, patientName: _item.patientName);
    if (!mounted || reason == null) {
      return;
    }

    await _runAction('cancel', () async {
      try {
        await ref.read(appointmentRepositoryProvider).cancelAppointment(
          appointmentId: _item.id,
          reason: reason.isEmpty ? null : reason,
        );
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(_item.id));
        ref.invalidate(appointmentCalendarProvider);
        _patchQueueAfterStatusChange(newStatus: AppointmentStatus.cancelled);
        ref.showAppToast(message: 'Appointment cancelled.', variant: AppToastVariant.success);
      } on RpcFailure catch (error) {
        if (mounted) {
          ref.showAppToast(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger);
        }
      } catch (_) {
        if (mounted) {
          ref.showAppToast(message: 'Unable to cancel appointment. Try again.', variant: AppToastVariant.danger);
        }
      }
    });
  }

  Future<void> _handleMarkNoShow() async {
    if (_markNoShowDisabledReason() != null || _isBusy) {
      return;
    }

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Mark as no-show?',
      message: '${_item.patientName} did not attend this appointment. The slot will be closed as a no-show.',
      confirmLabel: 'Mark no-show',
      cancelLabel: 'Keep status',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }

    await _runAction('no_show', () async {
      try {
        await ref.read(appointmentRepositoryProvider).markAppointmentNoShow(appointmentId: _item.id);
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(_item.id));
        ref.invalidate(appointmentCalendarProvider);
        _patchQueueAfterStatusChange(newStatus: AppointmentStatus.noShow);
        ref.showAppToast(message: 'Appointment marked as no-show.', variant: AppToastVariant.success);
      } on RpcFailure catch (error) {
        if (mounted) {
          ref.showAppToast(message: appointmentMessageForRpc(error), variant: AppToastVariant.danger);
        }
      } catch (_) {
        if (mounted) {
          ref.showAppToast(message: 'Unable to mark no-show. Try again.', variant: AppToastVariant.danger);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final advanceLabel = _advanceStatusLabel();
    final advanceDisabled = _advanceStatusDisabledReason();
    final noShowDisabled = _markNoShowDisabledReason();
    final cancelDisabled = _cancelDisabledReason();

    if (widget.compact) {
      final label = advanceDisabled == null ? advanceLabel : advanceLabel;
      if (label.isEmpty && cancelDisabled != null && noShowDisabled != null) {
        return const SizedBox.shrink();
      }
      return AppButton(
        key: Key('appointment_status_advance_${_item.id}'),
        label: label.isEmpty ? 'Manage' : label,
        size: AppButtonSize.sm,
        variant: AppButtonVariant.secondary,
        loading: _busyActionKey == 'advance',
        onPressed: advanceDisabled == null && label.isNotEmpty ? _handleAdvanceStatus : null,
      );
    }

    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: [
        AppButton(
          key: const Key('appointment_control_advance_status'),
          label: advanceLabel,
          size: AppButtonSize.sm,
          loading: _busyActionKey == 'advance',
          onPressed: advanceDisabled == null ? _handleAdvanceStatus : null,
        ),
        AppButton(
          key: const Key('appointment_control_no_show'),
          label: 'Mark no-show',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.secondary,
          loading: _busyActionKey == 'no_show',
          onPressed: noShowDisabled == null ? _handleMarkNoShow : null,
        ),
        AppButton(
          key: const Key('appointment_control_cancel'),
          label: 'Cancel appointment',
          size: AppButtonSize.sm,
          variant: AppButtonVariant.ghost,
          loading: _busyActionKey == 'cancel',
          onPressed: cancelDisabled == null ? _handleCancel : null,
        ),
      ],
    );
  }
}
