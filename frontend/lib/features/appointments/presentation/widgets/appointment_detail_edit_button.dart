import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_sheet.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';

/// Header edit action for the appointment detail page.
class AppointmentDetailEditButton extends ConsumerStatefulWidget {
  const AppointmentDetailEditButton({required this.detail, super.key});

  final AppointmentDetail detail;

  @override
  ConsumerState<AppointmentDetailEditButton> createState() => _AppointmentDetailEditButtonState();
}

class _AppointmentDetailEditButtonState extends ConsumerState<AppointmentDetailEditButton> {
  var _isLoading = false;

  AppointmentDetail get detail => widget.detail;

  PermissionService get _permissions => PermissionService(ref.read(authSessionProvider).context);

  bool get _canCreateAppointments => _permissions.canCreateAppointments();

  String? get _disabledReason {
    if (_isLoading) {
      return 'Please wait for the current action to finish.';
    }
    if (!_canCreateAppointments) {
      return 'You do not have permission to manage appointments.';
    }
    if (!detail.status.isTerminal) {
      return null;
    }
    return 'This appointment is ${detail.status.label.toLowerCase()} and cannot be edited.';
  }

  String get _tooltip {
    final reason = _disabledReason;
    if (reason != null) {
      return reason;
    }
    return 'Edit appointment';
  }

  Future<void> _handleEdit() async {
    if (_disabledReason != null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final branches = await ref.read(appointmentCalendarBranchesProvider.future);
      final doctors = await ref.read(appointmentCalendarDoctorsProvider.future);
      BranchListItem? selectedBranch;
      for (final branch in branches) {
        if (branch.id == detail.branchId) {
          selectedBranch = branch;
          break;
        }
      }
      final schedule = selectedBranch?.workingSchedule ?? BranchWorkingSchedule.defaultSchedule();

      if (!mounted) {
        return;
      }

      final updated = await AppointmentBookingSheet.show(
        context,
        branchId: detail.branchId,
        schedule: schedule,
        slotStart: detail.startTime.toLocal(),
        slotEnd: detail.endTime.toLocal(),
        initialDoctorId: detail.doctorId,
        doctors: doctors,
        existingAppointment: detail,
        branchName: selectedBranch?.name,
      );

      if (updated == true && mounted) {
        ref.invalidate(appointmentDetailProvider(detail.id));
        ref.invalidate(appointmentCalendarProvider);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInteractive = _disabledReason == null;

    final button = AppButton(
      key: const Key('appointment_detail_edit'),
      variant: AppButtonVariant.primary,
      size: AppButtonSize.md,
      loading: _isLoading,
      disabled: !isInteractive,
      leadingIcon: const Icon(Icons.edit_outlined),
      onPressed: isInteractive ? _handleEdit : null,
      child: const Text('Edit appointment'),
    );

    if (!isInteractive) {
      return Tooltip(message: _tooltip, child: button);
    }

    return button;
  }
}
