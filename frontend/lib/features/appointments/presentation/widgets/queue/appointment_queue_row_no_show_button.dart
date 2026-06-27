import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_day_rules.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';

/// Compact no-show control for a queue schedule row (V1-4 US7).
class AppointmentQueueRowNoShowButton extends ConsumerStatefulWidget {
  const AppointmentQueueRowNoShowButton({required this.item, super.key});

  final AppointmentListItem item;

  @override
  ConsumerState<AppointmentQueueRowNoShowButton> createState() => _AppointmentQueueRowNoShowButtonState();
}

class _AppointmentQueueRowNoShowButtonState extends ConsumerState<AppointmentQueueRowNoShowButton> {
  static const _buttonSize = 32.0;

  bool _isLoading = false;

  AppointmentListItem get item => widget.item;

  String get _organizationTimezone {
    final timezone = ref.read(authSessionProvider).context?.organizationTimezone?.trim();
    return timezone == null || timezone.isEmpty ? 'UTC' : timezone;
  }

  bool get _canCancelAppointments => AuthRouteGuard.canAccessAppointmentCancelActions(ref.read(authSessionProvider));

  String? _disabledReason() {
    if (item.status == AppointmentStatus.noShow) {
      return 'This appointment is already marked as no-show.';
    }

    if (!_canCancelAppointments) {
      return 'You do not have permission to cancel appointments.';
    }
    if (!item.status.canTransitionTo(AppointmentStatus.noShow)) {
      return 'No-show cannot be recorded for ${item.status.label.toLowerCase()} appointments.';
    }
    if (!canTransitionToStatusOnDate(
      AppointmentStatus.noShow,
      item.startTime,
      organizationTimezone: _organizationTimezone,
    )) {
      return 'No-show can only be marked on or after the appointment day.';
    }
    return null;
  }

  String _tooltipMessage() {
    const actionLabel = 'Mark no-show';
    final disabledReason = _disabledReason();
    if (disabledReason != null) {
      return '$actionLabel — $disabledReason';
    }
    return actionLabel;
  }

  Future<void> _handleMarkNoShow() async {
    if (_isLoading || _disabledReason() != null) {
      return;
    }

    await AppDialog.showConfirmation(
      context: context,
      title: 'Mark as no-show?',
      message: '${item.patientName} did not attend this appointment. The slot will be closed as a no-show.',
      confirmLabel: 'Mark no-show',
      cancelLabel: 'Keep status',
      destructive: true,
      onConfirm: () async {
        setState(() => _isLoading = true);
        try {
          await ref.read(appointmentRepositoryProvider).markAppointmentNoShow(appointmentId: item.id);
          if (!mounted) {
            return;
          }
          ref.invalidate(appointmentDetailProvider(item.id));
          ref.invalidate(appointmentCalendarProvider);
          ref
              .read(appointmentQueueProvider.notifier)
              .patchAppointmentStatus(appointmentId: item.id, newStatus: AppointmentStatus.noShow);
          AppToast.success(context, message: 'Appointment marked as no-show.');
        } on RpcFailure catch (error) {
          if (mounted) {
            AppToast.error(context, message: appointmentMessageForRpc(error));
          }
        } catch (_) {
          if (mounted) {
            AppToast.error(context, message: 'Unable to mark no-show. Try again.');
          }
        } finally {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final disabledReason = _disabledReason();
    final isInteractive = disabledReason == null && !_isLoading;

    final button = Material(
      color: isInteractive ? colors.destructive : colors.muted,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isInteractive) {
            _handleMarkNoShow();
          }
        },
        splashFactory: isInteractive ? null : NoSplash.splashFactory,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Center(
            child: _isLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isInteractive ? colors.destructiveForeground : colors.mutedForeground,
                    ),
                  )
                : Icon(
                    Icons.person_off_outlined,
                    size: 16,
                    color: isInteractive ? colors.destructiveForeground : colors.mutedForeground,
                  ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(left: SpacingTokens.sm),
      child: Tooltip(
        key: Key('appointment_queue_no_show_${item.id}'),
        message: _tooltipMessage(),
        waitDuration: const Duration(milliseconds: 400),
        child: Semantics(button: true, enabled: isInteractive, label: _tooltipMessage(), child: button),
      ),
    );
  }
}
