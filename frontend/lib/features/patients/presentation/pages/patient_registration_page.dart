import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/utils/date_format_utils.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/core/widgets/unsaved_changes_guard.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/presentation/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/duplicate_candidates_dialog.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

void _leavePatientRegistration(BuildContext context) {
  context.nav.popOrHome();
}

/// Register a new patient at the active branch (US1).
class PatientRegistrationPage extends ConsumerStatefulWidget {
  const PatientRegistrationPage({super.key});

  @override
  ConsumerState<PatientRegistrationPage> createState() => _PatientRegistrationPageState();
}

class _PatientRegistrationPageState extends ConsumerState<PatientRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  PatientGender? _gender;
  PatientMaritalStatus? _maritalStatus;
  bool _isSaving = false;
  String? _formError;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && mounted) {
      setState(() => _dateOfBirth = picked);
    }
  }

  void _clearDateOfBirth() {
    setState(() => _dateOfBirth = null);
  }

  CreatePatientInput _buildInput({required String activeBranchId, required bool acknowledgeDuplicate}) {
    return CreatePatientInput(
      activeBranchId: activeBranchId,
      fullName: _fullNameController.text,
      phone: _phoneController.text,
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      maritalStatus: _maritalStatus,
      notes: _trimOrNull(_notesController.text),
      acknowledgeDuplicate: acknowledgeDuplicate,
    );
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final auth = ref.read(authSessionProvider);
    final activeBranchId = auth.context?.activeBranchId;
    if (activeBranchId == null || activeBranchId.isEmpty) {
      setState(() => _formError = 'Select an active branch in the shell before registering a patient.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    await _createWithDuplicateHandling(
      activeBranchId: activeBranchId,
      acknowledgeDuplicate: false,
    );
  }

  Future<void> _createWithDuplicateHandling({
    required String activeBranchId,
    required bool acknowledgeDuplicate,
  }) async {
    try {
      final patientId = await ref.read(createPatientUseCaseProvider)(
        _buildInput(activeBranchId: activeBranchId, acknowledgeDuplicate: acknowledgeDuplicate),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Patient registered successfully.')));
      context.nav.goPatientDetail(patientId);
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
        await _createWithDuplicateHandling(
          activeBranchId: activeBranchId,
          acknowledgeDuplicate: true,
        );
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
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canCreate = ref.watch(permissionServiceProvider).canCreatePatients();

    if (!canCreate) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Register patient'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => _leavePatientRegistration(context)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to register patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final dobLabel = _dateOfBirth == null ? 'Not set' : formatDate(_dateOfBirth);

    return UnsavedChangesGuard(
      hasUnsavedChanges: _hasUnsavedChanges(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Register patient'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => _leavePatientRegistration(context)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_formError != null) ...[
                  Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 16),
                ],
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
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Not specified')),
                    for (final gender in PatientGender.values)
                      DropdownMenuItem(value: gender, child: Text(gender.label)),
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
                  key: const Key('patient_register_submit'),
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Register patient'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasUnsavedChanges() {
    return _fullNameController.text.trim().isNotEmpty ||
        _phoneController.text.trim().isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        _dateOfBirth != null ||
        _gender != null ||
        _maritalStatus != null;
  }
}
