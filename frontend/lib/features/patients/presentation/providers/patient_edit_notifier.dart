import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/data/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/duplicate_candidate.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';

@immutable
class PatientEditState {
  const PatientEditState({
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

  final PatientRegistrationForm values;
  final PatientFormErrors errors;
  final bool submitting;
  final List<DuplicateCandidate> duplicateCandidates;
  final bool duplicateOpen;
  final bool acknowledgedDuplicate;
  final String? pendingOpenPatientId;
  final DateTime? expectedUpdatedAt;
  final String? branchName;
  final bool hydrated;
  final bool staleUpdateOpen;

  String get trimmedName => values.fullName.trim();

  bool get showPreview => trimmedName.length >= 2;

  PatientEditState copyWith({
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
    return PatientEditState(
      values: values ?? this.values,
      errors: errors ?? this.errors,
      submitting: submitting ?? this.submitting,
      duplicateCandidates: duplicateCandidates ?? this.duplicateCandidates,
      duplicateOpen: duplicateOpen ?? this.duplicateOpen,
      acknowledgedDuplicate: acknowledgedDuplicate ?? this.acknowledgedDuplicate,
      pendingOpenPatientId: clearPendingOpenPatientId ? null : (pendingOpenPatientId ?? this.pendingOpenPatientId),
      expectedUpdatedAt: expectedUpdatedAt ?? this.expectedUpdatedAt,
      branchName: branchName ?? this.branchName,
      hydrated: hydrated ?? this.hydrated,
      staleUpdateOpen: staleUpdateOpen ?? this.staleUpdateOpen,
    );
  }
}

final patientEditProvider = StateNotifierProvider.family<PatientEditNotifier, PatientEditState, String>((
  ref,
  patientId,
) {
  final notifier = PatientEditNotifier(ref, patientId);

  ref.listen<AsyncValue<PatientDetail>>(patientDetailProvider(patientId), (_, next) {
    next.whenData((detail) => notifier.preloadFromDetail(detail, isRefreshing: next.isRefreshing));
  }, fireImmediately: true);

  return notifier;
});

/// Returns a mounted root navigator context when the widget tree is available.
BuildContext? _rootNavigatorContext(Ref ref) {
  try {
    final context = ref.read(rootNavigatorKeyProvider).currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    return context;
  } catch (_) {
    // Unit tests and other non-widget contexts have no binding yet.
    return null;
  }
}

class PatientEditNotifier extends StateNotifier<PatientEditState> {
  PatientEditNotifier(this._ref, this._patientId) : super(const PatientEditState());

  final Ref _ref;
  final String _patientId;

  void preloadFromDetail(PatientDetail detail, {bool isRefreshing = false}) {
    if (isRefreshing && (state.staleUpdateOpen || (!state.hydrated && state.expectedUpdatedAt != null))) {
      return;
    }
    if (state.hydrated && !state.staleUpdateOpen) {
      return;
    }

    state = PatientEditState(
      values: PatientRegistrationForm.fromPatientDetail(detail),
      expectedUpdatedAt: detail.updatedAt,
      branchName: detail.branchName,
      hydrated: true,
    );
  }

  void updateField(String key, Object? value) {
    final values = state.values;
    final nextValues = switch (key) {
      'fullName' => values.copyWith(fullName: value as String),
      'phone' => values.copyWith(phone: value as String),
      'dateOfBirth' => values.copyWith(dateOfBirth: value as DateTime?),
      'gender' => values.copyWith(gender: value as PatientGender?),
      'maritalStatus' => values.copyWith(maritalStatus: value as PatientMaritalStatus?),
      'notes' => values.copyWith(notes: value as String),
      _ => values,
    };

    state = state.copyWith(
      values: nextValues,
      errors: _clearFieldError(state.errors, key),
      acknowledgedDuplicate: state.acknowledgedDuplicate ? false : state.acknowledgedDuplicate,
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

  void setStaleUpdateOpen(bool open) {
    state = state.copyWith(staleUpdateOpen: open);
  }

  void clearPendingOpenPatient() {
    if (state.pendingOpenPatientId != null) {
      state = state.copyWith(clearPendingOpenPatientId: true);
    }
  }

  void reset() {
    state = const PatientEditState();
  }

  /// Acknowledges the duplicate warning and saves the patient anyway.
  Future<bool> saveAnyway() async {
    state = state.copyWith(acknowledgedDuplicate: true, duplicateOpen: false);
    return submit();
  }

  /// Closes the duplicate dialog and signals navigation to an existing patient.
  void openExistingPatient(String patientId) {
    state = state.copyWith(duplicateOpen: false, pendingOpenPatientId: patientId);
  }

  /// Reloads the form from the server after a stale-update conflict.
  void confirmStaleReload() {
    state = state.copyWith(staleUpdateOpen: false, hydrated: false);
    _ref.invalidate(patientDetailProvider(_patientId));
  }

  /// Validates, checks for duplicates, then updates the patient when clear.
  /// Returns `true` on success.
  Future<bool> submit() async {
    final expectedUpdatedAt = state.expectedUpdatedAt;
    if (expectedUpdatedAt == null) {
      state = state.copyWith(errors: const PatientFormErrors(form: 'Patient details are still loading. Try again.'));
      return false;
    }

    final validationErrors = validateRegistration(state.values);
    if (validationErrors.hasErrors) {
      state = state.copyWith(errors: validationErrors);
      return false;
    }

    state = state.copyWith(submitting: true, errors: PatientFormErrors.empty);

    try {
      if (!state.acknowledgedDuplicate) {
        final candidates = await _ref.read(checkDuplicatesUseCaseProvider)(
          fullName: state.values.fullName.trim(),
          phone: state.values.phone.trim(),
          dateOfBirth: state.values.dateOfBirth,
          excludePatientId: _patientId,
        );

        if (candidates.isNotEmpty) {
          state = state.copyWith(submitting: false, duplicateCandidates: candidates, duplicateOpen: true);
          return false;
        }
      }

      final trimmedPhone = state.values.phone.trim();
      final trimmedNotes = state.values.notes.trim();

      await _ref.read(updatePatientUseCaseProvider)(
        UpdatePatientInput(
          patientId: _patientId,
          fullName: state.values.fullName.trim(),
          expectedUpdatedAt: expectedUpdatedAt,
          phone: trimmedPhone.isEmpty ? null : trimmedPhone,
          dateOfBirth: state.values.dateOfBirth,
          gender: state.values.gender,
          maritalStatus: state.values.maritalStatus,
          notes: trimmedNotes.isEmpty ? null : trimmedNotes,
          acknowledgeDuplicate: state.acknowledgedDuplicate,
        ),
      );

      final toastContext = _rootNavigatorContext(_ref);
      if (toastContext != null && toastContext.mounted) {
        appToast(
          toastContext,
          AppToastInput(message: '${state.values.fullName.trim()} updated.', variant: AppToastVariant.success),
        );
      }

      _ref.invalidate(patientDetailProvider(_patientId));
      _ref.invalidate(patientListProvider);
      state = state.copyWith(submitting: false);
      return true;
    } on RpcFailure catch (failure) {
      if (failure.isStalePatient) {
        state = state.copyWith(submitting: false, staleUpdateOpen: true, errors: PatientFormErrors.empty);
        return false;
      }

      state = state.copyWith(submitting: false, errors: PatientFormErrors(form: patientMessageForRpc(failure)));
      return false;
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        errors: const PatientFormErrors(form: 'Could not update the patient. Try again.'),
      );
      return false;
    }
  }
}
