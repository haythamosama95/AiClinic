import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status_transitions.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';

/// Check-in / start / complete controls for a single appointment row (V1-4 US5).
class AppointmentStatusActions extends ConsumerStatefulWidget {
  const AppointmentStatusActions({super.key, required this.item, this.onStatusChanged, this.dense = false});

  final AppointmentListItem item;
  final ValueChanged<AppointmentStatus>? onStatusChanged;
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

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(permissionServiceProvider).canCreateAppointments();
    final target = forwardStatusTargetFor(_item);
    final label = forwardStatusActionLabelFor(_item);

    if (!canCreate || target == null || label.isEmpty || _item.status.isTerminal) {
      return const SizedBox.shrink();
    }

    final buttonKey = switch (target) {
      AppointmentStatus.checkedIn => const Key('appointments_status_check_in'),
      AppointmentStatus.inProgress => const Key('appointments_status_start'),
      AppointmentStatus.completed => const Key('appointments_status_complete'),
      _ => const Key('appointments_status_advance'),
    };

    final button = _submitting
        ? SizedBox(
            width: widget.dense ? 20 : 24,
            height: widget.dense ? 20 : 24,
            child: const CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.dense
        ? TextButton(key: buttonKey, onPressed: _advance, child: Text(label))
        : FilledButton.tonal(key: buttonKey, onPressed: _advance, child: Text(label));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
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
