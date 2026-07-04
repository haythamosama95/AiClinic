import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_field_validation.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/duplicate_candidates_dialog.dart';

/// Shared patient registration / edit form rendered inside [EditorFormPattern].
class PatientEditorForm extends ConsumerStatefulWidget {
  const PatientEditorForm({
    this.patient,
    super.key,
  });

  /// When set, the form operates in edit mode for this patient profile.
  final PatientDetail? patient;

  bool get isEditMode => patient != null;

  @override
  ConsumerState<PatientEditorForm> createState() => _PatientEditorFormState();
}

class _PatientEditorFormState extends ConsumerState<PatientEditorForm> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  PatientGender? _gender;
  PatientMaritalStatus? _maritalStatus;
  DateTime? _expectedUpdatedAt;

  var _isSaving = false;
  var _submitted = false;
  String? _summaryError;
  String? _staleEditError;
  String? _fullNameError;
  String? _phoneError;
  String? _dateOfBirthError;
  String? _genderError;

  static final _genderOptions = [
    AppSelectOption(value: PatientGender.male, label: PatientGender.male.label),
    AppSelectOption(value: PatientGender.female, label: PatientGender.female.label),
  ];

  static final _maritalStatusOptions = [
    for (final status in PatientMaritalStatus.values)
      AppSelectOption(value: status, label: status.label),
  ];

  @override
  void initState() {
    super.initState();
    final patient = widget.patient;
    if (patient == null) {
      return;
    }
    _fullNameController.text = patient.fullName;
    _phoneController.text = patient.phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    _notesController.text = patient.notes ?? '';
    _dateOfBirth = patient.dateOfBirth;
    _gender = patient.gender;
    _maritalStatus = patient.maritalStatus;
    _expectedUpdatedAt = patient.updatedAt;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _validate() {
    final fullNameError = _fullNameController.text.trim().isEmpty ? 'Full name is required.' : null;
    final phoneError = PatientFieldValidation.validateMobileNumber(_phoneController.text);
    final dobError = _dateOfBirth == null ? 'Date of birth is required.' : null;
    final genderError = _gender == null ? 'Gender is required.' : null;

    setState(() {
      _fullNameError = fullNameError;
      _phoneError = phoneError;
      _dateOfBirthError = dobError;
      _genderError = genderError;
    });

    return fullNameError == null && phoneError == null && dobError == null && genderError == null;
  }

  CreatePatientInput _buildCreateInput({
    required String activeBranchId,
    required bool acknowledgeDuplicate,
  }) {
    return CreatePatientInput(
      activeBranchId: activeBranchId,
      fullName: _fullNameController.text.trim(),
      phone: _phoneController.text.trim(),
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      maritalStatus: _maritalStatus,
      notes: _trimOrNull(_notesController.text),
      acknowledgeDuplicate: acknowledgeDuplicate,
    );
  }

  UpdatePatientInput _buildUpdateInput({required bool acknowledgeDuplicate}) {
    final patient = widget.patient!;
    return UpdatePatientInput(
      patientId: patient.id,
      fullName: _fullNameController.text.trim(),
      expectedUpdatedAt: _expectedUpdatedAt ?? patient.updatedAt,
      phone: _phoneController.text.trim(),
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      maritalStatus: _maritalStatus,
      notes: _trimOrNull(_notesController.text),
      acknowledgeDuplicate: acknowledgeDuplicate,
    );
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      return;
    }

    final auth = ref.read(authSessionProvider);
    if (widget.isEditMode) {
      if (!AuthRouteGuard.canAccessPatientEdit(auth)) {
        return;
      }
      setState(() {
        _isSaving = true;
        _summaryError = null;
        _staleEditError = null;
      });
      await _updateWithDuplicateHandling(acknowledgeDuplicate: false);
      return;
    }

    if (!AuthRouteGuard.canAccessPatientRegistration(auth)) {
      return;
    }

    final activeBranchId = auth.context?.activeBranchId;
    if (activeBranchId == null || activeBranchId.isEmpty) {
      setState(() => _summaryError = 'Select an active branch before registering a patient.');
      return;
    }

    setState(() {
      _isSaving = true;
      _summaryError = null;
      _staleEditError = null;
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
        _buildCreateInput(activeBranchId: activeBranchId, acknowledgeDuplicate: acknowledgeDuplicate),
      );

      if (!mounted) {
        return;
      }

      ref.invalidate(patientListProvider);
      ref.showAppToast(
        message: 'Patient registered successfully.',
        variant: AppToastVariant.success,
      );
      context.nav.goPatientDetail(patientId);
    } on RpcFailure catch (error) {
      await _handleSubmitFailure(
        error,
        onDuplicateAcknowledged: () => _createWithDuplicateHandling(
          activeBranchId: activeBranchId,
          acknowledgeDuplicate: true,
        ),
      );
    } catch (error) {
      _handleUnexpectedSubmitFailure(error);
    }
  }

  Future<void> _updateWithDuplicateHandling({required bool acknowledgeDuplicate}) async {
    final patientId = widget.patient!.id;

    try {
      await ref.read(updatePatientUseCaseProvider)(
        _buildUpdateInput(acknowledgeDuplicate: acknowledgeDuplicate),
      );

      if (!mounted) {
        return;
      }

      ref.invalidate(patientDetailProvider(patientId));
      ref.invalidate(patientListProvider);
      ref.showAppToast(
        message: 'Patient updated successfully.',
        variant: AppToastVariant.success,
      );
      context.nav.goPatientDetail(patientId);
    } on RpcFailure catch (error) {
      await _handleSubmitFailure(
        error,
        onDuplicateAcknowledged: () => _updateWithDuplicateHandling(acknowledgeDuplicate: true),
        onStalePatient: () async {
          ref.invalidate(patientDetailProvider(patientId));
        },
      );
    } catch (error) {
      _handleUnexpectedSubmitFailure(error);
    }
  }

  Future<void> _handleSubmitFailure(
    RpcFailure error, {
    required Future<void> Function() onDuplicateAcknowledged,
    Future<void> Function()? onStalePatient,
  }) async {
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
      await onDuplicateAcknowledged();
      return;
    }

    if (error.isStalePatient) {
      await onStalePatient?.call();
      setState(() {
        _isSaving = false;
        _staleEditError = patientMessageForRpc(error);
        _summaryError = null;
      });
      return;
    }

    setState(() {
      _isSaving = false;
      _summaryError = patientMessageForRpc(error);
      _staleEditError = null;
    });
  }

  void _handleUnexpectedSubmitFailure(Object error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isSaving = false;
      _summaryError = UserErrorMapper.mapToUserMessage(error);
      _staleEditError = null;
    });
  }

  void _handleCancel() {
    context.nav.popOrHome();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final canSubmit = widget.isEditMode
        ? AuthRouteGuard.canAccessPatientEdit(auth)
        : AuthRouteGuard.canAccessPatientRegistration(auth);
    final isEditMode = widget.isEditMode;
    final patient = widget.patient;
    final now = DateTime.now();

    if (!canSubmit) {
      return AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: isEditMode ? 'Edit patient' : 'Register patient',
        description: isEditMode
            ? 'You do not have permission to edit patients.'
            : 'You do not have permission to register patients.',
      );
    }

    return EditorFormPattern(
      title: isEditMode ? 'Edit patient' : 'Register patient',
      description: isEditMode
          ? 'Update patient details at ${patient!.branchName}.'
          : 'Add a new patient at the active branch.',
      staleEditAlert: _staleEditError == null
          ? null
          : AppAlert(
              variant: AppAlertVariant.warning,
              title: _staleEditError!,
              body: 'Reload the patient profile and try again.',
            ),
      summaryAlert: _summaryError == null
          ? null
          : AppAlert(
              variant: AppAlertVariant.danger,
              title: _summaryError!,
            ),
      sections: [
        EditorFormSection(
          title: 'Patient details',
          description: 'Demographics and contact information recorded at registration.',
          twoColumn: true,
          fields: [
            AppFormField(
              label: 'Full name',
              requiredMark: true,
              error: _submitted ? _fullNameError : null,
              child: AppTextField(
                controller: _fullNameController,
                hintText: 'Full name as recorded at the desk.',
                disabled: _isSaving,
                invalid: _submitted && _fullNameError != null,
                onChanged: (_) {
                  if (_submitted) {
                    setState(() => _fullNameError = null);
                  }
                },
              ),
            ),
            AppFormField(
              label: 'Mobile number',
              requiredMark: true,
              error: _submitted ? _phoneError : null,
              helperText: 'Only numbers are allowed.',
              child: AppTextField(
                controller: _phoneController,
                hintText: 'Mobile number',
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                disabled: _isSaving,
                invalid: _submitted && _phoneError != null,
                onChanged: (_) {
                  if (_submitted) {
                    setState(() => _phoneError = null);
                  }
                },
              ),
            ),
            AppFormField(
              label: 'Date of birth',
              requiredMark: true,
              error: _submitted ? _dateOfBirthError : null,
              child: AppDatePicker(
                value: _dateOfBirth,
                min: DateTime(1900),
                max: now,
                disabled: _isSaving,
                invalid: _submitted && _dateOfBirthError != null,
                onChanged: (value) => setState(() {
                  _dateOfBirth = value;
                  if (_submitted) {
                    _dateOfBirthError = value == null ? 'Date of birth is required.' : null;
                  }
                }),
              ),
            ),
            AppFormField(
              label: 'Gender',
              requiredMark: true,
              error: _submitted ? _genderError : null,
              child: AppSelect<PatientGender>(
                options: _genderOptions,
                value: _gender,
                disabled: _isSaving,
                invalid: _submitted && _genderError != null,
                placeholder: 'Select gender',
                onChanged: (value) => setState(() {
                  _gender = value;
                  if (_submitted) {
                    _genderError = null;
                  }
                }),
              ),
            ),
            AppFormField(
              label: 'Marital status',
              child: AppSelect<PatientMaritalStatus>(
                options: _maritalStatusOptions,
                value: _maritalStatus,
                disabled: _isSaving,
                placeholder: 'Not specified',
                onChanged: (value) => setState(() => _maritalStatus = value),
              ),
            ),
          ],
        ),
        EditorFormSection(
          title: 'Notes',
          description: 'Front-desk notes visible on the patient profile.',
          fields: [
            AppFormField(
              label: 'Notes',
              child: AppTextArea(
                controller: _notesController,
                hintText: 'Clinical or reception notes…',
                disabled: _isSaving,
                minRows: 3,
              ),
            ),
          ],
        ),
      ],
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            disabled: _isSaving,
            onPressed: _handleCancel,
          ),
          AppButton(
            label: isEditMode ? 'Update patient' : 'Register patient',
            loading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
