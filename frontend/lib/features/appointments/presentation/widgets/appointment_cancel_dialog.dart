import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';

/// Cancel or mark no-show for a cancellable appointment (V1-4 US7).
class AppointmentCancelDialog extends ConsumerStatefulWidget {
  const AppointmentCancelDialog({required this.item, super.key});

  final AppointmentListItem item;

  static Future<AppointmentStatus?> show(BuildContext context, {required AppointmentListItem item}) {
    return showDialog<AppointmentStatus>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppointmentCancelDialog(item: item),
    );
  }

  @override
  ConsumerState<AppointmentCancelDialog> createState() => _AppointmentCancelDialogState();
}

class _AppointmentCancelDialogState extends ConsumerState<AppointmentCancelDialog> {
  final _reasonController = TextEditingController();
  bool _isSaving = false;
  String? _formError;

  AppointmentListItem get _item => widget.item;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _cancel() async {
    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final reason = _reasonController.text.trim();
      final status = await ref
          .read(appointmentRepositoryProvider)
          .cancelAppointment(appointmentId: _item.id, reason: reason.isEmpty ? null : reason);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(status);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = appointmentMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  Future<void> _markNoShow() async {
    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final status = await ref.read(appointmentRepositoryProvider).markAppointmentNoShow(appointmentId: _item.id);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(status);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = appointmentMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('appointment_cancel_dialog'),
      title: const Text('Cancel or no-show'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${_item.patientName} · ${_item.doctorDisplayName}'),
              const SizedBox(height: 8),
              Text('Current status: ${_item.status.label}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                key: const Key('appointment_cancel_reason'),
                controller: _reasonController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Cancellation reason (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                maxLength: 2000,
              ),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _formError!,
                  key: const Key('appointment_cancel_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('appointment_cancel_dismiss'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton(
          key: const Key('appointment_cancel_no_show'),
          onPressed: _isSaving ? null : _markNoShow,
          child: const Text('Mark no-show'),
        ),
        FilledButton(
          key: const Key('appointment_cancel_confirm'),
          onPressed: _isSaving ? null : _cancel,
          child: _isSaving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Cancel appointment'),
        ),
      ],
    );
  }
}
