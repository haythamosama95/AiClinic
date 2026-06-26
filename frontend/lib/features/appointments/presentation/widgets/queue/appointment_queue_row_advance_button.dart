import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Compact forward-action control for a queue schedule row (V1-4 US5).
class AppointmentQueueRowAdvanceButton extends ConsumerStatefulWidget {
  const AppointmentQueueRowAdvanceButton({required this.item, required this.siblingAppointments, super.key});

  final AppointmentListItem item;
  final List<AppointmentListItem> siblingAppointments;

  @override
  ConsumerState<AppointmentQueueRowAdvanceButton> createState() => _AppointmentQueueRowAdvanceButtonState();
}

class _AppointmentQueueRowAdvanceButtonState extends ConsumerState<AppointmentQueueRowAdvanceButton> {
  static const _buttonSize = 40.0;

  bool _isLoading = false;

  AppointmentListItem get item => widget.item;

  String get _organizationTimezone {
    final timezone = ref.read(authSessionProvider).context?.organizationTimezone?.trim();
    return timezone == null || timezone.isEmpty ? 'UTC' : timezone;
  }

  bool get _canCreateAppointments => ref.read(permissionServiceProvider).canCreateAppointments();

  bool get _showsAdvanceAction => switch (item.status) {
    AppointmentStatus.scheduled => true,
    AppointmentStatus.confirmed => true,
    AppointmentStatus.checkedIn => true,
    AppointmentStatus.inProgress => true,
    _ => false,
  };

  AppointmentStatus? get _targetStatus => switch (item.status) {
    AppointmentStatus.scheduled => AppointmentStatus.confirmed,
    AppointmentStatus.confirmed => AppointmentStatus.checkedIn,
    AppointmentStatus.checkedIn => AppointmentStatus.inProgress,
    AppointmentStatus.inProgress => AppointmentStatus.completed,
    _ => null,
  };

  String? _disabledReason() {
    if (!_canCreateAppointments) {
      return 'You do not have permission to manage appointments.';
    }

    if (item.status == AppointmentStatus.inProgress) {
      return 'Complete this appointment from the visit workflow.';
    }

    final target = _targetStatus;
    if (target == null) {
      return null;
    }
    if (!canTransitionToStatusOnDate(target, item.startTime, organizationTimezone: _organizationTimezone)) {
      return switch (target) {
        AppointmentStatus.checkedIn => 'Check-in is only available on the appointment day.',
        AppointmentStatus.inProgress => 'Starting is only available on the appointment day.',
        _ => 'This status change is only available on the appointment day.',
      };
    }
    if (target == AppointmentStatus.inProgress) {
      return AppointmentQueueDisplay.doctorInProgressBlockReason(item, widget.siblingAppointments);
    }
    return null;
  }

  String _tooltipMessage() {
    final target = _targetStatus;
    final transitionLabel = target == null ? 'Advance status' : 'Move to ${target.label}';
    final disabledReason = _disabledReason();
    if (disabledReason != null) {
      return '$transitionLabel — $disabledReason';
    }
    return transitionLabel;
  }

  Future<void> _handleAdvance() async {
    if (_isLoading || _disabledReason() != null) {
      return;
    }

    final target = forwardStatusTargetFor(
      item,
      organizationTimezone: _organizationTimezone,
      siblingAppointments: widget.siblingAppointments,
    );
    if (target == null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(appointmentRepositoryProvider).updateAppointmentStatus(appointmentId: item.id, newStatus: target);
      if (!mounted) {
        return;
      }
      ref.invalidate(appointmentDetailProvider(item.id));
      ref.invalidate(appointmentCalendarProvider);
      ref.invalidate(appointmentQueueProvider);
      AppToast.success(context, message: 'Appointment marked as ${target.label.toLowerCase()}.');
    } on RpcFailure catch (error) {
      if (mounted) {
        AppToast.error(context, message: appointmentMessageForRpc(error));
      }
    } catch (_) {
      if (mounted) {
        AppToast.error(context, message: 'Unable to update status. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showsAdvanceAction) {
      return const SizedBox.shrink();
    }

    final colors = context.semanticColors;
    final disabledReason = _disabledReason();
    final isInteractive = disabledReason == null && !_isLoading;

    final button = Material(
      color: isInteractive ? colors.primary.withValues(alpha: 0.1) : colors.muted,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isInteractive ? _handleAdvance : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Center(
            child: _isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isInteractive ? colors.primary : colors.mutedForeground,
                    ),
                  )
                : Icon(
                    Icons.play_arrow_rounded,
                    size: 22,
                    color: isInteractive ? colors.primary : colors.mutedForeground,
                  ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: SpacingTokens.sm),
      child: Tooltip(
        key: Key('appointment_queue_advance_${item.id}'),
        message: _tooltipMessage(),
        waitDuration: const Duration(milliseconds: 400),
        child: Semantics(button: true, enabled: isInteractive, label: _tooltipMessage(), child: button),
      ),
    );
  }
}
