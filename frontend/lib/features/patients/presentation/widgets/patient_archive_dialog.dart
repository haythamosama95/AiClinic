import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/patient_rpc_messages.dart';

/// Confirms archival of a patient record (US5).
class PatientArchiveDialog extends ConsumerStatefulWidget {
  const PatientArchiveDialog({required this.patientId, required this.patientName, super.key});

  final String patientId;
  final String patientName;

  static Future<bool?> show(BuildContext context, {required String patientId, required String patientName}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PatientArchiveDialog(patientId: patientId, patientName: patientName),
    );
  }

  @override
  ConsumerState<PatientArchiveDialog> createState() => _PatientArchiveDialogState();
}

class _PatientArchiveDialogState extends ConsumerState<PatientArchiveDialog> {
  bool _isArchiving = false;
  String? _error;

  Future<void> _archive() async {
    setState(() {
      _isArchiving = true;
      _error = null;
    });

    try {
      await ref.read(archivePatientUseCaseProvider)(widget.patientId);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on RpcFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isArchiving = false;
        _error = patientMessageForRpc(failure);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isArchiving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('patient_archive_dialog'),
      title: const Text('Archive patient'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Archive "${widget.patientName}"? They will be removed from search and lists. '
              'This cannot be undone from the app.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('patient_archive_cancel'),
          onPressed: _isArchiving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('patient_archive_confirm'),
          onPressed: _isArchiving ? null : _archive,
          child: _isArchiving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Archive'),
        ),
      ],
    );
  }
}
