import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';

enum PatientFormMode { create, edit }

@immutable
class PatientFormArgs {
  const PatientFormArgs._({
    required this.mode,
    this.patientId,
    this.initialDetail,
  });

  static const create = PatientFormArgs._(mode: PatientFormMode.create);

  factory PatientFormArgs.edit({
    required String patientId,
    PatientDetail? initialDetail,
  }) =>
      PatientFormArgs._(
        mode: PatientFormMode.edit,
        patientId: patientId,
        initialDetail: initialDetail,
      );

  final PatientFormMode mode;
  final String? patientId;
  final PatientDetail? initialDetail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatientFormArgs &&
          mode == other.mode &&
          patientId == other.patientId &&
          initialDetail == other.initialDetail;

  @override
  int get hashCode => Object.hash(mode, patientId, initialDetail);
}

@immutable
class PatientFormSubmitOutcome {
  const PatientFormSubmitOutcome._({this.patientId, this.succeeded = false});

  const PatientFormSubmitOutcome.failed() : this._();

  const PatientFormSubmitOutcome.created(String patientId) : this._(patientId: patientId, succeeded: true);

  const PatientFormSubmitOutcome.updated() : this._(succeeded: true);

  final String? patientId;
  final bool succeeded;
}

@immutable
class PatientFormState {
  const PatientFormState({
    required this.mode,
    this.patientId,
    this.values = PatientRegistrationForm.empty,
    this.errors = PatientFormErrors.empty,
    this.submitting = false,
    this.duplicateCandidates = const [],
    this.duplicateOpen = false,
    this.acknowledgedDuplicate = false,
    this.pendingOpenPatientId,
    this.expectedUpdatedAt,
    this.branchName,
    this.hydrated = false,
    this.staleUpdateOpen = false,
  });

  factory PatientFormState.fromDetail(PatientDetail detail) {
    return PatientFormState(
      mode: PatientFormMode.edit,
      patientId: detail.id,
      values: PatientRegistrationForm.fromPatientDetail(detail),
      expectedUpdatedAt: detail.updatedAt,
      branchName: detail.branchName,
      hydrated: true,
    );
  }

  final PatientFormMode mode;
  final String? patientId;
  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final bool submitting;
  final List<DuplicateCandidate> duplicateCandidates;
  final bool duplicateOpen;
  final bool acknowledgedDuplicate;

  /// Set by [PatientFormNotifier.openExistingPatient] so the hosting dialog can
  /// close and navigate to the existing patient.
  final String? pendingOpenPatientId;
  final DateTime? expectedUpdatedAt;
  final String? branchName;
  final bool hydrated;
  final bool staleUpdateOpen;

  String get trimmedName => values.fullName.trim();

  bool get showPreview => trimmedName.length >= 2;

  PatientFormState copyWith({
    PatientFormMode? mode,
    String? patientId,
    PatientRegistrationForm? values,
    PatientFormErrors? errors,
    bool? submitting,
    List<DuplicateCandidate>? duplicateCandidates,
    bool? duplicateOpen,
    bool? acknowledgedDuplicate,
    String? pendingOpenPatientId,
    bool clearPendingOpenPatientId = false,
    DateTime? expectedUpdatedAt,
    String? branchName,
    bool? hydrated,
    bool? staleUpdateOpen,
  }) {
    return PatientFormState(
      mode: mode ?? this.mode,
      patientId: patientId ?? this.patientId,
      values: values ?? this.values,
      errors: errors ?? this.errors,
      submitting: submitting ?? this.submitting,
      duplicateCandidates: duplicateCandidates ?? this.duplicateCandidates,
      duplicateOpen: duplicateOpen ?? this.duplicateOpen,
      acknowledgedDuplicate: acknowledgedDuplicate ?? this.acknowledgedDuplicate,
      pendingOpenPatientId:
          clearPendingOpenPatientId ? null : (pendingOpenPatientId ?? this.pendingOpenPatientId),
      expectedUpdatedAt: expectedUpdatedAt ?? this.expectedUpdatedAt,
      branchName: branchName ?? this.branchName,
      hydrated: hydrated ?? this.hydrated,
      staleUpdateOpen: staleUpdateOpen ?? this.staleUpdateOpen,
    );
  }
}
