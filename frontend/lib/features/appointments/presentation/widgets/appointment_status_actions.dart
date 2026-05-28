import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_reschedule_dialog.dart';

/// Check-in / start / complete and reschedule controls for an appointment row (V1-4 US5/US6).
class AppointmentStatusActions extends ConsumerStatefulWidget {
  const AppointmentStatusActions({
    super.key,
    required this.item,
    this.onStatusChanged,
    this.onRescheduled,
    this.dense = false,
  });

  final AppointmentListItem item;
  final ValueChanged<AppointmentStatus>? onStatusChanged;
  final ValueChanged<CreateAppointmentResult>? onRescheduled;
  final bool dense;

  @override
  ConsumerState<AppointmentStatusActions> createState() => _AppointmentStatusActionsState();
}

class _AppointmentStatusActionsState extends ConsumerState<AppointmentStatusActions> {
  bool _submitting = false;
  String? _error;

  AppointmentListItem get _item => widget.item;

  @override
  void didUpdateWidget(covariant AppointmentStatusActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.item.status != widget.item.status) {
      setState(() {
        _error = null;
        _submitting = false;
      });
    }
  }

  Future<void> _advance() async {
    final target = forwardStatusTargetFor(_item);
    if (target == null || _submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final updated = await ref
          .read(appointmentRepositoryProvider)
          .updateAppointmentStatus(appointmentId: _item.id, newStatus: target);

      if (!mounted) {
        return;
      }

      setState(() => _submitting = false);
      widget.onStatusChanged?.call(updated);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status updated to ${updated.label}.')));
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = appointmentMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  Future<void> _openReschedule() async {
    if (_submitting) {
      return;
    }

    final result = await AppointmentRescheduleDialog.show(context, item: _item);
    if (!mounted || result == null) {
      return;
    }

    widget.onRescheduled?.call(result);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment rescheduled.')));
  }

  Future<void> _openCancelOrNoShow() async {
    if (_submitting) {
      return;
    }

    final updated = await AppointmentCancelDialog.show(context, item: _item);
    if (!mounted || updated == null) {
      return;
    }

    widget.onStatusChanged?.call(updated);
    final message = switch (updated) {
      AppointmentStatus.cancelled => 'Appointment cancelled.',
      AppointmentStatus.noShow => 'Appointment marked as no-show.',
      _ => 'Status updated to ${updated.label}.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionServiceProvider);
    final canCreate = permissions.canCreateAppointments();
    final canCancel = permissions.canCancelAppointments();
    final target = forwardStatusTargetFor(_item);
    final label = forwardStatusActionLabelFor(_item);
    final showStatus = canCreate && target != null && label.isNotEmpty && !_item.status.isTerminal;
    final showReschedule = canCreate && canRescheduleAppointment(_item);
    final showCancel = canCancel && canCancelOrNoShowAppointment(_item);

    if (!showStatus && !showReschedule && !showCancel) {
      return const SizedBox.shrink();
    }

    final buttonKey = switch (target) {
      AppointmentStatus.checkedIn => const Key('appointments_status_check_in'),
      AppointmentStatus.inProgress => const Key('appointments_status_start'),
      AppointmentStatus.completed => const Key('appointments_status_complete'),
      _ => const Key('appointments_status_advance'),
    };

    final statusButton = _submitting
        ? SizedBox(
            width: widget.dense ? 20 : 24,
            height: widget.dense ? 20 : 24,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.dense
        ? TextButton(key: buttonKey, onPressed: _advance, child: Text(label))
        : FilledButton.tonal(key: buttonKey, onPressed: _advance, child: Text(label));

    final rescheduleButton = TextButton(
      key: const Key('appointments_status_reschedule'),
      onPressed: _submitting ? null : _openReschedule,
      child: const Text('Reschedule'),
    );

    final cancelButton = TextButton(
      key: const Key('appointments_status_cancel'),
      onPressed: _submitting ? null : _openCancelOrNoShow,
      child: const Text('Cancel / no-show'),
    );

    final actionButtons = <Widget>[
      if (showStatus) statusButton,
      if (showReschedule) rescheduleButton,
      if (showCancel) cancelButton,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (actionButtons.length == 1)
          actionButtons.first
        else
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: actionButtons),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            key: const Key('appointments_status_error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
