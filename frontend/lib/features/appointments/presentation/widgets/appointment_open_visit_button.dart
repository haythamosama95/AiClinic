import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/visits/presentation/navigation/visit_navigation.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_by_appointment_provider.dart';

/// Opens the encounter workspace for an in-progress or completed appointment.
class AppointmentOpenVisitButton extends ConsumerStatefulWidget {
  const AppointmentOpenVisitButton({required this.detail, super.key});

  final AppointmentDetail detail;

  @override
  ConsumerState<AppointmentOpenVisitButton> createState() => _AppointmentOpenVisitButtonState();
}

class _AppointmentOpenVisitButtonState extends ConsumerState<AppointmentOpenVisitButton> {
  var _opening = false;

  bool get _shouldShow {
    if (!appointmentSupportsOpenVisit(widget.detail)) {
      return false;
    }
    return canOpenVisitForAppointment(ref, widget.detail);
  }

  Future<void> _handleOpen() async {
    if (_opening) {
      return;
    }

    setState(() => _opening = true);
    try {
      await openVisitForAppointment(context: context, ref: ref, detail: widget.detail);
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) {
      return const SizedBox.shrink();
    }

    final visitAsync = ref.watch(visitByAppointmentProvider(widget.detail.id));
    final hasVisit = visitAsync.maybeWhen(
      data: (result) => result.visitId?.trim().isNotEmpty == true,
      orElse: () => false,
    );

    if (widget.detail.status == AppointmentStatus.completed && visitAsync.hasValue && !hasVisit) {
      return const SizedBox.shrink();
    }

    final loading = _opening || visitAsync.isLoading;

    return AppButton(
      key: const Key('appointment_open_visit'),
      variant: AppButtonVariant.primary,
      size: AppButtonSize.sm,
      leadingIcon: const Icon(Icons.medical_services_outlined, size: 16),
      loading: loading,
      disabled: loading,
      onPressed: loading ? null : _handleOpen,
      child: Text(widget.detail.status == AppointmentStatus.inProgress ? 'Open visit' : 'View visit'),
    );
  }
}
