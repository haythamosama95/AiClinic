import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_surface_invalidation.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/clinic_setup_draft_mapper.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

const _setupDraftKey = 'aiclinic:setup-draft';
const _setupCompleteKey = 'aiclinic:setup-complete';
const _setupCompletedStepsKey = 'aiclinic:setup-completed-steps';

@immutable
class ClinicSetupDraftState {
  const ClinicSetupDraftState({
    required this.draft,
    this.step = 0,
    this.completed = false,
    this.completedSteps = const {},
    this.confirmedBranchIds = const {},
    this.confirmedStaffIds = const {},
    this.confirmedServiceIds = const {},
    this.isSubmitting = false,
    this.submitError,
  });

  final SetupDraft draft;
  final int step;
  final bool completed;
  final Set<int> completedSteps;

  /// Branch/staff/service rows the user explicitly saved in the wizard UI.
  /// Not persisted — only keeps collapsed summaries stable across step transitions.
  final Set<String> confirmedBranchIds;
  final Set<String> confirmedStaffIds;
  final Set<String> confirmedServiceIds;
  final bool isSubmitting;
  final String? submitError;

  ClinicSetupDraftState copyWith({
    SetupDraft? draft,
    int? step,
    bool? completed,
    Set<int>? completedSteps,
    Set<String>? confirmedBranchIds,
    Set<String>? confirmedStaffIds,
    Set<String>? confirmedServiceIds,
    bool? isSubmitting,
    String? submitError,
    bool clearSubmitError = false,
  }) {
    return ClinicSetupDraftState(
      draft: draft ?? this.draft,
      step: step ?? this.step,
      completed: completed ?? this.completed,
      completedSteps: completedSteps ?? this.completedSteps,
      confirmedBranchIds: confirmedBranchIds ?? this.confirmedBranchIds,
      confirmedStaffIds: confirmedStaffIds ?? this.confirmedStaffIds,
      confirmedServiceIds: confirmedServiceIds ?? this.confirmedServiceIds,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: clearSubmitError ? null : (submitError ?? this.submitError),
    );
  }
}

final clinicSetupDraftProvider = StateNotifierProvider<ClinicSetupDraftNotifier, ClinicSetupDraftState>((ref) {
  final notifier = ClinicSetupDraftNotifier(ref);
  ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
    unawaited(notifier.syncWithSession(next.context));
  });
  return notifier;
});

/// Whether the clinic setup wizard has been completed.
///
/// Backend session state is authoritative while bootstrap is incomplete. After
/// the server reports a configured clinic, the local draft `completed` flag
/// drives the settings setup UX (including "Run setup again").
final isSetupCompleteProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).context;
  if (session != null && session.needsClinicSetup) {
    return false;
  }
  return ref.watch(clinicSetupDraftProvider).completed;
});

/// Page-local setup draft notifier mirroring web `SetupContext`.
class ClinicSetupDraftNotifier extends StateNotifier<ClinicSetupDraftState> {
  ClinicSetupDraftNotifier(this._ref) : super(ClinicSetupDraftState(draft: createDefaultSetup())) {
    Future<void>.microtask(loadDraft);
  }

  final Ref _ref;

  /// Loads the persisted draft and completion flag from [SharedPreferences].
  ///
  /// Web does not persist wizard step — only the draft and completion flag are
  /// restored; [ClinicSetupDraftState.step] always starts at 0.
  Future<void> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_setupDraftKey);
      var completed = prefs.getString(_setupCompleteKey) == 'true';
      final completedSteps = _readCompletedSteps(prefs.getString(_setupCompletedStepsKey));

      final session = _ref.read(authSessionProvider).context;
      if (!completed && session != null && !session.needsClinicSetup) {
        completed = true;
      }

      final draft = raw == null || raw.isEmpty
          ? createDefaultSetup()
          : SetupDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      state = ClinicSetupDraftState(draft: draft, completed: completed, completedSteps: completedSteps);
      await syncWithSession(_ref.read(authSessionProvider).context);
    } on Object {
      state = ClinicSetupDraftState(draft: createDefaultSetup());
    }
  }

  /// Aligns cached completion flags with the latest backend session (e.g. after clinic reset).
  Future<void> syncWithSession(AuthSessionContext? session) async {
    if (session == null) {
      return;
    }

    if (!session.needsClinicSetup) {
      return;
    }

    if (!state.completed && state.completedSteps.isEmpty) {
      return;
    }

    state = ClinicSetupDraftState(draft: createDefaultSetup(), step: 0, completed: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_setupCompleteKey);
      await prefs.remove(_setupCompletedStepsKey);
      await prefs.remove(_setupDraftKey);
    } on Object {
      // No-op when preferences are unavailable.
    }
  }

  Set<int> _readCompletedSteps(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((step) => step as int).toSet();
    } on Object {
      return const {};
    }
  }

  /// Persists the current draft to [SharedPreferences].
  Future<void> persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_setupDraftKey, jsonEncode(state.draft.toJson()));
      await prefs.setString(_setupCompletedStepsKey, jsonEncode(state.completedSteps.toList()..sort()));
    } on Object {
      // No-op when preferences are unavailable.
    }
  }

  void setStep(int step) {
    state = state.copyWith(step: step < 0 ? 0 : step, clearSubmitError: true);
    persistDraft();
  }

  /// Caches the current step as finished after validation passes.
  void markStepComplete(int step) {
    if (step < 0) {
      return;
    }
    state = state.copyWith(completedSteps: {...state.completedSteps, step});
    persistDraft();
  }

  void updateOrganization({String? name, String? timezone, String? currency}) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        organization: state.draft.organization.copyWith(name: name, timezone: timezone, currency: currency),
      ),
    );
  }

  void setBranches(List<BranchDraft> branches) {
    state = state.copyWith(draft: state.draft.copyWith(branches: branches));
  }

  void updateBranch(
    String id, {
    String? name,
    String? code,
    String? mobile,
    String? mapLocation,
    List<WorkingDay>? workingDays,
  }) {
    setBranches(
      state.draft.branches
          .map(
            (branch) => branch.id == id
                ? branch.copyWith(
                    name: name,
                    code: code,
                    mobile: mobile,
                    mapLocation: mapLocation,
                    workingDays: workingDays,
                  )
                : branch,
          )
          .toList(),
    );
  }

  BranchDraft addBranch() {
    final branch = createEmptyBranch();
    setBranches([...state.draft.branches, branch]);
    return branch;
  }

  void removeBranch(String id) {
    final nextBranches = state.draft.branches.where((branch) => branch.id != id).toList();
    final nextConfirmed = {...state.confirmedBranchIds}..remove(id);
    state = state.copyWith(
      draft: state.draft.copyWith(branches: nextBranches),
      confirmedBranchIds: nextConfirmed,
    );
  }

  void confirmBranch(String id) {
    state = state.copyWith(confirmedBranchIds: {...state.confirmedBranchIds, id});
  }

  void unconfirmBranch(String id) {
    final next = {...state.confirmedBranchIds}..remove(id);
    state = state.copyWith(confirmedBranchIds: next);
  }

  void setStaff(List<StaffDraft> staff) {
    state = state.copyWith(draft: state.draft.copyWith(staff: staff));
  }

  void updateStaff(
    String id, {
    String? name,
    String? mobile,
    String? username,
    String? password,
    String? role,
    List<String>? branchIds,
  }) {
    setStaff(
      state.draft.staff
          .map(
            (member) => member.id == id
                ? member.copyWith(
                    name: name,
                    mobile: mobile,
                    username: username,
                    password: password,
                    role: role,
                    branchIds: branchIds,
                  )
                : member,
          )
          .toList(),
    );
  }

  StaffDraft addStaff() {
    final member = createEmptyStaff();
    setStaff([...state.draft.staff, member]);
    return member;
  }

  void removeStaff(String id) {
    final nextStaff = state.draft.staff.where((member) => member.id != id).toList();
    final nextConfirmed = {...state.confirmedStaffIds}..remove(id);
    state = state.copyWith(
      draft: state.draft.copyWith(staff: nextStaff),
      confirmedStaffIds: nextConfirmed,
    );
  }

  void confirmStaff(String id) {
    state = state.copyWith(confirmedStaffIds: {...state.confirmedStaffIds, id});
  }

  void unconfirmStaff(String id) {
    final next = {...state.confirmedStaffIds}..remove(id);
    state = state.copyWith(confirmedStaffIds: next);
  }

  void setServices(List<ServiceDraft> services) {
    state = state.copyWith(draft: state.draft.copyWith(services: services));
  }

  void updateService(String id, {String? name, double? price, bool clearPrice = false}) {
    setServices(
      state.draft.services
          .map(
            (service) =>
                service.id == id ? service.copyWith(name: name, price: price, clearPrice: clearPrice) : service,
          )
          .toList(),
    );
  }

  ServiceDraft addService() {
    final service = createEmptyService();
    setServices([...state.draft.services, service]);
    return service;
  }

  void removeService(String id) {
    final nextServices = state.draft.services.where((service) => service.id != id).toList();
    final nextConfirmed = {...state.confirmedServiceIds}..remove(id);
    state = state.copyWith(
      draft: state.draft.copyWith(services: nextServices),
      confirmedServiceIds: nextConfirmed,
    );
  }

  void confirmService(String id) {
    state = state.copyWith(confirmedServiceIds: {...state.confirmedServiceIds, id});
  }

  void unconfirmService(String id) {
    final next = {...state.confirmedServiceIds}..remove(id);
    state = state.copyWith(confirmedServiceIds: next);
  }

  /// Persists the cached draft to the backend when bootstrap setup is required.
  Future<bool> completeSetup() async {
    state = state.copyWith(isSubmitting: true, clearSubmitError: true);
    await persistDraft();

    final session = _ref.read(authSessionProvider).context;
    if (session?.needsClinicSetup ?? false) {
      if (session != null && !session.canPerformBootstrapSetup) {
        state = state.copyWith(
          isSubmitting: false,
          submitError: 'Only the clinic administrator account can run first-time setup.',
        );
        return false;
      }

      AppLog.info('settings.setup.finish.start');
      try {
        final input = toBootstrapFinishSetupInput(state.draft);
        await _ref.read(finishBootstrapSetupUseCaseProvider)(input);
        await _ref.read(authSessionProvider.notifier).refreshSessionContext();
        invalidateAppointmentSurfaceProviders(_ref);
        AppLog.info('settings.setup.finish.ok');

        state = state.copyWith(completed: true, isSubmitting: false, completedSteps: {0, 1, 2, 3});
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_setupCompleteKey, 'true');
        } on Object {
          // No-op when preferences are unavailable.
        }
        await persistDraft();
        return true;
      } on RpcFailure catch (error) {
        AppLog.warning('settings.setup.finish.rpc_failed code=${error.code}');
        state = state.copyWith(isSubmitting: false, submitError: setupMessageForRpc(error));
        return false;
      } on StateError catch (error) {
        state = state.copyWith(isSubmitting: false, submitError: error.message);
        return false;
      } catch (error) {
        AppLog.warning('settings.setup.finish.failed reason=${error.runtimeType}');
        state = state.copyWith(
          isSubmitting: false,
          submitError: 'Unable to save clinic setup. Check connectivity and try again.',
        );
        return false;
      }
    }

    state = state.copyWith(completed: true, isSubmitting: false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_setupCompleteKey, 'true');
    } on Object {
      // No-op when preferences are unavailable.
    }
    await persistDraft();
    return true;
  }

  Future<void> resetSetup() async {
    final fresh = createDefaultSetup();
    state = ClinicSetupDraftState(
      draft: fresh,
      step: 0,
      completed: false,
      confirmedBranchIds: const {},
      confirmedStaffIds: const {},
      confirmedServiceIds: const {},
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_setupCompleteKey);
      await prefs.remove(_setupCompletedStepsKey);
    } on Object {
      // No-op when preferences are unavailable.
    }
    await persistDraft();
  }
}
