import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_shift_doctors.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_detail_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_start_doctor_dialog.dart';

/// Inline outlined action buttons for managing an appointment from the status journey card.
class AppointmentDetailStatusActions extends ConsumerStatefulWidget {
  const AppointmentDetailStatusActions({
    required this.detail,
    required this.siblingAppointments,
    required this.shiftLookup,
    required this.onChanged,
    super.key,
  });

  final AppointmentDetail detail;
  final List<AppointmentListItem> siblingAppointments;
  final AppointmentQueueShiftDoctorLookup shiftLookup;
  final VoidCallback onChanged;

  @override
  ConsumerState<AppointmentDetailStatusActions> createState() =>
      _AppointmentDetailStatusActionsState();
}

class _AppointmentDetailStatusActionsState
    extends ConsumerState<AppointmentDetailStatusActions> {
  String? _busyActionKey;

  AppointmentDetail get detail => widget.detail;

  bool get _isBusy => _busyActionKey != null;

  String get _organizationTimezone => effectiveOrganizationTimezone(
    ref.read(authSessionProvider).context?.organizationTimezone,
  );

  AppointmentListItem get _listItem => detail.toListItem();

  bool get _canAdvance => ref.watch(
    authSessionProvider.select(AuthRouteGuard.canAccessAppointmentBooking),
  );

  bool get _canCancel => ref.watch(
    authSessionProvider.select(
      AuthRouteGuard.canAccessAppointmentCancelActions,
    ),
  );

  AppointmentStatus? get _forwardTarget => forwardStatusTargetFor(
    _listItem,
    organizationTimezone: _organizationTimezone,
    siblingAppointments: widget.siblingAppointments,
    shiftLookup: widget.shiftLookup,
  );

  AppointmentStatus? get _revertTarget => previousStatusTargetFor(_listItem);

  String get _revertLabel => revertStatusActionLabelFor(_listItem);

  String get _forwardLabel => forwardStatusActionLabelFor(
    _listItem,
    organizationTimezone: _organizationTimezone,
    siblingAppointments: widget.siblingAppointments,
    shiftLookup: widget.shiftLookup,
  );

  String get _displayForwardLabel {
    final label = _forwardLabel;
    if (label.isNotEmpty) {
      return label;
    }
    return switch (detail.status) {
      AppointmentStatus.scheduled => 'Confirm',
      AppointmentStatus.confirmed => 'Check in',
      AppointmentStatus.checkedIn => 'Start',
      _ => 'Advance status',
    };
  }

  bool get _canMarkNoShow => canMarkNoShowAppointment(
    _listItem,
    organizationTimezone: _organizationTimezone,
    referenceUtc: DateTime.now().toUtc(),
  );

  String? _busyBlockedReason(String actionKey) {
    if (_busyActionKey != null && _busyActionKey != actionKey) {
      return 'Please wait for the current action to finish.';
    }
    return null;
  }

  String? _advanceDisabledReason() {
    if (!_canAdvance) {
      return 'You do not have permission to manage appointments.';
    }
    if (detail.status.isTerminal) {
      return 'This appointment is ${detail.status.label.toLowerCase()} and cannot be advanced further.';
    }
    if (detail.status == AppointmentStatus.inProgress) {
      return 'Complete this appointment from the visit workflow.';
    }
    final target = _forwardTarget;
    if (target == null || _forwardLabel.isEmpty) {
      return 'No further status change is available.';
    }
    if (target == AppointmentStatus.inProgress) {
      return AppointmentQueueStartDoctor.blockReasonForStart(
        item: _listItem,
        siblingAppointments: widget.siblingAppointments,
        shiftLookup: widget.shiftLookup,
      );
    }
    return null;
  }

  String? _revertDisabledReason() {
    if (!_canAdvance) {
      return 'You do not have permission to manage appointments.';
    }
    if (_revertTarget == null) {
      return 'There is no previous status to revert to.';
    }
    return null;
  }

  String? _markNoShowDisabledReason() {
    if (!_canCancel) {
      return 'You do not have permission to cancel appointments.';
    }
    if (!_canMarkNoShow) {
      return 'No-show cannot be recorded for ${detail.status.label.toLowerCase()} appointments.';
    }
    return null;
  }

  String? _cancelDisabledReason() {
    if (!_canCancel) {
      return 'You do not have permission to cancel appointments.';
    }
    if (canCancelAppointment(_listItem)) {
      return null;
    }
    return 'This appointment cannot be cancelled in its current status.';
  }

  String? _disabledReasonFor(String actionKey, String? businessReason) {
    return _busyBlockedReason(actionKey) ?? businessReason;
  }

  Future<void> _runAction(
    String actionKey,
    Future<void> Function() action,
  ) async {
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
    final item = _listItem;
    if (!AppointmentQueueStartDoctor.requiresDoctorPicker(
      item: item,
      shiftLookup: widget.shiftLookup,
      siblingAppointments: widget.siblingAppointments,
    )) {
      final assigned = item.doctorId?.trim();
      if (assigned != null && assigned.isNotEmpty) {
        return assigned;
      }
      final options = AppointmentQueueStartDoctor.optionsForStart(
        item: item,
        siblingAppointments: widget.siblingAppointments,
        shiftLookup: widget.shiftLookup,
      );
      return options.where((option) => !option.isBusy).firstOrNull?.id;
    }

    final options = AppointmentQueueStartDoctor.optionsForStart(
      item: item,
      siblingAppointments: widget.siblingAppointments,
      shiftLookup: widget.shiftLookup,
    );
    if (!mounted) {
      return null;
    }
    return AppointmentStartDoctorDialog.show(context, options: options);
  }

  Future<void> _handleAdvanceStatus() async {
    if (_disabledReasonFor('advance', _advanceDisabledReason()) != null) {
      return;
    }

    final target = _forwardTarget;
    if (target == null) {
      return;
    }

    await _runAction('advance', () async {
      try {
        var workingDetail = detail;

        if (target == AppointmentStatus.inProgress) {
          final selectedDoctorId = await _resolveDoctorForStart();
          if (!mounted || selectedDoctorId == null) {
            return;
          }

          final assignedDoctorId = workingDetail.doctorId?.trim();
          if (assignedDoctorId == null ||
              assignedDoctorId.isEmpty ||
              assignedDoctorId != selectedDoctorId) {
            await ref
                .read(appointmentRepositoryProvider)
                .updateAppointment(
                  appointmentId: workingDetail.id,
                  patientId: workingDetail.patientId,
                  doctorId: selectedDoctorId,
                  startTime: workingDetail.startTime,
                  endTime: workingDetail.endTime,
                );
          }
        }

        await ref
            .read(appointmentRepositoryProvider)
            .updateAppointmentStatus(
              appointmentId: workingDetail.id,
              newStatus: target,
            );

        if (!mounted) {
          return;
        }
        widget.onChanged();
        appToast(
          context,
          AppToastInput(
            message:
                '${workingDetail.patientName} is now ${target.label.toLowerCase()}.',
            variant: AppToastVariant.success,
          ),
        );
      } on RpcFailure catch (error) {
        if (mounted) {
          appToast(
            context,
            AppToastInput(
              message: appointmentMessageForRpc(error),
              variant: AppToastVariant.danger,
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          appToast(
            context,
            const AppToastInput(
              message:
                  'Could not update the appointment status. Please try again.',
              variant: AppToastVariant.danger,
            ),
          );
        }
      }
    });
  }

  Future<void> _handleRevertStatus() async {
    if (_disabledReasonFor('revert', _revertDisabledReason()) != null) {
      return;
    }

    final target = _revertTarget;
    if (target == null) {
      return;
    }

    final confirmed = await AppDialog.show<bool>(
      context,
      title: 'Revert to ${target.label.toLowerCase()}?',
      description:
          'This will undo the last status change for ${detail.patientName}.',
      size: AppDialogSize.sm,
      child: Builder(
        builder: (dialogContext) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep current status'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              variant: AppButtonVariant.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_revertLabel),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _runAction('revert', () async {
      try {
        await ref
            .read(appointmentRepositoryProvider)
            .updateAppointmentStatus(
              appointmentId: detail.id,
              newStatus: target,
            );

        if (!mounted) {
          return;
        }
        widget.onChanged();
        appToast(
          context,
          AppToastInput(
            message:
                '${detail.patientName} is back to ${target.label.toLowerCase()}.',
            variant: AppToastVariant.success,
          ),
        );
      } on RpcFailure catch (error) {
        if (mounted) {
          appToast(
            context,
            AppToastInput(
              message: appointmentMessageForRpc(error),
              variant: AppToastVariant.danger,
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          appToast(
            context,
            const AppToastInput(
              message:
                  'Could not revert the appointment status. Please try again.',
              variant: AppToastVariant.danger,
            ),
          );
        }
      }
    });
  }

  Future<void> _handleCancel() async {
    if (_disabledReasonFor('cancel', _cancelDisabledReason()) != null) {
      return;
    }

    final reason = await AppointmentCancelDialog.show(
      context,
      appointment: _listItem,
    );
    if (!mounted || reason == null) {
      return;
    }

    await _runAction('cancel', () async {
      try {
        await ref
            .read(appointmentRepositoryProvider)
            .cancelAppointment(appointmentId: detail.id, reason: reason);
        if (!mounted) {
          return;
        }
        widget.onChanged();
        appToast(
          context,
          AppToastInput(
            message: '${detail.patientName}\'s appointment was cancelled.',
            variant: AppToastVariant.success,
          ),
        );
      } on RpcFailure catch (error) {
        if (mounted) {
          appToast(
            context,
            AppToastInput(
              message: appointmentMessageForRpc(error),
              variant: AppToastVariant.danger,
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          appToast(
            context,
            const AppToastInput(
              message: 'Could not cancel the appointment. Please try again.',
              variant: AppToastVariant.danger,
            ),
          );
        }
      }
    });
  }

  Future<void> _handleMarkNoShow() async {
    if (_disabledReasonFor('no_show', _markNoShowDisabledReason()) != null) {
      return;
    }

    final confirmed = await AppDialog.show<bool>(
      context,
      title: 'Mark as no-show?',
      description:
          'Record that ${detail.patientName} did not arrive for this visit.',
      size: AppDialogSize.sm,
      child: Builder(
        builder: (dialogContext) => Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep appointment'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              variant: AppButtonVariant.danger,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Mark no-show'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _runAction('no_show', () async {
      try {
        await ref
            .read(appointmentRepositoryProvider)
            .markAppointmentNoShow(appointmentId: detail.id);
        if (!mounted) {
          return;
        }
        widget.onChanged();
        appToast(
          context,
          AppToastInput(
            message: '${detail.patientName} was marked as a no-show.',
            variant: AppToastVariant.success,
          ),
        );
      } on RpcFailure catch (error) {
        if (mounted) {
          appToast(
            context,
            AppToastInput(
              message: appointmentMessageForRpc(error),
              variant: AppToastVariant.danger,
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          appToast(
            context,
            const AppToastInput(
              message:
                  'Could not mark the appointment as a no-show. Please try again.',
              variant: AppToastVariant.danger,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final currentStatusColor = AppointmentCalendarDisplay.statusColor(
      detail.status,
      brightness,
    );

    final specs = <_StatusActionSpec>[
      if (_revertTarget != null)
        _StatusActionSpec(
          key: const Key('appointment_control_revert_status'),
          icon: Icons.undo_outlined,
          label: _revertLabel,
          disabledReason: _disabledReasonFor('revert', _revertDisabledReason()),
          isLoading: _busyActionKey == 'revert',
          onPressed: _handleRevertStatus,
          backgroundGradient: LinearGradient(
            colors: [
              currentStatusColor,
              AppointmentCalendarDisplay.statusColor(
                _revertTarget!,
                brightness,
              ),
            ],
          ),
        ),
      _StatusActionSpec(
        key: const Key('appointment_control_advance_status'),
        icon: Icons.play_arrow_rounded,
        label: _displayForwardLabel,
        disabledReason: _disabledReasonFor('advance', _advanceDisabledReason()),
        isLoading: _busyActionKey == 'advance',
        onPressed: _handleAdvanceStatus,
        backgroundGradient: _forwardTarget == null
            ? null
            : LinearGradient(
                colors: [
                  currentStatusColor,
                  AppointmentCalendarDisplay.statusColor(
                    _forwardTarget!,
                    brightness,
                  ),
                ],
              ),
      ),
      _StatusActionSpec(
        key: const Key('appointment_control_no_show'),
        icon: Icons.person_off_outlined,
        label: 'Mark no-show',
        variant: AppButtonVariant.danger,
        disabledReason: _disabledReasonFor(
          'no_show',
          _markNoShowDisabledReason(),
        ),
        isLoading: _busyActionKey == 'no_show',
        onPressed: _handleMarkNoShow,
      ),
      _StatusActionSpec(
        key: const Key('appointment_control_cancel'),
        icon: Icons.event_busy_outlined,
        label: 'Cancel appointment',
        variant: AppButtonVariant.danger,
        disabledReason: _disabledReasonFor('cancel', _cancelDisabledReason()),
        isLoading: _busyActionKey == 'cancel',
        onPressed: _handleCancel,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useStacked = constraints.maxWidth < 280;

        if (useStacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < specs.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.space1),
                _StatusActionButton(spec: specs[i], expand: true),
              ],
            ],
          );
        }

        return Wrap(
          spacing: AppSpacing.space1,
          runSpacing: AppSpacing.space1,
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
    this.variant = AppButtonVariant.secondary,
    this.backgroundGradient,
    this.disabledReason,
    this.isLoading = false,
  });

  final Key key;
  final IconData icon;
  final String label;
  final AppButtonVariant variant;
  final Gradient? backgroundGradient;
  final String? disabledReason;
  final bool isLoading;
  final VoidCallback onPressed;
}

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({required this.spec, this.expand = false});

  final _StatusActionSpec spec;
  final bool expand;

  void _handleTap(BuildContext context) {
    final reason = spec.disabledReason;
    if (reason != null) {
      appToast(
        context,
        AppToastInput(message: reason, variant: AppToastVariant.info),
      );
      return;
    }
    spec.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final isInteractive = spec.disabledReason == null;

    final button = AppButton(
      key: spec.key,
      variant: spec.variant,
      size: AppButtonSize.md,
      loading: spec.isLoading,
      disabled: !isInteractive,
      backgroundGradient: spec.backgroundGradient,
      leadingIcon: Icon(spec.icon, size: 18),
      onPressed: isInteractive ? spec.onPressed : null,
      child: Text(spec.label),
    );

    final wrapped = expand
        ? SizedBox(width: double.infinity, child: button)
        : button;

    if (isInteractive) {
      return wrapped;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context),
      child: wrapped,
    );
  }
}
