import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
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
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_confirm_dialog.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';

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

/// Action panel for managing an appointment from the detail page.
class AppointmentDetailControlsCard extends ConsumerStatefulWidget {
  const AppointmentDetailControlsCard({required this.detail, this.maxHeight, super.key});

  final AppointmentDetail detail;

  /// When set beside the hero card, caps total card height and scrolls overflow actions.
  final double? maxHeight;

  @override
  ConsumerState<AppointmentDetailControlsCard> createState() => _AppointmentDetailControlsCardState();
}

class _AppointmentDetailControlsCardState extends ConsumerState<AppointmentDetailControlsCard> {
  String? _busyActionKey;

  AppointmentDetail get detail => widget.detail;

  bool get _isBusy => _busyActionKey != null;

  String get _organizationTimezone =>
      ref.read(authSessionProvider).context?.organizationTimezone?.trim().isNotEmpty == true
      ? ref.read(authSessionProvider).context!.organizationTimezone!.trim()
      : 'UTC';

  PermissionService get _permissions => PermissionService(ref.read(authSessionProvider).context);

  AppointmentListItem get _listItem => detail.toListItem();

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
    final activeLabel = forwardStatusActionLabelFor(_listItem, organizationTimezone: _organizationTimezone);
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
    return null;
  }

  String? _rescheduleDisabledReason() {
    final permission = _permissionDeniedCreateReason();
    if (permission != null) {
      return permission;
    }
    if (canRescheduleAppointment(_listItem)) {
      return null;
    }
    if (detail.type != AppointmentType.planned) {
      return 'Only planned appointments can be rescheduled.';
    }
    if (detail.status != AppointmentStatus.scheduled) {
      return 'Only scheduled appointments can be rescheduled. Cancel and re-book to change a confirmed slot.';
    }
    return 'This appointment cannot be rescheduled.';
  }

  String? _editDisabledReason() {
    final permission = _permissionDeniedCreateReason();
    if (permission != null) {
      return permission;
    }
    if (!detail.status.isTerminal) {
      return null;
    }
    return 'This appointment is ${detail.status.label.toLowerCase()} and cannot be edited.';
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

  Future<void> _handleAdvanceStatus() async {
    if (_disabledReasonFor('advance', _advanceStatusDisabledReason()) != null) {
      return;
    }

    final target = forwardStatusTargetFor(_listItem, organizationTimezone: _organizationTimezone);
    if (target == null) {
      return;
    }

    await _runAction('advance', () async {
      try {
        await ref
            .read(appointmentRepositoryProvider)
            .updateAppointmentStatus(appointmentId: detail.id, newStatus: target);
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(detail.id));
        ref.invalidate(appointmentCalendarProvider);
        AppToast.success(context, message: 'Appointment marked as ${target.label.toLowerCase()}.');
      } on RpcFailure catch (error) {
        if (mounted) {
          AppToast.error(context, message: appointmentMessageForRpc(error));
        }
      } catch (_) {
        if (mounted) {
          AppToast.error(context, message: 'Unable to update status. Try again.');
        }
      }
    });
  }

  Future<void> _handleReschedule() async {
    if (_disabledReasonFor('reschedule', _rescheduleDisabledReason()) != null) {
      return;
    }

    await _runAction('reschedule', () async {
      final branches = await ref.read(appointmentCalendarBranchesProvider.future);
      BranchListItem? selectedBranch;
      for (final branch in branches) {
        if (branch.id == detail.branchId) {
          selectedBranch = branch;
          break;
        }
      }
      final schedule = selectedBranch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();

      final focusDate = DateTime(
        detail.startTime.toLocal().year,
        detail.startTime.toLocal().month,
        detail.startTime.toLocal().day,
      );
      final bounds = appointmentCalendarFetchBounds(focusDate, AppointmentCalendarMode.week);
      final branchAppointments = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: detail.branchId, from: bounds.$1, to: bounds.$2);

      if (!mounted) {
        return;
      }

      final confirmed = await AppointmentRescheduleConfirmDialog.show(
        context,
        appointment: _listItem,
        newStart: detail.startTime.toLocal(),
        newEnd: detail.endTime.toLocal(),
        schedule: schedule,
        branchAppointments: branchAppointments,
      );
      if (confirmed == null || !mounted) {
        return;
      }

      try {
        await ref
            .read(appointmentRepositoryProvider)
            .rescheduleAppointment(appointmentId: detail.id, startTime: confirmed.start, endTime: confirmed.end);
        if (!mounted) {
          return;
        }
        ref.invalidate(appointmentDetailProvider(detail.id));
        ref.invalidate(appointmentCalendarProvider);
        AppToast.success(
          context,
          message: 'Appointment rescheduled to ${_formatRange(confirmed.start, confirmed.end)}.',
        );
      } on RpcFailure catch (error) {
        if (mounted) {
          AppToast.error(context, message: appointmentMessageForRpc(error));
        }
      } catch (_) {
        if (mounted) {
          AppToast.error(context, message: 'Unable to reschedule appointment. Try again.');
        }
      }
    });
  }

  void _handleEditInCalendar() {
    if (_disabledReasonFor('edit', _editDisabledReason()) != null || _isBusy) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.nav.goAppointmentsCalendar();
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
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final actions = _buildActions();

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(color: colors.foreground.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: widget.maxHeight != null ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: colors.primary),
                const SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text('Manage', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),
            if (widget.maxHeight != null)
              Expanded(child: _ManageActionList(actions: actions))
            else
              _ManageActionList(actions: actions),
          ],
        ),
      ),
    );

    if (widget.maxHeight == null) {
      return card;
    }

    return SizedBox(height: widget.maxHeight, child: card);
  }

  List<Widget> _buildActions() {
    final specs = <_ManageActionSpec>[
      _ManageActionSpec(
        key: const Key('appointment_control_advance_status'),
        icon: Icons.play_arrow_rounded,
        label: _advanceStatusLabel(),
        subtitle: 'Update appointment status',
        disabledReason: _disabledReasonFor('advance', _advanceStatusDisabledReason()),
        accent: context.semanticColors.primary,
        isLoading: _busyActionKey == 'advance',
        onPressed: _handleAdvanceStatus,
      ),
      _ManageActionSpec(
        key: const Key('appointment_control_reschedule'),
        icon: Icons.event_repeat_rounded,
        label: 'Reschedule',
        subtitle: 'Change date or time',
        disabledReason: _disabledReasonFor('reschedule', _rescheduleDisabledReason()),
        isLoading: _busyActionKey == 'reschedule',
        onPressed: _handleReschedule,
      ),
      _ManageActionSpec(
        key: const Key('appointment_control_edit'),
        icon: Icons.edit_outlined,
        label: 'Edit',
        subtitle: 'Open in calendar',
        disabledReason: _disabledReasonFor('edit', _editDisabledReason()),
        onPressed: _handleEditInCalendar,
      ),
      _ManageActionSpec(
        key: const Key('appointment_control_no_show'),
        icon: Icons.person_off_outlined,
        label: 'Mark no-show',
        subtitle: 'Patient did not attend',
        disabledReason: _disabledReasonFor('no_show', _markNoShowDisabledReason()),
        isLoading: _busyActionKey == 'no_show',
        onPressed: _handleMarkNoShow,
      ),
      _ManageActionSpec(
        key: const Key('appointment_control_cancel'),
        icon: Icons.event_busy_outlined,
        label: 'Cancel appointment',
        subtitle: 'Remove from schedule',
        disabledReason: _disabledReasonFor('cancel', _cancelDisabledReason()),
        variant: _AppointmentControlActionVariant.destructive,
        isLoading: _busyActionKey == 'cancel',
        onPressed: _handleCancel,
      ),
    ];

    final indexed = specs.indexed.toList()
      ..sort((a, b) {
        final aBlocked = a.$2.disabledReason != null;
        final bBlocked = b.$2.disabledReason != null;
        if (aBlocked != bBlocked) {
          return aBlocked ? 1 : -1;
        }
        return a.$1.compareTo(b.$1);
      });

    return [
      for (final (_, spec) in indexed)
        _AppointmentControlAction(
          key: spec.key,
          icon: spec.icon,
          label: spec.label,
          subtitle: spec.subtitle,
          disabledReason: spec.disabledReason,
          accent: spec.accent,
          variant: spec.variant,
          isLoading: spec.isLoading,
          onPressed: spec.onPressed,
        ),
    ];
  }

  static String _formatRange(DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    final day = DateFormat.yMMMd().format(localStart);
    final from = DateFormat.jm().format(localStart);
    final to = DateFormat.jm().format(localEnd);
    return '$day · $from – $to';
  }
}

enum _AppointmentControlActionVariant { normal, destructive }

class _ManageActionSpec {
  const _ManageActionSpec({
    required this.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onPressed,
    this.disabledReason,
    this.accent,
    this.variant = _AppointmentControlActionVariant.normal,
    this.isLoading = false,
  });

  final Key key;
  final IconData icon;
  final String label;
  final String subtitle;
  final String? disabledReason;
  final Color? accent;
  final _AppointmentControlActionVariant variant;
  final bool isLoading;
  final VoidCallback onPressed;
}

class _ManageActionList extends StatelessWidget {
  const _ManageActionList({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: SpacingTokens.xs), actions[i]],
      ],
    );

    return SingleChildScrollView(physics: const ClampingScrollPhysics(), child: list);
  }
}

class _AppointmentControlAction extends StatelessWidget {
  const _AppointmentControlAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onPressed,
    this.disabledReason,
    this.accent,
    this.variant = _AppointmentControlActionVariant.normal,
    this.isLoading = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String? disabledReason;
  final Color? accent;
  final _AppointmentControlActionVariant variant;
  final bool isLoading;
  final VoidCallback onPressed;

  bool get _isInteractive => disabledReason == null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);
    final isDestructive = variant == _AppointmentControlActionVariant.destructive;
    final accentColor = accent ?? (isDestructive ? colors.destructive : colors.primary);
    final iconColor = _isInteractive ? accentColor : colors.mutedForeground;
    final foreground = _isInteractive
        ? (isDestructive ? colors.destructive : colors.foreground)
        : colors.mutedForeground;
    final borderRadius = BorderRadius.circular(context.shapeTokens.md);
    final hoverFill = isDestructive ? colors.destructive.withValues(alpha: 0.08) : colors.muted;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: _isInteractive ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(context.shapeTokens.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SpacingTokens.xs),
              child: isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                    )
                  : Icon(icon, size: 18, color: iconColor),
            ),
          ),
          const SizedBox(width: SpacingTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: foreground),
                ),
                const SizedBox(height: 2),
                Text(
                  disabledReason ?? subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.mutedForeground,
                    fontStyle: disabledReason != null ? FontStyle.italic : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: colors.mutedForeground),
        ],
      ),
    );

    if (!_isInteractive) {
      return ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: content);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: borderRadius,
        hoverColor: hoverFill,
        focusColor: hoverFill,
        splashColor: hoverFill.withValues(alpha: 0.14),
        highlightColor: hoverFill.withValues(alpha: 0.1),
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: content),
      ),
    );
  }
}
