import 'dart:convert';

import 'package:ai_clinic/app/application/clinic_setup_orchestrator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_result.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_branch_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_organization_input.dart';
import 'package:ai_clinic/features/setup/domain/repositories/bootstrap_repository.dart';
import 'package:ai_clinic/features/setup/domain/usecases/finish_bootstrap_setup.dart';
import 'package:ai_clinic/features/setup/domain/usecases/reset_installation.dart';
import 'package:ai_clinic/features/setup/domain/usecases/setup_use_case_providers.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_test_support.dart';

const setupDraftPrefsKey = 'aiclinic:setup-draft';
const setupCompletePrefsKey = 'aiclinic:setup-complete';
const setupCompletedStepsPrefsKey = 'aiclinic:setup-completed-steps';

Future<void> pumpDraftLoad(ProviderContainer container) async {
  container.read(clinicSetupProvider);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> flushMicrotasks([int rounds = 3]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Object> draftPrefsEntry(SetupDraft draft, {bool completed = false, Set<int> completedSteps = const {}}) {
  return {
    setupDraftPrefsKey: jsonEncode(draft.toJson()),
    if (completed) setupCompletePrefsKey: 'true',
    if (completedSteps.isNotEmpty) setupCompletedStepsPrefsKey: jsonEncode(completedSteps.toList()..sort()),
  };
}

class RefreshableAuthSessionNotifier extends MutableAuthSessionNotifier {
  RefreshableAuthSessionNotifier(super.initial, {this.refreshToSteadyState = false});

  var refreshSessionContextCalls = 0;

  /// When true, simulates the JWT refresh that clears `needsClinicSetup` after bootstrap.
  final bool refreshToSteadyState;

  @override
  Future<void> refreshSessionContext() async {
    refreshSessionContextCalls++;
    if (refreshToSteadyState) {
      replace(steadyStateSession());
    }
  }
}

class FakeClinicSetupOrchestrator extends ClinicSetupOrchestrator {
  FakeClinicSetupOrchestrator(super.ref);

  var persistSteadyStateCalls = 0;
  var persistRemainingBootstrapEntitiesCalls = 0;
  var hydrateDraftFromBackendCalls = 0;
  var notifyClinicDataChangedCalls = 0;

  SetupDraft? hydrateResult;
  Object? persistSteadyStateError;
  Object? persistRemainingError;

  @override
  Future<void> persistSteadyState(SetupDraft draft) async {
    persistSteadyStateCalls++;
    if (persistSteadyStateError != null) {
      throw persistSteadyStateError!;
    }
  }

  @override
  Future<void> persistRemainingBootstrapEntities({
    required String primaryBranchId,
    required List<String> staffMemberIds,
    required SetupDraft draft,
  }) async {
    persistRemainingBootstrapEntitiesCalls++;
    if (persistRemainingError != null) {
      throw persistRemainingError!;
    }
  }

  @override
  Future<SetupDraft?> hydrateDraftFromBackend() async {
    hydrateDraftFromBackendCalls++;
    return hydrateResult;
  }

  @override
  void notifyClinicDataChanged() {
    notifyClinicDataChangedCalls++;
  }
}

class FakeBootstrapRepository implements BootstrapRepository {
  FakeBootstrapRepository({
    Future<BootstrapFinishSetupResult> Function(BootstrapFinishSetupInput input)? onFinishSetup,
    Future<RpcResult> Function()? onResetInstallation,
  })  : _onFinishSetup = onFinishSetup,
        _onResetInstallation = onResetInstallation;

  final Future<BootstrapFinishSetupResult> Function(BootstrapFinishSetupInput input)? _onFinishSetup;
  final Future<RpcResult> Function()? _onResetInstallation;

  BootstrapFinishSetupInput? lastFinishSetupInput;

  @override
  Future<String> createOrganization(BootstrapOrganizationInput input) {
    throw UnimplementedError();
  }

  @override
  Future<String> createBranch(BootstrapBranchInput input) {
    throw UnimplementedError();
  }

  @override
  Future<BootstrapFinishSetupResult> finishSetup(BootstrapFinishSetupInput input) {
    lastFinishSetupInput = input;
    if (_onFinishSetup == null) {
      throw StateError('finishSetup not stubbed');
    }
    return _onFinishSetup!(input);
  }

  @override
  Future<RpcResult> resetInstallationForDevelopment() {
    if (_onResetInstallation == null) {
      throw StateError('resetInstallation not stubbed');
    }
    return _onResetInstallation!();
  }
}

RpcFailure rpcFailure(String code, {String? message}) {
  return RpcFailure(RpcResult(success: false, errorCode: code, errorMessage: message ?? 'Test failure'));
}

ProviderContainer createClinicSetupContainer({
  Map<String, Object> prefs = const {},
  AuthSessionNotifier? auth,
  FakeBootstrapRepository? bootstrapRepository,
}) {
  SharedPreferences.setMockInitialValues(prefs);
  final authNotifier = auth ?? MutableAuthSessionNotifier(const AuthSessionState(status: AuthSessionStatus.unknown));

  return ProviderContainer(
    overrides: [
      authSessionProvider.overrideWith(() => authNotifier),
      clinicSetupOrchestratorProvider.overrideWith((ref) => FakeClinicSetupOrchestrator(ref)),
      if (bootstrapRepository != null) ...[
        finishBootstrapSetupUseCaseProvider.overrideWith((ref) => FinishBootstrapSetup(bootstrapRepository)),
        resetInstallationUseCaseProvider.overrideWith((ref) => ResetInstallation(bootstrapRepository)),
      ],
    ],
  );
}

FakeClinicSetupOrchestrator readFakeOrchestrator(ProviderContainer container) {
  return container.read(clinicSetupOrchestratorProvider) as FakeClinicSetupOrchestrator;
}

AuthSessionState bootstrapAdminSession({bool setupRequired = true}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      setupRequired: setupRequired,
      isBootstrapAdmin: true,
      role: StaffRole.administrator,
    ),
  );
}

AuthSessionState steadyStateSession() {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(setupRequired: false),
  );
}

AuthSessionState nonBootstrapStaffSession() {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      setupRequired: true,
      isBootstrapAdmin: false,
      role: StaffRole.receptionist,
    ),
  );
}

BootstrapFinishSetupResult defaultBootstrapResult() {
  return const BootstrapFinishSetupResult(
    organizationId: '00000000-0000-4000-8000-000000000099',
    branchId: '00000000-0000-4000-8000-0000000000aa',
    staffMemberIds: ['00000000-0000-4000-8000-0000000000bb'],
  );
}

/// Fills the default wizard draft with values that pass bootstrap validation.
void seedValidBootstrapDraft(ClinicSetupNotifier notifier) {
  final branchId = notifier.state.draft.branches.first.id;
  notifier.updateOrganization(name: 'New Clinic', timezone: 'Africa/Cairo', currency: 'EGP');
  notifier.updateBranch(
    branchId,
    name: 'Main Branch',
    code: 'MAIN',
    mobile: '2010000000',
    mapLocation: 'https://maps.example.com',
  );
  final staffId = notifier.state.draft.staff.first.id;
  notifier.updateStaff(
    staffId,
    name: 'Admin User',
    mobile: '2010000001',
    username: 'admin',
    password: 'Secret123',
    role: 'administrator',
    branchIds: [branchId],
  );
}

SetupDraft sampleHydratedDraft() {
  final branch = BranchDraft(
    id: '00000000-0000-4000-8000-0000000000cc',
    name: 'Main',
    code: 'MAIN',
    mobile: '2010000000',
    mapLocation: 'https://maps.example.com',
    workingDays: createDefaultWorkingDays(),
    isDraft: false,
  );
  final staff = StaffDraft(
    id: '00000000-0000-4000-8000-0000000000dd',
    name: 'Admin',
    mobile: '2010000001',
    username: 'admin',
    password: 'Secret123',
    role: 'administrator',
    branchIds: [branch.id],
    isDraft: false,
  );
  final service = ServiceDraft(
    id: '00000000-0000-4000-8000-0000000000ee',
    name: 'Consultation',
    price: 100,
    isDraft: false,
  );
  return SetupDraft(
    organization: const OrganizationDraft(name: 'Test Clinic', timezone: 'Africa/Cairo', currency: 'EGP'),
    branches: [branch],
    staff: [staff],
    services: [service],
  );
}

Future<Map<String, Object>> readAllSetupPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    if (prefs.containsKey(setupDraftPrefsKey)) setupDraftPrefsKey: prefs.getString(setupDraftPrefsKey)!,
    if (prefs.containsKey(setupCompletePrefsKey)) setupCompletePrefsKey: prefs.getString(setupCompletePrefsKey)!,
    if (prefs.containsKey(setupCompletedStepsPrefsKey))
      setupCompletedStepsPrefsKey: prefs.getString(setupCompletedStepsPrefsKey)!,
  };
}
