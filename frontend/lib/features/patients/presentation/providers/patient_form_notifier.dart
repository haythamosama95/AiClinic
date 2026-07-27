import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_toast.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/theme/theme_transition_controller.dart';
import 'package:ai_clinic/features/patients/application/patient_rpc_messages.dart';
import 'package:ai_clinic/features/patients/domain/create_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/domain/patient_gender.dart';
import 'package:ai_clinic/features/patients/domain/patient_marital_status.dart';
import 'package:ai_clinic/features/patients/domain/patient_rpc_failure.dart';
import 'package:ai_clinic/features/patients/domain/update_patient_input.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_registration_form.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/active_branch_name_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_form_state.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

final patientFormNotifierProvider = NotifierProvider.autoDispose
    .family<PatientFormNotifier, PatientFormState, PatientFormArgs>(
      PatientFormNotifier.new,
    );

class PatientFormNotifier extends Notifier<PatientFormState> {
  PatientFormNotifier(this._args);

  final PatientFormArgs _args;

  AppLocalizations? get _l10n {
    final context = ref.read(rootNavigatorKeyProvider).currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    return context.l10n;
  }

  @override
  PatientFormState build() {
    if (_args.mode == PatientFormMode.edit && _args.patientId != null) {
      ref.listen<AsyncValue<PatientDetail>>(
        patientDetailProvider(_args.patientId!),
        (_, next) {
          next.whenData(preloadFromDetail);
        },
        fireImmediately: true,
      );
    }

    if (_args.initialDetail != null) {
      return PatientFormState.fromDetail(_args.initialDetail!);
    }

    return PatientFormState(
      mode: _args.mode,
      patientId: _args.patientId,
      hydrated: _args.mode == PatientFormMode.create,
    );
  }

  void preloadFromDetail(PatientDetail detail) {
    if (state.hydrated && !state.staleUpdateOpen) {
      return;
    }

    state = PatientFormState.fromDetail(detail);
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
    state = PatientFormState(
      mode: _args.mode,
      patientId: _args.patientId,
      hydrated: _args.mode == PatientFormMode.create,
    );
  }

  /// Acknowledges the duplicate warning and submits anyway.
  Future<PatientFormSubmitOutcome> submitAnyway() async {
    state = state.copyWith(acknowledgedDuplicate: true, duplicateOpen: false);
    return submit();
  }

  /// Closes the duplicate dialog and signals navigation to an existing patient.
  void openExistingPatient(String patientId) {
    state = state.copyWith(duplicateOpen: false, pendingOpenPatientId: patientId);
  }

  /// Reloads the form from the server after a stale-update conflict.
  void confirmStaleReload() {
    final patientId = state.patientId;
    if (patientId == null) {
      return;
    }
    state = state.copyWith(staleUpdateOpen: false, hydrated: false);
    ref.invalidate(patientDetailProvider(patientId));
  }

  /// Validates, checks for duplicates, then creates or updates the patient.
  Future<PatientFormSubmitOutcome> submit() async {
    return switch (state.mode) {
      PatientFormMode.create => _submitCreate(),
      PatientFormMode.edit => _submitEdit(),
    };
  }

  Future<PatientFormSubmitOutcome> _submitCreate() async {
    final l10n = _l10n;
    if (l10n == null) {
      return const PatientFormSubmitOutcome.failed();
    }

    final validationErrors = validateRegistration(state.values, l10n);
    if (validationErrors.hasErrors) {
      state = state.copyWith(errors: validationErrors);
      return const PatientFormSubmitOutcome.failed();
    }

    final activeBranchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (activeBranchId == null || activeBranchId.isEmpty) {
      state = state.copyWith(
        errors: PatientFormErrors(form: l10n.patientFormSelectBranchBeforeRegister),
      );
      return const PatientFormSubmitOutcome.failed();
    }

    state = state.copyWith(submitting: true, errors: PatientFormErrors.empty);

    try {
      if (!state.acknowledgedDuplicate) {
        final candidates = await ref.read(checkDuplicatesUseCaseProvider)(
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
          return const PatientFormSubmitOutcome.failed();
        }
      }

      final patientId = await ref.read(createPatientUseCaseProvider)(
        CreatePatientInput(
          activeBranchId: activeBranchId,
          fullName: state.values.fullName.trim(),
          phone: state.values.phone.trim(),
          dateOfBirth: state.values.dateOfBirth,
          gender: state.values.gender,
          maritalStatus: state.values.maritalStatus,
          notes: state.values.notes.trim().isEmpty ? null : state.values.notes.trim(),
          acknowledgeDuplicate: state.acknowledgedDuplicate,
        ),
      );

      final branchName = await ref.read(activeBranchNameProvider.future);
      final toastContext = ref.read(rootNavigatorKeyProvider).currentContext;
      if (toastContext != null && toastContext.mounted) {
        appToast(
          toastContext,
          AppToastInput(
            message: toastContext.l10n.patientFormRegisteredAtBranch(state.values.fullName.trim(), branchName),
            variant: AppToastVariant.success,
          ),
        );
      }

      state = state.copyWith(submitting: false);
      return PatientFormSubmitOutcome.created(patientId);
    } on RpcFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        errors: PatientFormErrors(form: patientMessageForRpc(failure, l10n)),
      );
      return const PatientFormSubmitOutcome.failed();
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        errors: PatientFormErrors(form: l10n.patientFormCouldNotRegister),
      );
      return const PatientFormSubmitOutcome.failed();
    }
  }

  Future<PatientFormSubmitOutcome> _submitEdit() async {
    final l10n = _l10n;
    if (l10n == null) {
      return const PatientFormSubmitOutcome.failed();
    }

    final patientId = state.patientId;
    final expectedUpdatedAt = state.expectedUpdatedAt;
    if (patientId == null || expectedUpdatedAt == null) {
      state = state.copyWith(
        errors: PatientFormErrors(form: l10n.patientFormDetailsStillLoading),
      );
      return const PatientFormSubmitOutcome.failed();
    }

    final validationErrors = validateRegistration(state.values, l10n);
    if (validationErrors.hasErrors) {
      state = state.copyWith(errors: validationErrors);
      return const PatientFormSubmitOutcome.failed();
    }

    state = state.copyWith(submitting: true, errors: PatientFormErrors.empty);

    try {
      if (!state.acknowledgedDuplicate) {
        final candidates = await ref.read(checkDuplicatesUseCaseProvider)(
          fullName: state.values.fullName.trim(),
          phone: state.values.phone.trim(),
          dateOfBirth: state.values.dateOfBirth,
          excludePatientId: patientId,
        );

        if (candidates.isNotEmpty) {
          state = state.copyWith(
            submitting: false,
            duplicateCandidates: candidates,
            duplicateOpen: true,
          );
          return const PatientFormSubmitOutcome.failed();
        }
      }

      final trimmedPhone = state.values.phone.trim();
      final trimmedNotes = state.values.notes.trim();

      await ref.read(updatePatientUseCaseProvider)(
        UpdatePatientInput(
          patientId: patientId,
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

      final toastContext = ref.read(rootNavigatorKeyProvider).currentContext;
      if (toastContext != null && toastContext.mounted) {
        appToast(
          toastContext,
          AppToastInput(
            message: toastContext.l10n.patientFormPatientUpdated(state.values.fullName.trim()),
            variant: AppToastVariant.success,
          ),
        );
      }

      ref.invalidate(patientDetailProvider(patientId));
      ref.invalidate(patientListProvider);
      state = state.copyWith(submitting: false);
      return const PatientFormSubmitOutcome.updated();
    } on RpcFailure catch (failure) {
      if (failure.isStalePatient) {
        state = state.copyWith(submitting: false, staleUpdateOpen: true, errors: PatientFormErrors.empty);
        return const PatientFormSubmitOutcome.failed();
      }

      state = state.copyWith(
        submitting: false,
        errors: PatientFormErrors(form: patientMessageForRpc(failure, l10n)),
      );
      return const PatientFormSubmitOutcome.failed();
    } catch (_) {
      state = state.copyWith(
        submitting: false,
        errors: PatientFormErrors(form: l10n.patientFormCouldNotUpdate),
      );
      return const PatientFormSubmitOutcome.failed();
    }
  }
}
