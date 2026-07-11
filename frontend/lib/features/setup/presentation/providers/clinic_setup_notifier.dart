import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_surface_invalidation.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/usecases/settings_use_case_providers.dart';
import 'package:ai_clinic/features/setup/application/setup_rpc_messages.dart';
import 'package:ai_clinic/features/setup/domain/clinic_setup_draft_mapper.dart';
import 'package:ai_clinic/features/setup/domain/persist_clinic_setup_draft.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
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
    this.sessionNeedsClinicSetup,
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

  /// Cached from [AuthSessionContext.needsClinicSetup]; `null` until the first
  /// session read completes (e.g. during [ClinicSetupNotifier.loadDraft]).
  final bool? sessionNeedsClinicSetup;

  /// Whether the bootstrap / re-run setup wizard is actively in progress.
  ///
  /// Session `needsClinicSetup` is authoritative for first-run bootstrap.
  /// When the backend reports setup complete, the local `completed` flag drives
  /// steady-state "Run setup again" UX (mirrors [isSetupCompleteProvider]).
  bool get isBootstrapWizardInProgress {
    final needsSetup = sessionNeedsClinicSetup;
    if (needsSetup == true) {
      return true;
    }
    if (needsSetup == false) {
      return !completed;
    }
    return false;
  }

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
    Object? sessionNeedsClinicSetup = _sessionNeedsClinicSetupSentinel,
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
      sessionNeedsClinicSetup: identical(sessionNeedsClinicSetup, _sessionNeedsClinicSetupSentinel)
          ? this.sessionNeedsClinicSetup
          : sessionNeedsClinicSetup as bool?,
    );
  }
}

const _validationFocusSentinel = Object();
const _sessionNeedsClinicSetupSentinel = Object();

final clinicSetupProvider = StateNotifierProvider<ClinicSetupNotifier, ClinicSetupState>((ref) {
  final notifier = ClinicSetupNotifier(ref);
  ref.listen<AuthSessionState>(authSessionProvider, (previous, next) {
    if (!notifier._draftLoaded) {
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

/// Session-authoritative bootstrap wizard progress for routing guards.
///
/// Mirrors [ClinicSetupState.isBootstrapWizardInProgress] but is suitable for
/// `ref.watch` without reading notifier state in isolation.
final isBootstrapWizardInProgressProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).context;
  if (session != null && session.needsClinicSetup) {
    return true;
  }
  return !ref.watch(clinicSetupProvider).completed;
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
  bool _draftLoaded = false;

  /// Loads the persisted draft and completion flag from [SharedPreferences].
  Future<void> loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final session = _ref.read(authSessionProvider).context;

      final raw = prefs.getString(_setupDraftKey);
      var completed = prefs.getString(_setupCompleteKey) == 'true';
      final completedSteps = _readCompletedSteps(prefs.getString(_setupCompletedStepsKey));

      if (!completed && session != null && !session.needsClinicSetup) {
        completed = true;
      }

      final draft = raw == null || raw.isEmpty
          ? createDefaultSetup()
          : SetupDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);

      state = ClinicSetupState(
        draft: draft,
        completed: completed,
        completedSteps: completedSteps,
        sessionNeedsClinicSetup: session?.needsClinicSetup,
      );
      await syncWithSession(_ref.read(authSessionProvider).context);
    } on Object {
      state = ClinicSetupState(draft: createDefaultSetup());
    } finally {
      _draftLoaded = true;
    }
  }

  /// Aligns cached completion flags with the latest backend session (e.g. after clinic reset).
  Future<void> syncWithSession(AuthSessionContext? session) async {
    if (session == null) {
      if (state.sessionNeedsClinicSetup != null) {
        state = state.copyWith(sessionNeedsClinicSetup: null);
      }
      return;
    }

    if (state.sessionNeedsClinicSetup != session.needsClinicSetup) {
      state = state.copyWith(sessionNeedsClinicSetup: session.needsClinicSetup);
    }

    if (!session.needsClinicSetup) {
      return;
    }

    if (!state.completed && state.completedSteps.isEmpty) {
      return;
    }

    state = ClinicSetupState(
      draft: createDefaultSetup(),
      step: 0,
      completed: false,
      sessionNeedsClinicSetup: session.needsClinicSetup,
    );
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
  /// `bootstrap_finish_setup` RPC. In steady-state mode, persists changes via
  /// individual CRUD operations (`persistSetupDraftToBackend`).
  Future<bool> completeSetup() async {
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
        await _ref.read(finishBootstrapSetupUseCaseProvider)(input);
        await _ref.read(authSessionProvider.notifier).refreshSessionContext();
        final refreshedSession = _ref.read(authSessionProvider).context;
        await hydrateFromBackend();
        invalidateAppointmentSurfaceProviders(_ref);
        AppLog.info('setup.finish.ok');

        state = state.copyWith(
          completed: true,
          isSubmitting: false,
          completedSteps: {0, 1, 2, 3},
          sessionNeedsClinicSetup: refreshedSession?.needsClinicSetup ?? false,
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
      final existingBranches = await _ref
          .read(listBranchesUseCaseProvider)(organizationId: organizationId)
          .catchError((_) => const <BranchListItem>[]);
      final existingStaff = await _loadStaffForSetup();
      final existingServices = await _loadServicesForSetup();
      final serviceRepo = _ref.read(serviceCatalogRepositoryProvider);

      await persistSetupDraftToBackend(
        draft: state.draft,
        existingBranches: existingBranches,
        existingStaff: existingStaff,
        existingServices: existingServices,
        gateways: PersistSetupDraftGateways(
          updateOrganization: (input) => _ref.read(updateOrganizationUseCaseProvider)(input),
          createBranch: (input) => _ref.read(createBranchUseCaseProvider)(input),
          updateBranch: (input) => _ref.read(updateBranchUseCaseProvider)(input),
          deleteBranch: ({required String branchId}) => _ref.read(deleteBranchUseCaseProvider)(branchId: branchId),
          createStaffAccount: (input) => _ref.read(createStaffAccountUseCaseProvider)(input),
          updateStaffMember: (input) => _ref.read(updateStaffMemberUseCaseProvider)(input),
          deleteStaffMember: ({required String staffMemberId}) =>
              _ref.read(deleteStaffMemberUseCaseProvider)(staffMemberId: staffMemberId),
          createService: ({required String name, required String defaultPrice}) async {
            final result = await serviceRepo.createService(
              name: name,
              defaultPrice: defaultPrice,
              globalStatus: GlobalStatus.active,
              assignAllBranches: true,
            );
            return result.serviceId;
          },
          updateService:
              ({
                required String serviceId,
                required DateTime expectedUpdatedAt,
                required String name,
                required String defaultPrice,
              }) async {
                await serviceRepo.updateService(
                  serviceId: serviceId,
                  expectedUpdatedAt: expectedUpdatedAt,
                  name: name,
                  defaultPrice: defaultPrice,
                  globalStatus: GlobalStatus.active,
                );
              },
          softDeleteService: ({required String serviceId, required DateTime expectedUpdatedAt}) async {
            await serviceRepo.softDeleteService(serviceId: serviceId, expectedUpdatedAt: expectedUpdatedAt);
          },
        ),
      );

      await hydrateFromBackend();
      invalidateAppointmentSurfaceProviders(_ref);
      AppLog.info('setup.finish.steady_state.ok');

      state = state.copyWith(
        completed: true,
        isSubmitting: false,
        completedSteps: {0, 1, 2, 3},
        sessionNeedsClinicSetup: session?.needsClinicSetup ?? false,
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
      AppLog.warning('setup.finish.steady_state.rpc_failed code=${error.code}');
      await hydrateFromBackend();
      state = state.copyWith(isSubmitting: false, submitError: setupMessageForRpc(error));
      return false;
    } on StateError catch (error) {
      await hydrateFromBackend();
      state = state.copyWith(isSubmitting: false, submitError: error.message);
      return false;
    } catch (error) {
      AppLog.warning('setup.finish.steady_state.failed reason=${error.runtimeType}');
      await hydrateFromBackend();
      state = state.copyWith(
        isSubmitting: false,
        submitError: 'Unable to save clinic setup. Check connectivity and try again.',
      );
      return false;
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
    assert(kDebugMode, 'resetInstallationForDevelopment is debug-only');
    if (!kDebugMode) {
      return false;
    }
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
      final refreshedSession = _ref.read(authSessionProvider).context;
      AppLog.info(
        'setup.dev_reset.session_refreshed setup_required=${refreshedSession?.setupRequired}',
      );

      invalidateAppointmentSurfaceProviders(_ref);
      await resetSetup();
      state = state.copyWith(
        isSubmitting: false,
        sessionNeedsClinicSetup: refreshedSession?.needsClinicSetup,
      );
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
  /// no organization exists yet.
  Future<void> hydrateFromBackend() async {
    final session = _ref.read(authSessionProvider).context;
    final organizationId = session?.organizationId?.trim();
    if (organizationId == null || organizationId.isEmpty || (session?.needsClinicSetup ?? false)) {
      return;
    }

    AppLog.info('setup.hydrate.start');

    // Single fetch path for org/branches — shared with shell chrome and settings.
    _ref.invalidate(clinicSetupOrganizationProvider);
    _ref.invalidate(clinicSetupBranchesProvider);
    final organization = await _ref.read(clinicSetupOrganizationProvider.future).catchError((_) => null);
    final branches = await _ref.read(clinicSetupBranchesProvider.future).catchError((_) => const <BranchListItem>[]);
    final staff = await _loadStaffForSetup();
    final services = await _loadServicesForSetup();

    final draft = setupDraftFromBackend(
      organization: organization,
      branches: branches,
      staff: staff,
      services: services,
    );

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

  Future<List<StaffListItem>> _loadStaffForSetup() async {
    final auth = _ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return const [];
    }

    return _ref.read(listStaffUseCaseProvider)(filter: StaffListFilter.all).catchError((_) => const <StaffListItem>[]);
  }

  Future<List<ServiceListItem>> _loadServicesForSetup() async {
    final auth = _ref.read(authSessionProvider);
    if (!AuthRouteGuard.canAccessServiceCatalogList(auth)) {
      return const [];
    }

    const pageSize = 100;
    var offset = 0;
    final all = <ServiceListItem>[];

    while (true) {
      final page = await _ref
          .read(serviceCatalogRepositoryProvider)
          .listServices(limit: pageSize, offset: offset)
          .catchError((_) => const ServiceListPageResult(items: [], total: 0));

      all.addAll(page.items);
      if (page.items.isEmpty || all.length >= page.total) {
        break;
      }
      offset += pageSize;
    }

    return all;
  }
}