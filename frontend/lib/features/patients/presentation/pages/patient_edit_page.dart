import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/repositories/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/presentation/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/duplicate_candidates_dialog.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

void _leavePatientEdit(BuildContext context, String patientId) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.patientDetail(patientId));
  }
}

/// Edit an existing patient profile org-wide (US4).
class PatientEditPage extends ConsumerStatefulWidget {
  const PatientEditPage({required this.patientId, super.key});

  final String? patientId;

  @override
  ConsumerState<PatientEditPage> createState() => _PatientEditPageState();
}

class _PatientEditPageState extends ConsumerState<PatientEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  PatientGender? _gender;
  PatientMaritalStatus? _maritalStatus;
  DateTime? _expectedUpdatedAt;
  String? _loadedPatientId;
  bool _isSaving = false;
  String? _formError;
  bool _showStaleBanner = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _populateFromDetail(PatientDetail detail) {
    if (_loadedPatientId == detail.id) {
      return;
    }

    _loadedPatientId = detail.id;
    _fullNameController.text = detail.fullName;
    _phoneController.text = detail.phone ?? '';
    _notesController.text = detail.notes ?? '';
    _dateOfBirth = detail.dateOfBirth;
    _gender = detail.gender;
    _maritalStatus = detail.maritalStatus;
    _expectedUpdatedAt = detail.updatedAt;
    _showStaleBanner = false;
    _formError = null;
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  UpdatePatientInput _buildInput({required String patientId, required bool acknowledgeDuplicate}) {
    return UpdatePatientInput(
      patientId: patientId,
      fullName: _fullNameController.text,
      expectedUpdatedAt: _expectedUpdatedAt ?? DateTime.now().toUtc(),
      phone: _phoneController.text.trim(),
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      maritalStatus: _maritalStatus,
      notes: _trimOrNull(_notesController.text),
      acknowledgeDuplicate: acknowledgeDuplicate,
    );
  }

  Future<void> _reloadPatient(String patientId) async {
    ref.invalidate(patientDetailProvider(patientId));
    setState(() {
      _loadedPatientId = null;
      _showStaleBanner = false;
      _formError = null;
    });
    await ref.read(patientDetailProvider(patientId).future);
  }

  Future<void> _submit(String patientId) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_expectedUpdatedAt == null) {
      setState(() => _formError = 'Patient data is still loading. Try again in a moment.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
      _showStaleBanner = false;
    });

    final repository = ref.read(patientRepositoryProvider);
    await _updateWithDuplicateHandling(repository: repository, patientId: patientId, acknowledgeDuplicate: false);
  }

  Future<void> _updateWithDuplicateHandling({
    required PatientRepository repository,
    required String patientId,
    required bool acknowledgeDuplicate,
  }) async {
    try {
      final updatedAt = await repository.updatePatient(
        _buildInput(patientId: patientId, acknowledgeDuplicate: acknowledgeDuplicate),
      );

      if (!mounted) {
        return;
      }

      ref.invalidate(patientDetailProvider(patientId));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient updated successfully.')));
      context.go(AppRoutes.patientDetail(patientId));
      // Keep analyzer happy about updatedAt being used for optimistic lock refresh on future edits.
      _expectedUpdatedAt = updatedAt;
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }

      if (error.isDuplicateWarning) {
        final candidates = error.duplicateCandidates;
        setState(() => _isSaving = false);

        final proceed = await DuplicateCandidatesDialog.show(context, candidates: candidates);
        if (proceed != true || !mounted) {
          return;
        }

        setState(() => _isSaving = true);
        await _updateWithDuplicateHandling(repository: repository, patientId: patientId, acknowledgeDuplicate: true);
        return;
      }

      if (error.isStalePatient) {
        setState(() {
          _isSaving = false;
          _showStaleBanner = true;
          _formError = null;
        });
        return;
      }

      setState(() {
        _isSaving = false;
        _formError = patientMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = error.toString();
      });
    }
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _dateOfBirth = picked);
    }
  }

  void _clearDateOfBirth() {
    setState(() => _dateOfBirth = null);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = PermissionService(ref.watch(authSessionProvider).context).canEditPatients();
    final id = widget.patientId?.trim() ?? '';

    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit patient'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => id.isEmpty ? context.go(AppRoutes.patients) : _leavePatientEdit(context, id),
          ),
        ),
        body: const Center(
          key: Key('patient_edit_permission_denied'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to edit patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (id.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit patient'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.patients)),
        ),
        body: const Center(
          key: Key('patient_edit_invalid_id'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('A valid patient id is required.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final detailAsync = ref.watch(patientDetailProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.maybeWhen(
          data: (detail) => Text('Edit ${detail.fullName}'),
          orElse: () => const Text('Edit patient'),
        ),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _leavePatientEdit(context, id)),
      ),
      body: detailAsync.when(
        loading: () => const Center(key: Key('patient_edit_loading'), child: CircularProgressIndicator()),
        error: (error, _) => Center(
          key: const Key('patient_edit_load_error'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => _reloadPatient(id), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (detail) {
          _populateFromDetail(detail);
          return _buildForm(context, detail: detail, patientId: id);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, {required PatientDetail detail, required String patientId}) {
    final dobLabel = _dateOfBirth == null
        ? 'Not set'
        : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      key: const Key('patient_edit_body'),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showStaleBanner) ...[
              MaterialBanner(
                key: const Key('patient_edit_stale_banner'),
                content: const Text('This record was updated elsewhere. Reload the latest data before saving again.'),
                actions: [
                  TextButton(
                    key: const Key('patient_edit_stale_reload'),
                    onPressed: _isSaving ? null : () => _reloadPatient(patientId),
                    child: const Text('Reload'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_formError != null) ...[
              Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
            ],
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Registering branch'),
              child: Text(detail.branchName),
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Full name',
              infoTooltip: 'Patient legal or preferred full name as recorded at the desk.',
              controller: _fullNameController,
              enabled: !_isSaving,
              validator: (value) => value == null || value.trim().isEmpty ? 'Full name is required.' : null,
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Mobile number',
              infoTooltip: 'Mobile number including country code when known (8–15 digits).',
              controller: _phoneController,
              enabled: !_isSaving,
              keyboardType: TextInputType.phone,
              validator: (value) => value == null || value.trim().isEmpty ? 'Mobile number is required.' : null,
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date of birth'),
                    child: Text(dobLabel),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _isSaving ? null : _pickDateOfBirth, child: const Text('Pick date')),
                if (_dateOfBirth != null)
                  TextButton(onPressed: _isSaving ? null : _clearDateOfBirth, child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PatientGender?>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Not specified')),
                DropdownMenuItem(value: PatientGender.male, child: Text('Male')),
                DropdownMenuItem(value: PatientGender.female, child: Text('Female')),
              ],
              onChanged: _isSaving ? null : (value) => setState(() => _gender = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PatientMaritalStatus?>(
              value: _maritalStatus,
              decoration: const InputDecoration(labelText: 'Marital status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Not specified')),
                ...PatientMaritalStatus.values.map(
                  (status) => DropdownMenuItem(value: status, child: Text(status.label)),
                ),
              ],
              onChanged: _isSaving ? null : (value) => setState(() => _maritalStatus = value),
            ),
            const SizedBox(height: 16),
            AppFormField(
              label: 'Notes',
              infoTooltip: 'Front-desk notes visible on the patient profile.',
              controller: _notesController,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('patient_edit_submit'),
              onPressed: _isSaving ? null : () => _submit(patientId),
              child: _isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
