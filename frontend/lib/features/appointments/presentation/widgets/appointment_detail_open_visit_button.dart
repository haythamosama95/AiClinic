import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/visits/application/visit_launch_service.dart';

/// Header action that opens visit documentation for an appointment.
class AppointmentDetailOpenVisitButton extends ConsumerStatefulWidget {
  const AppointmentDetailOpenVisitButton({required this.detail, super.key});

  final AppointmentDetail detail;

  @override
  ConsumerState<AppointmentDetailOpenVisitButton> createState() => _AppointmentDetailOpenVisitButtonState();
}

class _AppointmentDetailOpenVisitButtonState extends ConsumerState<AppointmentDetailOpenVisitButton> {
  var _isLoading = false;

  AppointmentDetail get detail => widget.detail;

  bool get _canAccessVisit => ref.watch(authSessionProvider.select(AuthRouteGuard.canAccessVisitDocumentation));

  bool get _canStartVisit => switch (detail.status) {
    AppointmentStatus.checkedIn || AppointmentStatus.inProgress || AppointmentStatus.completed => true,
    _ => false,
  };

  String? get _disabledReason {
    if (!_canAccessVisit) {
      return 'You do not have permission to document visits.';
    }
    if (_isLoading) {
      return 'Opening visit…';
    }
    if (!_canStartVisit) {
      return switch (detail.status) {
        AppointmentStatus.scheduled || AppointmentStatus.confirmed =>
          'Check in the patient before opening the visit.',
        AppointmentStatus.cancelled => 'This appointment was cancelled.',
        AppointmentStatus.noShow => 'This appointment was marked as a no-show.',
        _ => 'This appointment is not ready for visit documentation.',
      };
    }
    return null;
  }

  String get _tooltip {
    final reason = _disabledReason;
    if (reason != null) {
      return reason;
    }
    return 'Open visit documentation';
  }

  Future<void> _handleOpenVisit() async {
    if (_disabledReason != null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(visitLaunchServiceProvider)
          .openOrCreateVisitForAppointment(appointmentId: detail.id, doctorId: detail.doctorId);

      if (!mounted) {
        return;
      }

      switch (result) {
        case VisitLaunchSuccess(:final visitId):
          context.nav.pushVisitDocument(visitId);
        case VisitLaunchFailed(:final userMessage):
          appToast(context, AppToastInput(message: userMessage, variant: AppToastVariant.danger));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccessVisit) {
      return const SizedBox.shrink();
    }

    final isInteractive = _disabledReason == null;

    final button = AppButton(
      key: const Key('appointment_detail_open_visit'),
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.md,
      loading: _isLoading,
      leadingIcon: const Icon(Icons.assignment_outlined),
      onPressed: isInteractive ? _handleOpenVisit : null,
      child: const Text('Open visit'),
    );

    if (!isInteractive) {
      return Tooltip(message: _tooltip, child: button);
    }

    return button;
  }
}
