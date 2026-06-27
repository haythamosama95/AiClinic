import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
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
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/queue_shift_doctor_picker_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';

extension _AppointmentDetailListItem on AppointmentDetail {
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
    );
  }
}

/// Ghost action buttons for managing an appointment from the status journey card.
class AppointmentDetailStatusActions extends ConsumerStatefulWidget {
  const AppointmentDetailStatusActions({required this.detail, super.key});

  final AppointmentDetail detail;

  @override
  ConsumerState<AppointmentDetailStatusActions> createState() => _AppointmentDetailStatusActionsState();
}

class _AppointmentDetailStatusActionsState extends ConsumerState<AppointmentDetailStatusActions> {
  String? _busyActionKey;
  late AppointmentQueueShiftDoctorLookup _shiftLookup;

  AppointmentDetail get detail => widget.detail;

  bool get _isBusy => _busyActionKey != null;

  String get _organizationTimezone =>
      ref.read(authSessionProvider).context?.organizationTimezone?.trim().isNotEmpty == true
      ? ref.read(authSessionProvider).context!.organizationTimezone!.trim()
      : 'UTC';

  PermissionService get _permissions => PermissionService(ref.read(authSessionProvider).context);

  AppointmentListItem get _listItem => detail.toListItem();

  List<AppointmentListItem> get _siblingAppointments {
    final queueItems = ref.read(appointmentQueueProvider).items;
    if (queueItems.isNotEmpty) {
      return queueItems;
    }
    return ref.read(appointmentCalendarProvider).items;
  }

  AppointmentQueueShiftDoctorLookup get _shiftLookupValue => _shiftLookup;

  bool get _canCreateAppointments => _permissions.canCreateAppointments();

  bool get _canCancelAppointments => AuthRouteGuard.canAccessAppointmentCancelActions(ref.read(authSessionProvider));

  String? _busyBlockedReason(String actionKey) {
    if (_busyActionKey != null && _busyActionKey != actionKey) {
      return 'Please wait for the current action to finish.';
    }
    return null;
  }

  String? _permissionDeniedCreateReason() {
    if (_canCreateAppointments) {
      return null;
    }
    return 'You do not have permission to manage appointments.';
  }

  String? _permissionDeniedCancelReason() {
    if (_canCancelAppointments) {
      return null;
    }
    return 'You do not have permission to cancel appointments.';
  }

  String _advanceStatusLabel() {
    final activeLabel = forwardStatusActionLabelFor(
      _listItem,
      organizationTimezone: _organizationTimezone,
      siblingAppointments: _siblingAppointments,
      shiftLookup: _shiftLookupValue,
    );
    if (activeLabel.isNotEmpty) {
      return activeLabel;
    }
    return switch (detail.status) {
      AppointmentStatus.scheduled => 'Confirm',
      AppointmentStatus.confirmed => 'Check in',
      AppointmentStatus.checkedIn => 'Start',
      AppointmentStatus.inProgress => 'Complete',
      _ => 'Advance status',
    };
  }

  String? _advanceStatusDisabledReason() {
    final permission = _permissionDeniedCreateReason();
    if (permission != null) {
      return permission;
    }
    if (detail.status.isTerminal) {
      return 'This appointment is ${detail.status.label.toLowerCase()} and cannot be advanced further.';
    }
    if (detail.status == AppointmentStatus.inProgress) {
      return 'Complete this appointment from the visit workflow.';
    }

    final target = switch (detail.status) {
      AppointmentStatus.scheduled => AppointmentStatus.confirmed,
      AppointmentStatus.confirmed => AppointmentStatus.checkedIn,
      AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
      _ => null,
    };
    if (target == null) {
      return 'No further status change is available.';
    }
    if (!canTransitionToStatusOnDate(target, detail.startTime, organizationTimezone: _organizationTimezone)) {
      return switch (target) {
        AppointmentStatus.checkedIn => 'Check-in is only available on the appointment day.',
        AppointmentStatus.inProgress => 'Starting is only available on the appointment day.',
        _ => 'This status change is only available on the appointment day.',
      };
    }
    if (target == AppointmentStatus.inProgress) {
      return AppointmentQueueDisplay.doctorInProgressBlockReason(
        _listItem,
        _siblingAppointments,
        shiftLookup: _shiftLookupValue,
      );
    }
    return null;
  }

  String? _markNoShowDisabledReason() {
    final permission = _permissionDeniedCancelReason();
    if (permission != null) {
      return permission;
    }
    if (!detail.status.canTransitionTo(AppointmentStatus.noShow)) {
      return 'No-show cannot be recorded for ${detail.status.label.toLowerCase()} appointments.';
    }
    if (!canTransitionToStatusOnDate(
      AppointmentStatus.noShow,
      detail.startTime,
      organizationTimezone: _organizationTimezone,
    )) {
      return 'No-show can only be marked on or after the appointment day.';
    }
    return null;
  }

  String? _cancelDisabledReason() {
    final permission = _permissionDeniedCancelReason();
    if (permission != null) {
      return permission;
    }
    if (canCancelAppointment(_listItem)) {
      return null;
    }
    return 'This appointment cannot be cancelled in its current status.';
  }

  String? _disabledReasonFor(String actionKey, String? businessReason) {
    return _busyBlockedReason(actionKey) ?? businessReason;
  }

  Future<void> _runAction(String actionKey, Future<void> Function() action) async {
    if (_isBusy) {
      return;
    }
    setState(() => _busyActionKey = actionKey);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busyActionKey = null);
      }
    }
  }

  Future<String?> _resolveDoctorForStart() async {
    final options = AppointmentQueueStartDoctor.optionsForStart(
      item: _listItem,
      siblingAppointments: _siblingAppointments,
      shiftLookup: _shiftLookupValue,
    );
    if (!mounted) {
      return null;
    }
    return QueueShiftDoctorPickerDialog.show(context, options: options);
  }

  Future<void> _assignDoctorIfNeeded(String doctorId) async {
    final currentDoctorId = detail.doctorId?.trim();
    if (currentDoctorId != null && currentDoctorId.isNotEmpty && currentDoctorId == doctorId) {
      return;
    }

    await ref
        .read(appointmentRepositoryProvider)
        .updateAppointment(
          appointmentId: detail.id,
          patientId: detail.patientId,
          doctorId: doctorId,
          startTime: detail.startTime,
          endTime: detail.endTime,
        );
  }

  String? _doctorNameForId(String doctorId) {
    final trimmed = doctorId.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final assignedDoctorId = detail.doctorId?.trim();
    if (assignedDoctorId == trimmed && detail.doctorName?.trim().isNotEmpty == true) {
      return detail.doctorName!.trim();
    }

    for (final doctor in _shiftLookup.doctorsOnShiftAt(detail.startTime)) {
      if (doctor.id == trimmed) {
        return doctor.name;
      }
    }

    for (final item in _siblingAppointments) {
      if (item.doctorId == trimmed && item.doctorName?.trim().isNotEmpty == true) {
        return item.doctorName!.trim();
      }
    }
    return null;
  }

  void _patchQueueAfterStatusChange({
    required AppointmentStatus newStatus,
    String? doctorId,
    DateTime? updatedAt,
    DateTime? checkedInAt,
    DateTime? inProgressAt,
  }) {
    ref
        .read(appointmentQueueProvider.notifier)
        .patchAppointmentStatus(
          appointmentId: detail.id,
          newStatus: newStatus,
          doctorId: doctorId,
          doctorName: doctorId == null ? null : _doctorNameForId(doctorId),
          updatedAt: updatedAt,
          checkedInAt: checkedInAt,
          inProgressAt: inProgressAt,
        );
  }

  Future<void> _revertDoctorAssignment({required String? originalDoctorId}) async {
    final revertTo = originalDoctorId?.trim();
    try {
      await ref
          .read(appointmentRepositoryProvider)
          .updateAppointment(
            appointmentId: detail.id,
            patientId: detail.patientId,
            doctorId: revertTo != null && revertTo.isNotEmpty ? revertTo : null,
            startTime: detail.startTime,
            endTime: detail.endTime,
          );
    } catch (error) {
      debugPrint('AppointmentDetailStatusActions._revertDoctorAssignment failed: $error');
    }
  }

  Future<void> _handleAdvanceStatus() async {
    if (_disabledReasonFor('advance', _advanceStatusDisabledReason()) != null) {
      return;
    }

    final target = forwardStatusTargetFor(
      _listItem,
      organizationTimezone: _organizationTimezone,
      siblingAppointments: _siblingAppointments,
      shiftLookup: _shiftLookupValue,
    );
    if (target == null) {
      return;
    }

    String? doctorIdForStart;
    if (target == AppointmentStatus.inProgress &&
        AppointmentQueueStartDoctor.requiresDoctorPicker(
          item: _listItem,
          shiftLookup: _shiftLookupValue,
          siblingAppointments: _siblingAppointments,
        )) {
      doctorIdForStart = await _resolveDoctorForStart();
      if (doctorIdForStart == null) {
        return;
      }
    }

    await _runAction('advance', () async {
      final originalDoctorId = detail.doctorId?.trim();
      var didAssignDoctor = false;
      try {
        if (doctorIdForStart != null) {
          await _assignDoctorIfNeeded(doctorIdForStart);
          didAssignDoctor = true;
        }
        final update = await ref
            .read(appointmentRepositoryProvider)
            .updateAppointmentStatus(appointmentId: detail.id, newStatus: target);
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(detail.id));
        ref.invalidate(appointmentCalendarProvider);
        _patchQueueAfterStatusChange(
          newStatus: target,
          doctorId: doctorIdForStart,
          updatedAt: update.updatedAt,
          checkedInAt: update.checkedInAt,
          inProgressAt: update.inProgressAt,
        );
        AppToast.success(context, message: 'Appointment marked as ${target.label.toLowerCase()}.');
      } on RpcFailure catch (error) {
        if (didAssignDoctor) {
          await _revertDoctorAssignment(originalDoctorId: originalDoctorId);
        }
        if (mounted) {
          AppToast.error(context, message: appointmentMessageForRpc(error));
        }
      } catch (_) {
        if (didAssignDoctor) {
          await _revertDoctorAssignment(originalDoctorId: originalDoctorId);
        }
        if (mounted) {
          AppToast.error(context, message: 'Unable to update status. Try again.');
        }
      }
    });
  }

  Future<void> _handleCancel() async {
    if (_disabledReasonFor('cancel', _cancelDisabledReason()) != null) {
      return;
    }

    final reason = await AppointmentCancelDialog.show(context, patientName: detail.patientName);
    if (!mounted || reason == null) {
      return;
    }

    await _runAction('cancel', () async {
      try {
        await ref
            .read(appointmentRepositoryProvider)
            .cancelAppointment(appointmentId: detail.id, reason: reason.isEmpty ? null : reason);
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(detail.id));
        ref.invalidate(appointmentCalendarProvider);
        _patchQueueAfterStatusChange(newStatus: AppointmentStatus.cancelled);
        AppToast.success(context, message: 'Appointment cancelled.');
      } on RpcFailure catch (error) {
        if (mounted) {
          AppToast.error(context, message: appointmentMessageForRpc(error));
        }
      } catch (_) {
        if (mounted) {
          AppToast.error(context, message: 'Unable to cancel appointment. Try again.');
        }
      }
    });
  }

  Future<void> _handleMarkNoShow() async {
    if (_disabledReasonFor('no_show', _markNoShowDisabledReason()) != null) {
      return;
    }

    await AppDialog.showConfirmation(
      context: context,
      title: 'Mark as no-show?',
      message: '${detail.patientName} did not attend this appointment. The slot will be closed as a no-show.',
      confirmLabel: 'Mark no-show',
      cancelLabel: 'Keep status',
      destructive: true,
      onConfirm: () async {
        await _runAction('no_show', () async {
          try {
            await ref.read(appointmentRepositoryProvider).markAppointmentNoShow(appointmentId: detail.id);
            if (!mounted) {
              return;
            }
            ref.invalidate(appointmentDetailProvider(detail.id));
            ref.invalidate(appointmentCalendarProvider);
            _patchQueueAfterStatusChange(newStatus: AppointmentStatus.noShow);
            AppToast.success(context, message: 'Appointment marked as no-show.');
          } on RpcFailure catch (error) {
            if (mounted) {
              AppToast.error(context, message: appointmentMessageForRpc(error));
            }
          } catch (_) {
            if (mounted) {
              AppToast.error(context, message: 'Unable to mark no-show. Try again.');
            }
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _shiftLookup =
        ref.watch(appointmentQueueShiftDoctorLookupProvider).value ?? AppointmentQueueShiftDoctorLookup.empty;

    final specs = <_StatusActionSpec>[
      _StatusActionSpec(
        key: const Key('appointment_control_advance_status'),
        icon: Icons.play_arrow_rounded,
        label: _advanceStatusLabel(),
        disabledReason: _disabledReasonFor('advance', _advanceStatusDisabledReason()),
        isLoading: _busyActionKey == 'advance',
        onPressed: _handleAdvanceStatus,
      ),
      _StatusActionSpec(
        key: const Key('appointment_control_no_show'),
        icon: Icons.person_off_outlined,
        label: 'Mark no-show',
        disabledReason: _disabledReasonFor('no_show', _markNoShowDisabledReason()),
        isLoading: _busyActionKey == 'no_show',
        onPressed: _handleMarkNoShow,
      ),
      _StatusActionSpec(
        key: const Key('appointment_control_cancel'),
        icon: Icons.event_busy_outlined,
        label: 'Cancel appointment',
        disabledReason: _disabledReasonFor('cancel', _cancelDisabledReason()),
        isLoading: _busyActionKey == 'cancel',
        onPressed: _handleCancel,
      ),
    ];

    specs.sort((a, b) {
      final aBlocked = a.disabledReason != null;
      final bBlocked = b.disabledReason != null;
      if (aBlocked != bBlocked) {
        return aBlocked ? 1 : -1;
      }
      return 0;
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final useStacked = constraints.maxWidth < 280;

        if (useStacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < specs.length; i++) ...[
                if (i > 0) const SizedBox(height: SpacingTokens.xs),
                _StatusActionButton(spec: specs[i], expand: true),
              ],
            ],
          );
        }

        return Wrap(
          spacing: SpacingTokens.xs,
          runSpacing: SpacingTokens.xs,
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final spec in specs) _StatusActionButton(spec: spec)],
        );
      },
    );
  }
}

class _StatusActionSpec {
  const _StatusActionSpec({
    required this.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.disabledReason,
    this.isLoading = false,
  });

  final Key key;
  final IconData icon;
  final String label;
  final String? disabledReason;
  final bool isLoading;
  final VoidCallback onPressed;
}

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({required this.spec, this.expand = false});

  final _StatusActionSpec spec;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final isInteractive = spec.disabledReason == null;

    final button = AppButton(
      key: spec.key,
      label: spec.label,
      variant: AppButtonVariant.ghost,
      size: AppFieldSize.sm,
      expand: expand,
      icon: Icon(spec.icon, size: 18),
      isLoading: spec.isLoading,
      onPressed: isInteractive ? spec.onPressed : null,
    );

    if (!isInteractive) {
      return Tooltip(message: spec.disabledReason!, child: button);
    }

    return button;
  }
}
