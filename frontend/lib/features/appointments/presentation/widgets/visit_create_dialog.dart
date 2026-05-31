import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/doctor_selector.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';

/// Starts a visit from an eligible appointment; prompts for doctor when missing (V1-5 US1).
class VisitCreateDialog extends ConsumerStatefulWidget {
  const VisitCreateDialog({required this.item, super.key});

  final AppointmentListItem item;

  static Future<CreateVisitResult?> show(BuildContext context, {required AppointmentListItem item}) {
    return showDialog<CreateVisitResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VisitCreateDialog(item: item),
    );
  }

  @override
  ConsumerState<VisitCreateDialog> createState() => _VisitCreateDialogState();
}

class _VisitCreateDialogState extends ConsumerState<VisitCreateDialog> {
  String? _selectedDoctorId;
  bool _isSaving = false;
  String? _formError;

  AppointmentListItem get _item => widget.item;

  bool get _needsDoctorPicker => _item.doctorId == null || _item.doctorId!.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _selectedDoctorId = _item.doctorId;
  }

  Future<void> _create() async {
    if (_needsDoctorPicker && (_selectedDoctorId == null || _selectedDoctorId!.trim().isEmpty)) {
      setState(() => _formError = 'Select a doctor before starting this visit.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final result = await ref
          .read(visitRepositoryProvider)
          .createVisit(appointmentId: _item.id, doctorId: _needsDoctorPicker ? _selectedDoctorId : null);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = visitMessageForRpc(error);
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
      key: const Key('visit_create_dialog'),
      title: const Text('Start visit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Patient: ${_item.patientName}'),
            const SizedBox(height: 8),
            if (_needsDoctorPicker) ...[
              const Text('This appointment has no doctor assigned. Select one to continue.'),
              const SizedBox(height: 12),
              DoctorSelector(
                selectedDoctorId: _selectedDoctorId,
                onChanged: (value) => setState(() {
                  _selectedDoctorId = value;
                  _formError = null;
                }),
              ),
            ] else
              Text('Doctor: ${_item.doctorDisplayName}'),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                key: const Key('visit_create_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('visit_create_cancel'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('visit_create_confirm'),
          onPressed: _isSaving ? null : _create,
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Start visit'),
        ),
      ],
    );
  }
}
