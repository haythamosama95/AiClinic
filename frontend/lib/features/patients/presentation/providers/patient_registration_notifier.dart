import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_result.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';

@immutable
class PatientRegistrationState {
  const PatientRegistrationState({
    this.values = PatientRegistrationForm.empty,
    this.errors = PatientFormErrors.empty,
    this.submitting = false,
    this.duplicateCandidates = const [],
    this.duplicateOpen = false,
    this.acknowledgedDuplicate = false,
    this.pendingOpenPatientId,
  });

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final bool submitting;
  final List<DuplicateCandidate> duplicateCandidates;
  final bool duplicateOpen;
  final bool acknowledgedDuplicate;

  /// Set by [PatientRegistrationNotifier.openExistingPatient] so the hosting
  /// dialog can close and navigate to the existing patient.
  final String? pendingOpenPatientId;

  String get trimmedName => values.fullName.trim();

  bool get showPreview => trimmedName.length >= 2;

  PatientRegistrationState copyWith({
    PatientRegistrationForm? values,
    PatientFormErrors? errors,
    bool? submitting,
    List<DuplicateCandidate>? duplicateCandidates,
    bool? duplicateOpen,
    bool? acknowledgedDuplicate,
    String? pendingOpenPatientId,
    bool clearPendingOpenPatientId = false,
  }) {
    return PatientRegistrationState(
      values: values ?? this.values,
      errors: errors ?? this.errors,
      submitting: submitting ?? this.submitting,
      duplicateCandidates: duplicateCandidates ?? this.duplicateCandidates,
      duplicateOpen: duplicateOpen ?? this.duplicateOpen,
      acknowledgedDuplicate:
          acknowledgedDuplicate ?? this.acknowledgedDuplicate,
      pendingOpenPatientId: clearPendingOpenPatientId
          ? null
          : (pendingOpenPatientId ?? this.pendingOpenPatientId),
    );
  }
}

final patientRegistrationProvider =
    StateNotifierProvider<
      PatientRegistrationNotifier,
      PatientRegistrationState
    >((ref) {
      return PatientRegistrationNotifier(ref);
    });

class PatientRegistrationNotifier
    extends StateNotifier<PatientRegistrationState> {
  PatientRegistrationNotifier(this._ref)
    : super(const PatientRegistrationState());

  final Ref _ref;

  void updateField(String key, Object? value) {
    final values = state.values;
    final nextValues = switch (key) {
      'fullName' => values.copyWith(fullName: value as String),
      'phone' => values.copyWith(phone: value as String),
      'dateOfBirth' => values.copyWith(dateOfBirth: value as DateTime?),
      'gender' => values.copyWith(gender: value as PatientGender?),
      'maritalStatus' => values.copyWith(
        maritalStatus: value as PatientMaritalStatus?,
      ),
      'notes' => values.copyWith(notes: value as String),
      _ => values,
    };

    state = state.copyWith(
      values: nextValues,
      errors: _clearFieldError(state.errors, key),
      acknowledgedDuplicate: state.acknowledgedDuplicate
          ? false
          : state.acknowledgedDuplicate,
    );
  }

  PatientFormErrors _clearFieldError(PatientFormErrors errors, String key) {
    return switch (key) {
      'fullName' => errors.copyWith(clearFullName: true),
      'phone' => errors.copyWith(clearPhone: true),
      'dateOfBirth' => errors.copyWith(clearDateOfBirth: true),
      'gender' => errors.copyWith(clearGender: true),
      'maritalStatus' => errors.copyWith(clearMaritalStatus: true),
      'notes' => errors.copyWith(clearNotes: true),
      _ => errors,
    };
  }

  void setDuplicateOpen(bool open) {
    state = state.copyWith(duplicateOpen: open);
  }

  void clearPendingOpenPatient() {
    if (state.pendingOpenPatientId != null) {
      state = state.copyWith(clearPendingOpenPatientId: true);
    }
  }

  void reset() {
    state = const PatientRegistrationState();
  }

  /// Acknowledges the duplicate warning and creates the patient anyway.
  Future<CreatePatientResult?> registerAnyway() async {
    state = state.copyWith(acknowledgedDuplicate: true, duplicateOpen: false);
    return submit();
  }

  /// Closes the duplicate dialog and signals navigation to an existing patient.
  void openExistingPatient(String patientId) {
    state = state.copyWith(
      duplicateOpen: false,
      pendingOpenPatientId: patientId,
    );
  }

  /// Validates, checks for duplicates, then creates the patient when clear.
  /// Returns the creation result (patient id + MRN) on success.
  Future<CreatePatientResult?> submit() async {
    final validationErrors = validateRegistration(state.values);
    if (validationErrors.hasErrors) {
      state = state.copyWith(errors: validationErrors);
      return null;
    }

    final activeBranchId = _ref
        .read(authSessionProvider)
        .context
        ?.activeBranchId;
    if (activeBranchId == null || activeBranchId.isEmpty) {
      state = state.copyWith(
        errors: const PatientFormErrors(
          form: 'Select an active branch before registering a patient.',
        ),
      );
      return null;
    }

    state = state.copyWith(submitting: true, errors: PatientFormErrors.empty);

    try {
      if (!state.acknowledgedDuplicate) {
        final candidates = await _ref.read(checkDuplicatesUseCaseProvider)(
          fullName: state.values.fullName.trim(),
          phone: state.values.phone.trim(),
          dateOfBirth: state.values.dateOfBirth,
        );

        if (candidates.isNotEmpty) {
          state = state.copyWith(
            submitting: false,
            duplicateCandidates: candidates,
            duplicateOpen: true,
          );
          return null;
        }
      }

      final result = await _ref.read(createPatientUseCaseProvider)(
        CreatePatientInput(
          activeBranchId: activeBranchId,
          fullName: state.values.fullName.trim(),
          phone: state.values.phone.trim(),
          dateOfBirth: state.values.dateOfBirth,
          gender: state.values.gender,
          maritalStatus: state.values.maritalStatus,
          notes: state.values.notes.trim().isEmpty
              ? null
              : state.values.notes.trim(),
          acknowledgeDuplicate: state.acknowledgedDuplicate,
        ),
      );

      state = state.copyWith(submitting: false);
      return result;
    } on RpcFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        errors: PatientFormErrors(form: patientMessageForRpc(failure)),
      );
      return null;
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        errors: const PatientFormErrors(
          form: 'Could not register the patient. Try again.',
        ),
      );
      return null;
    }
  }
}
