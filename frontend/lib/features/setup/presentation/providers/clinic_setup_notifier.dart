import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/app/application/clinic_setup_orchestrator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/application/provisioning_rpc_messages.dart';
import 'package:ai_clinic/features/setup/application/setup_rpc_messages.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_result.dart';
import 'package:ai_clinic/features/setup/domain/clinic_setup_draft_mapper.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_validation.dart';

const _setupDraftKey = 'aiclinic:setup-draft';
const _setupCompleteKey = 'aiclinic:setup-complete';
const _setupCompletedStepsKey = 'aiclinic:setup-completed-steps';

@immutable
class ClinicSetupState {
  const ClinicSetupState({
    required this.draft,
    this.step = 0,
    this.completed = false,
    this.completedSteps = const {},
    this.confirmedBranchIds = const {},
    this.confirmedStaffIds = const {},
    this.confirmedServiceIds = const {},
    this.isSubmitting = false,
    this.submitError,
    this.validationFocusEntityId,
  });

  final SetupDraft draft;
  final int step;
  final bool completed;
  final Set<int> completedSteps;

  final Set<String> confirmedBranchIds;
  final Set<String> confirmedStaffIds;
  final Set<String> confirmedServiceIds;
  final bool isSubmitting;
  final String? submitError;

  final String? validationFocusEntityId;

  /// Whether the first-run wizard is in progress.
  ///
  /// Backend session state is authoritative for "is setup done". The local
  /// `completed` flag is a UI hint only and can lag the JWT on cold start, so we
  /// expose both: [isBootstrapWizardInProgress] defers to the session flag when
  /// available (see [isBootstrapSetupRequiredProvider]) and otherwise falls back
  /// to `!completed`. Routing consumers should prefer
  /// [isBootstrapSetupRequiredProvider] so they never act on a stale local flag.
  bool get isBootstrapWizardInProgress => !completed;

  ClinicSetupState copyWith({
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
    Object? validationFocusEntityId = _validationFocusSentinel,
  }) {
    return ClinicSetupState(
      draft: draft ?? this.draft,
      step: step ?? this.step,
      completed: completed ?? this.completed,
      completedSteps: completedSteps ?? this.completedSteps,
      confirmedBranchIds: confirmedBranchIds ?? this.confirmedBranchIds,
      confirmedStaffIds: confirmedStaffIds ?? this.confirmedStaffIds,
      confirmedServiceIds: confirmedServiceIds ?? this.confirmedServiceIds,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      submitError: clearSubmitError ? null : (submitError ?? this.submitError),
      validationFocusEntityId: identical(validationFocusEntityId, _validationFocusSentinel)
          ? this.validationFocusEntityId
          : validationFocusEntityId as String?,
    );
  }
}

const _validationFocusSentinel = Object();

final clinicSetupProvider = StateNotifierProvider<ClinicSetupNotifier, ClinicSetupState>((ref) {
  final notifier = ClinicSetupNotifier(ref);
  ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
    // Skip session syncs until the initial draft load has finished so the cold-start
    // `unknown -> unauthenticated` transition cannot resurrect a wiped draft that
    // `loadDraft` is still holding across its `SharedPreferences` await (see review §3.3).
    if (!notifier.initialLoadDone) {
      return;
    }
    unawaited(notifier.syncWithSession(next.context));
  });
  return notifier;
});

/// Whether the clinic setup wizard has been completed.
///
/// Backend session state is authoritative while bootstrap is incomplete. After
/// the server reports a configured clinic, the local draft `completed` flag
/// drives the setup UX (including "Run setup again").
final isSetupCompleteProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).context;
  if (session != null && session.needsClinicSetup) {
    return false;
  }
  return ref.watch(clinicSetupProvider).completed;
});

/// Authoritative "is first-run bootstrap still required" flag used by routing.
///
/// Derived from the JWT-backed session context (`needsClinicSetup`) rather than
/// the local `completed` flag so the router cannot act on a stale local draft
/// during the cold-start window before `loadDraft`/`syncWithSession` reconcile.
final isBootstrapSetupRequiredProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).context;
  if (session != null) {
    return session.needsClinicSetup;
  }
  // No context yet (unknown/loading): assume required so the guard stays closed.
  return ref.watch(clinicSetupProvider).isBootstrapWizardInProgress;
});

/// Unified clinic setup notifier.
///
/// Merges the first-run atomic bootstrap wizard (formerly [SetupNotifier]) with
/// the re-run/hydrate steady-state draft flow (formerly
/// [ClinicSetupNotifier]). Handles both initial clinic setup via
/// `bootstrap_finish_setup` RPC and re-configuration of an existing clinic via
/// steady-state CRUD APIs.
class ClinicSetupNotifier extends StateNotifier<ClinicSetupState> {
  ClinicSetupNotifier(this._ref) : super(ClinicSetupState(draft: createDefaultSetup())) {
    Future<void>.microtask(loadDraft);
  }

  final Ref _ref;

  /// Whether the initial draft load from [SharedPreferences] has completed.
  ///
  /// Session-sync listeners skip until this is `true` to avoid resurrecting a
  /// reset draft during the cold-start race (review §3.3).
  bool _initialLoadDone = false;

  bool get initialLoadDone => _initialLoadDone;

  /// Loads the persisted draft and completion flag from [SharedPreferences].
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

      state = ClinicSetupState(draft: draft, completed: completed, completedSteps: completedSteps);
      _initialLoadDone = true;
      await syncWithSession(_ref.read(authSessionProvider).context);
    } on Object {
      state = ClinicSetupState(draft: createDefaultSetup());
      _initialLoadDone = true;
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

    state = ClinicSetupState(draft: createDefaultSetup(), step: 0, completed: false);
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

  /// Persists the cached draft to the backend.
  ///
  /// In first-run mode (`needsClinicSetup == true`), calls the atomic
  /// `bootstrap_finish_setup` RPC to create the organization, primary branch, and
  /// staff accounts together, then persists the remaining branches, staff branch
  /// assignments, and services through the steady-state CRUD path so the wizard
  /// no longer silently discards them (review §3.1). The draft is then
  /// re-hydrated from the backend so it reflects truth rather than the input.
  ///
  /// In steady-state mode, persists changes via individual CRUD operations
  /// (`persistSetupDraftToBackend`).
  Future<bool> completeSetup() async {
    // Re-entrancy guard: a programmatic double-invocation could fire the RPCs
    // twice and corrupt local state (review §3.4).
    if (state.isSubmitting) {
      return false;
    }

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

      AppLog.info('setup.finish.start');
      try {
        final input = toBootstrapFinishSetupInput(state.draft);
        final result = await _ref.read(finishBootstrapSetupUseCaseProvider)(input);
        await _ref.read(authSessionProvider.notifier).refreshSessionContext();

        // The atomic RPC only stores the primary branch + staff (each auto-assigned
        // to that branch). Persist the remaining branches, the user's selected staff
        // branch assignments, and services through the steady-state path so nothing
        // the wizard collected is silently dropped (review §3.1).
        var partialFailureMessage = await _persistRemainingBootstrapEntities(result);

        // Always hydrate so the draft mirrors backend truth (which may be a subset
        // if the steady-state follow-up partially failed).
        await hydrateFromBackend();
        _orchestrator.notifyClinicDataChanged();
        AppLog.info('setup.finish.ok');

        state = state.copyWith(
          completed: true,
          isSubmitting: false,
          completedSteps: {0, 1, 2, 3},
          submitError: partialFailureMessage,
        );
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_setupCompleteKey, 'true');
        } on Object {
          // No-op when preferences are unavailable.
        }
        await persistDraft();
        return true;
      } on RpcFailure catch (error) {
        AppLog.warning('setup.finish.rpc_failed code=${error.code}');
        state = state.copyWith(isSubmitting: false, submitError: _finishSetupMessageForRpc(error));
        return false;
      } on StateError catch (error) {
        state = state.copyWith(isSubmitting: false, submitError: error.message);
        return false;
      } catch (error) {
        AppLog.warning('setup.finish.failed reason=${error.runtimeType}');
        state = state.copyWith(
          isSubmitting: false,
          submitError: 'Unable to save clinic setup. Check connectivity and try again.',
        );
        return false;
      }
    }

    final organizationId = session?.organizationId?.trim();
    if (organizationId == null || organizationId.isEmpty) {
      state = state.copyWith(isSubmitting: false, submitError: 'Sign in again to save clinic setup.');
      return false;
    }

    AppLog.info('setup.finish.steady_state.start');
    try {
      await _orchestrator.persistSteadyState(state.draft);

      await hydrateFromBackend();
      _orchestrator.notifyClinicDataChanged();
      AppLog.info('setup.finish.steady_state.ok');

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
      AppLog.warning('setup.finish.steady_state.rpc_failed code=${error.code}');
      // Partial failure may have left the backend partway through the save. Hydrate
      // so the draft reflects whatever actually committed (review §3.5).
      await _safeHydrateFromBackend();
      state = state.copyWith(isSubmitting: false, submitError: setupMessageForRpc(error));
      return false;
    } on StateError catch (error) {
      await _safeHydrateFromBackend();
      state = state.copyWith(isSubmitting: false, submitError: error.message);
      return false;
    } catch (error) {
      AppLog.warning('setup.finish.steady_state.failed reason=${error.runtimeType}');
      await _safeHydrateFromBackend();
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Unable to save clinic setup. Some changes may not have been saved; review your setup.',
      );
      return false;
    }
  }

  ClinicSetupOrchestrator get _orchestrator => _ref.read(clinicSetupOrchestratorProvider);

  /// Persists the extra branches, staff branch assignments, and services that the
  /// atomic `bootstrap_finish_setup` RPC does not store. Delegates to the
  /// orchestrator which remaps the primary branch + staff to their backend ids
  /// and runs the steady-state CRUD path.
  ///
  /// Returns a partial-failure message (or `null` when everything committed) so
  /// callers can surface it without masking the fact that the atomic core
  /// succeeded.
  Future<String?> _persistRemainingBootstrapEntities(BootstrapFinishSetupResult result) async {
    if (state.draft.branches.length <= 1 &&
        state.draft.services.isEmpty &&
        state.draft.staff.every((member) => member.branchIds.length <= 1)) {
      return null;
    }

    try {
      await _orchestrator.persistRemainingBootstrapEntities(
        primaryBranchId: result.branchId,
        staffMemberIds: result.staffMemberIds,
        draft: state.draft,
      );
      return null;
    } on RpcFailure catch (error) {
      AppLog.warning('setup.finish.remaining_persist.rpc_failed code=${error.code}');
      return setupMessageForRpc(error);
    } on StateError catch (error) {
      AppLog.warning('setup.finish.remaining_persist.state_error');
      return error.message;
    } catch (error) {
      AppLog.warning('setup.finish.remaining_persist.failed reason=${error.runtimeType}');
      return 'Some branches, staff assignments, or services could not be saved. Review your setup in Settings.';
    }
  }

  Future<void> _safeHydrateFromBackend() async {
    try {
      await hydrateFromBackend();
    } catch (error) {
      AppLog.warning('setup.hydrate.after_failure reason=${error.runtimeType}');
    }
  }

  Future<void> resetSetup() async {
    final fresh = createDefaultSetup();
    state = ClinicSetupState(
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

  /// Marks setup as complete without an RPC call.
  ///
  /// Used by the dev clinic seed flow after dummy data has been injected
  /// directly into the database, bypassing the wizard's `completeSetup()`.
  void markSetupComplete() {
    state = state.copyWith(completed: true, completedSteps: {0, 1, 2, 3});
    Future<void>.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_setupCompleteKey, 'true');
      } on Object {
        // No-op when preferences are unavailable.
      }
    });
  }

  /// Wipes org/branch data via dev RPC and reloads session claims for another setup run.
  Future<bool> resetInstallationForDevelopment() async {
    // Dev-only destructive operation: hard-guard at the notifier layer so it can
    // never run outside a debug build (review §6.8). The shell widget also gates the
    // UI, but this is the authoritative runtime guard.
    if (!kDebugMode) {
      return false;
    }
    // Re-entrancy guard, mirroring completeSetup (review §3.4).
    if (state.isSubmitting) {
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearSubmitError: true);
    AppLog.info('setup.dev_reset.start');

    try {
      final result = await _ref.read(resetInstallationUseCaseProvider)();
      AppLog.info(
        'setup.dev_reset.rpc_ok orgs=${result.data?['organizations_deleted']} '
        'branches=${result.data?['branches_deleted']}',
      );

      await _ref.read(authSessionProvider.notifier).refreshSessionContext();
      AppLog.info(
        'setup.dev_reset.session_refreshed setup_required=${_ref.read(authSessionProvider).context?.setupRequired}',
      );

      _orchestrator.notifyClinicDataChanged();
      await resetSetup();
      state = state.copyWith(isSubmitting: false);
      return true;
    } on RpcFailure catch (error) {
      AppLog.warning('setup.dev_reset.rpc_failed code=${error.code}');
      state = state.copyWith(isSubmitting: false, submitError: setupMessageForRpc(error));
      return false;
    } catch (error) {
      AppLog.warning('setup.dev_reset.failed reason=${error.runtimeType} detail=$error');
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Unable to reset clinic data. Check connectivity and try again.',
      );
      return false;
    }
  }

  /// Fetches organization, branches, staff, and services from the backend and
  /// applies them to the setup draft. Skipped during first-time bootstrap when
  /// no organization exists yet. Delegates the cross-feature fetch to the
  /// orchestrator (review §6.2) and applies setup-specific state (dev passwords,
  /// confirmed IDs) locally.
  Future<void> hydrateFromBackend() async {
    final session = _ref.read(authSessionProvider).context;
    if (session == null || session.needsClinicSetup) {
      return;
    }

    AppLog.info('setup.hydrate.start');

    final draft = await _orchestrator.hydrateDraftFromBackend();
    if (draft == null) {
      return;
    }

    final hydratedStaff = kDebugMode
        ? draft.staff
              .map((member) {
                final knownPassword = DevClinicSeedSpec.knownPasswordForDevSeedStaff(member.username);
                if (knownPassword == null) {
                  return member;
                }
                return member.copyWith(password: knownPassword);
              })
              .toList(growable: false)
        : draft.staff;

    final hydratedDraft = draft.copyWith(staff: hydratedStaff);

    state = state.copyWith(
      draft: hydratedDraft,
      confirmedBranchIds: confirmedBranchIdsForSetup(hydratedDraft.branches),
      confirmedStaffIds: confirmedStaffIdsForSetup(hydratedDraft.staff, hydratedDraft.branches.length),
      confirmedServiceIds: confirmedServiceIdsForSetup(hydratedDraft.services),
      clearSubmitError: true,
    );
    await persistDraft();
    AppLog.info('setup.hydrate.ok');
  }

  void revealBranchValidationErrors(Map<String, String> errors) {
    final branches = state.draft.branches;
    for (var index = 0; index < branches.length; index++) {
      final prefix = 'branch-$index-';
      final hasBranchError = errors.keys.any((key) => key.startsWith(prefix));
      if (!hasBranchError) {
        continue;
      }

      final branchId = branches[index].id;
      final nextConfirmed = {...state.confirmedBranchIds}..remove(branchId);
      state = state.copyWith(confirmedBranchIds: nextConfirmed, validationFocusEntityId: branchId);
      return;
    }
  }

  void clearValidationFocus() {
    if (state.validationFocusEntityId == null) {
      return;
    }
    state = state.copyWith(validationFocusEntityId: null);
  }

  void revealStaffValidationErrors(Map<String, String> errors) {
    final staff = state.draft.staff;
    for (var index = 0; index < staff.length; index++) {
      final prefix = 'staff-$index-';
      final hasStaffError = errors.keys.any((key) => key.startsWith(prefix));
      if (!hasStaffError) {
        continue;
      }

      final staffId = staff[index].id;
      final nextConfirmed = {...state.confirmedStaffIds}..remove(staffId);
      state = state.copyWith(confirmedStaffIds: nextConfirmed, validationFocusEntityId: staffId);
      return;
    }
  }

  void revealServiceValidationErrors(Map<String, String> errors) {
    final services = state.draft.services;
    for (var index = 0; index < services.length; index++) {
      final prefix = 'service-$index-';
      final hasServiceError = errors.keys.any((key) => key.startsWith(prefix));
      if (!hasServiceError) {
        continue;
      }

      final serviceId = services[index].id;
      final nextConfirmed = {...state.confirmedServiceIds}..remove(serviceId);
      state = state.copyWith(confirmedServiceIds: nextConfirmed, validationFocusEntityId: serviceId);
      return;
    }
  }

  static String _finishSetupMessageForRpc(RpcFailure failure) {
    return switch (failure.code) {
      'ORG_SETUP_INCOMPLETE' ||
      'FORBIDDEN' ||
      'USERNAME_EXISTS' ||
      'INVALID_BRANCH' ||
      'WEAK_PASSWORD' ||
      'RPC_NOT_APPLIED' => provisioningMessageForRpc(failure),
      _ => setupMessageForRpc(failure),
    };
  }
}