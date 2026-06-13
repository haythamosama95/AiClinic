import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_result.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:async';

void main() {
  group('setupMessageForRpc', () {
    test('maps known setup error codes', () {
      expect(
        setupMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'ORG_ALREADY_EXISTS'}))),
        contains('already exists'),
      );

      expect(
        setupMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'NOT_BOOTSTRAP_ADMIN'}))),
        contains('bootstrap administrator'),
      );
    });

    test('falls back for unknown codes', () {
      expect(
        setupMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'UNKNOWN'}))),
        contains('Unable to save'),
      );
    });

    test('maps RESET_SAFE_DELETE to migration hint', () {
      expect(
        setupMessageForRpc(
          RpcFailure(
            RpcResult.fromDynamic({
              'success': false,
              'error_code': 'RESET_SAFE_DELETE',
              'error_message': 'Apply migration 20260521150000.',
            }),
          ),
        ),
        contains('20260521150000'),
      );
    });
  });

  group('SetupNotifier', () {
    test('continueToBranchStep stores draft without organizationId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.branch);
      expect(state.organizationId, isNull);
      expect(state.organizationDraft?.name, 'Sunrise Clinic');
    });

    test('continueToBranchStep rejects invalid currency', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'NOTREAL', timezone: 'Africa/Cairo');

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.organization);
    });

    test('continueToBranchStep rejects invalid timezone', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Invalid/Zone');

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).errorMessage, contains('timezone from the list'));
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.organization);
    });

    test('goBackToOrganizationStep clears branch and staff drafts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      notifier.goBackToOrganizationStep();

      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.organization);
      expect(state.organizationDraft?.name, 'Clinic');
      expect(state.branchDraft, isNull);
      expect(state.staffDrafts, isEmpty);
    });

    test('goBackToBranchStep clears staff drafts only', () {
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true, branchIds: const ['branch-local']),
        ),
      );
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );
      notifier.addStaffDraft(
        username: 'frontdesk',
        fullName: 'Front Desk',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      notifier.goBackToBranchStep();

      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.branch);
      expect(state.branchDraft?.name, 'Main');
      expect(state.staffDrafts, isEmpty);
    });

    test('goBackToBranchStep is no-op when not on staff step', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.goBackToBranchStep();

      expect(container.read(setupNotifierProvider).step, SetupWizardStep.branch);
    });

    test('continueToStaffStep stores branch draft without organizationId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      final ok = notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '+20 100 000 0000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.staff);
      expect(state.organizationId, isNull);
      expect(state.branchId, isNull);
      expect(state.branchDraft?.name, 'Main');
    });

    test('addStaffDraft stores staff locally without RPC', () {
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: AuthSessionContext(
            staffProfile: const StaffProfile(
              staffMemberId: '00000000-0000-4000-8000-000000000010',
              fullName: 'Bootstrap Admin',
              role: StaffRole.administrator,
              isBootstrapAdmin: true,
              isActive: true,
            ),
            organizationId: null,
            branchIds: const [],
            activeBranchId: null,
            permissions: const {},
            setupRequired: true,
          ),
        ),
      );
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '+20 100 000 0000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      final ok = notifier.addStaffDraft(
        username: 'owner1',
        fullName: 'Owner One',
        role: StaffRole.administrator,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      expect(ok, isTrue);
      expect(container.read(setupNotifierProvider).staffDrafts, hasLength(1));
      expect(container.read(setupNotifierProvider).staffDrafts.first.username, 'owner1');
    });

    test('addStaffDraft rejects duplicate username in draft list', () {
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true, branchIds: const ['branch-local']),
        ),
      );
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );
      notifier.addStaffDraft(
        username: 'frontdesk',
        fullName: 'Front Desk',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      final duplicate = notifier.addStaffDraft(
        username: 'FrontDesk',
        fullName: 'Duplicate',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      expect(duplicate, isFalse);
      expect(container.read(setupNotifierProvider).staffDrafts, hasLength(1));
      expect(container.read(setupNotifierProvider).errorMessage, contains('already in the setup list'));
    });

    test('finishSetup rejects empty staff drafts', () async {
      final bootstrapRepo = _RecordingBootstrapRepository();
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWithValue(bootstrapRepo),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      final ok = await notifier.finishSetup();

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).errorMessage, contains('at least one staff'));
      expect(bootstrapRepo.finishSetupInput, isNull);
    });

    test('resetInstallationForDevelopment clears wizard after successful RPC', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith((ref) => _FakeBootstrapRepository()),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      final ok = await notifier.resetInstallationForDevelopment();

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.organization);
      expect(state.organizationDraft, isNull);
      expect(state.isSubmitting, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('resetInstallationForDevelopment surfaces RESET_SAFE_DELETE without connectivity fallback', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith(
            (ref) => _FakeBootstrapRepository(
              resetResult: RpcFailure(
                RpcResult.fromDynamic({
                  'success': false,
                  'error_code': 'RESET_SAFE_DELETE',
                  'error_message': 'Apply migration 20260521150000.',
                }),
              ),
            ),
          ),
          authSessionProvider.overrideWith(_CountingAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container.read(setupNotifierProvider.notifier).resetInstallationForDevelopment();

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).errorMessage, contains('20260521150000'));
    });

    test('starts on organization step', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.organization);
    });

    test('continueToStaffStep without org draft redirects to organization', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.organization);
      expect(container.read(setupNotifierProvider).errorMessage, contains('organization'));
    });

    test('advancing org step clears downstream drafts', () {
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(setupRequired: true, branchIds: const ['branch-local']),
        ),
      );
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Clinic A', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );
      notifier.addStaffDraft(
        username: 'staff1',
        fullName: 'Staff One',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      notifier.goBackToOrganizationStep();
      notifier.continueToBranchStep(name: 'Clinic B', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      final state = container.read(setupNotifierProvider);
      expect(state.organizationDraft?.name, 'Clinic B');
      expect(state.branchDraft, isNull);
      expect(state.staffDrafts, isEmpty);
    });

    test('addStaffDraft rejects empty full name', () {
      final container = _staffDraftContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);

      expect(
        notifier.addStaffDraft(
          username: 'staff1',
          fullName: '   ',
          role: StaffRole.receptionist,
          branchIds: const ['branch-local'],
          password: 'Secret12',
        ),
        isFalse,
      );
    });

    test('addStaffDraft rejects invalid password', () {
      final container = _staffDraftContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);

      expect(
        notifier.addStaffDraft(
          username: 'staff1',
          fullName: 'Staff One',
          role: StaffRole.receptionist,
          branchIds: const ['branch-local'],
          password: '12345678',
        ),
        isFalse,
      );
    });

    test('addStaffDraft rejects empty branchIds', () {
      final container = _staffDraftContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);

      expect(
        notifier.addStaffDraft(
          username: 'staff1',
          fullName: 'Staff One',
          role: StaffRole.receptionist,
          branchIds: const [],
          password: 'Secret12',
        ),
        isFalse,
      );
    });

    test('addStaffDraft rejects role when doctor cannot provision', () {
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            setupRequired: true,
            role: StaffRole.doctor,
            branchIds: const ['branch-local'],
          ),
        ),
      );
      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      expect(
        notifier.addStaffDraft(
          username: 'staff1',
          fullName: 'Staff One',
          role: StaffRole.receptionist,
          branchIds: const ['branch-local'],
          password: 'Secret12',
        ),
        isFalse,
      );
    });

    test('addStaffDraft normalizes username', () {
      final container = _staffDraftContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);

      notifier.addStaffDraft(
        username: 'FrontDesk',
        fullName: 'Staff One',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      expect(container.read(setupNotifierProvider).staffDrafts.first.username, 'frontdesk');
    });

    test('addStaffDraft without session shows sign-in error', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      expect(
        notifier.addStaffDraft(
          username: 'staff1',
          fullName: 'Staff One',
          role: StaffRole.receptionist,
          branchIds: const ['branch-local'],
          password: 'Secret12',
        ),
        isFalse,
      );
      expect(container.read(setupNotifierProvider).errorMessage, contains('Sign in'));
    });

    test('addStaffDraft without branch draft returns to branch step', () {
      final container = _staffDraftContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPathWithContainer(container);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.goBackToOrganizationStep();

      expect(
        notifier.addStaffDraft(
          username: 'staff1',
          fullName: 'Staff One',
          role: StaffRole.receptionist,
          branchIds: const ['branch-local'],
          password: 'Secret12',
        ),
        isFalse,
      );
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.branch);
    });

    test('finishSetup rejects missing org draft', () async {
      final container = ProviderContainer(
        overrides: [bootstrapRepositoryProvider.overrideWithValue(_RecordingBootstrapRepository())],
      );
      addTearDown(container.dispose);

      final ok = await container.read(setupNotifierProvider.notifier).finishSetup();

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.organization);
    });

    test('finishSetup rejects missing branch draft', () async {
      final container = ProviderContainer(
        overrides: [bootstrapRepositoryProvider.overrideWithValue(_RecordingBootstrapRepository())],
      );
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      final ok = await notifier.finishSetup();
      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.branch);
    });

    test('finishSetup refreshes session and clears drafts on success', () async {
      final bootstrapRepo = _RecordingBootstrapRepository();
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWithValue(bootstrapRepo),
          authSessionProvider.overrideWith(_CountingAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);
      notifier.addStaffDraft(
        username: 'staff1',
        fullName: 'Staff One',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      final ok = await notifier.finishSetup();

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.complete);
      expect(state.organizationId, 'org-dummy');
      expect(state.branchId, 'branch-dummy');
      expect(state.staffDrafts, isEmpty);
      expect(state.organizationDraft, isNull);
      expect(state.branchDraft, isNull);
      expect(
        (container.read(authSessionProvider.notifier) as _CountingAuthSessionNotifier).refreshSessionContextCount,
        1,
      );
    });

    test('multiple staff drafts all submitted on Finish', () async {
      final bootstrapRepo = _RecordingBootstrapRepository();
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWithValue(bootstrapRepo),
          authSessionProvider.overrideWith(_CountingAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);
      for (final username in ['staff1', 'staff2', 'staff3']) {
        notifier.addStaffDraft(
          username: username,
          fullName: 'Staff $username',
          role: StaffRole.receptionist,
          branchIds: const ['branch-local'],
          password: 'Secret12',
        );
      }

      await notifier.finishSetup();

      expect(bootstrapRepo.finishSetupInput?.staffAccounts, hasLength(3));
    });

    test('finishSetup surfaces connectivity message on unexpected failure', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWithValue(_ThrowingFinishBootstrapRepository()),
          authSessionProvider.overrideWith(_CountingAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);
      notifier.addStaffDraft(
        username: 'staff1',
        fullName: 'Staff One',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      final ok = await notifier.finishSetup();

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).errorMessage, contains('connectivity'));
    });

    test('continueToBranchStep accepts unicode organization name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'عيادة الشروق', currencyCode: 'egp', timezone: 'africa/cairo');

      expect(ok, isTrue);
      expect(container.read(setupNotifierProvider).organizationDraft?.name, 'عيادة الشروق');
      expect(container.read(setupNotifierProvider).organizationDraft?.currencyCode, 'EGP');
    });

    test('continueToStaffStep preserves mixed-case branch code', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MaIn',
        address: '123 Street',
        phone: '201000000000',
        mapsUrl: 'https://maps.example.com/main',
        workingSchedule: BranchWorkingSchedule.defaultSchedule(),
      );

      expect(container.read(setupNotifierProvider).branchDraft?.code, 'MaIn');
    });

    test('finishSetup sets isSubmitting while RPC is in flight', () async {
      final completer = Completer<BootstrapFinishSetupResult>();
      final bootstrapRepo = _DeferredFinishBootstrapRepository(completer);
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWithValue(bootstrapRepo),
          authSessionProvider.overrideWith(_CountingAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);
      _prepareStaffDraftPath(container, notifier);
      notifier.addStaffDraft(
        username: 'staff1',
        fullName: 'Staff One',
        role: StaffRole.receptionist,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      final future = notifier.finishSetup();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(setupNotifierProvider).isSubmitting, isTrue);

      completer.complete(
        const BootstrapFinishSetupResult(
          organizationId: 'org-dummy',
          branchId: 'branch-dummy',
          staffMemberIds: ['staff-dummy'],
        ),
      );
      await future;

      expect(container.read(setupNotifierProvider).isSubmitting, isFalse);
      expect(bootstrapRepo.finishSetupCallCount, 1);
    });

    test('resetInstallationForDevelopment refreshes session on success', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith((ref) => _FakeBootstrapRepository()),
          authSessionProvider.overrideWith(_CountingAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await container.read(setupNotifierProvider.notifier).resetInstallationForDevelopment();

      expect(
        (container.read(authSessionProvider.notifier) as _CountingAuthSessionNotifier).refreshSessionContextCount,
        1,
      );
    });
  });
}

ProviderContainer _staffDraftContainer() {
  return ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
}

void _prepareStaffDraftPathWithContainer(ProviderContainer container) {
  (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
    AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(setupRequired: true, branchIds: const ['branch-local']),
    ),
  );
}

void _prepareStaffDraftPath(ProviderContainer container, SetupNotifier notifier) {
  _prepareStaffDraftPathWithContainer(container);
  notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
  notifier.continueToStaffStep(
    branchName: 'Main',
    branchCode: 'MAIN',
    address: '123 Street',
    phone: '201000000000',
    mapsUrl: 'https://maps.example.com/main',
    workingSchedule: BranchWorkingSchedule.defaultSchedule(),
  );
}

class _CountingAuthSessionNotifier extends TestAuthSessionNotifier {
  var refreshSessionContextCount = 0;

  @override
  Future<void> refreshSessionContext() async {
    refreshSessionContextCount++;
  }
}

class _ThrowingFinishBootstrapRepository extends BootstrapRepositoryImpl {
  _ThrowingFinishBootstrapRepository() : super(_ThrowingSupabaseClient());

  @override
  Future<BootstrapFinishSetupResult> finishSetup(BootstrapFinishSetupInput input) async {
    throw Exception('network down');
  }
}

class _RecordingBootstrapRepository extends BootstrapRepositoryImpl {
  _RecordingBootstrapRepository() : super(_ThrowingSupabaseClient());

  BootstrapFinishSetupInput? finishSetupInput;
  var finishSetupCallCount = 0;

  @override
  Future<BootstrapFinishSetupResult> finishSetup(BootstrapFinishSetupInput input) async {
    finishSetupCallCount++;
    finishSetupInput = input;
    return const BootstrapFinishSetupResult(
      organizationId: 'org-dummy',
      branchId: 'branch-dummy',
      staffMemberIds: ['staff-dummy'],
    );
  }
}

class _DeferredFinishBootstrapRepository extends BootstrapRepositoryImpl {
  _DeferredFinishBootstrapRepository(this._completer) : super(_ThrowingSupabaseClient());

  final Completer<BootstrapFinishSetupResult> _completer;
  var finishSetupCallCount = 0;

  @override
  Future<BootstrapFinishSetupResult> finishSetup(BootstrapFinishSetupInput input) async {
    finishSetupCallCount++;
    return _completer.future;
  }
}

class _FakeBootstrapRepository extends BootstrapRepositoryImpl {
  _FakeBootstrapRepository({this.resetResult}) : super(_ThrowingSupabaseClient());

  final Object? resetResult;

  @override
  Future<RpcResult> resetInstallationForDevelopment() async {
    final result = resetResult;
    if (result is RpcFailure) {
      throw result;
    }
    return const RpcResult(
      success: true,
      data: {'organizations_deleted': 1, 'branches_deleted': 1, 'had_organization_before_reset': true},
    );
  }
}

class _ThrowingSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
