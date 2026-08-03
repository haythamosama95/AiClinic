import 'dart:convert';

import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import 'clinic_setup_notifier_support.dart';

void main() {
  group('ClinicSetupNotifier loadDraft and persistDraft', () {
    test('loads default draft from empty preferences', () async {
      final container = createClinicSetupContainer();
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      final state = container.read(clinicSetupProvider);
      expect(state.completed, isFalse);
      expect(state.completedSteps, isEmpty);
      expect(state.draft.organization.name, '');
      expect(state.draft.branches, hasLength(1));
      expect(state.draft.staff, hasLength(1));
      expect(state.draft.services, hasLength(1));
    });

    test('loads persisted draft, completion flag, and completed steps', () async {
      final draft = createDefaultSetup().copyWith(
        organization: const OrganizationDraft(name: 'Saved Clinic', timezone: 'Asia/Dubai', currency: 'AED'),
      );
      final container = createClinicSetupContainer(
        prefs: draftPrefsEntry(draft, completed: true, completedSteps: {0, 2}),
      );
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      final state = container.read(clinicSetupProvider);
      expect(state.completed, isTrue);
      expect(state.completedSteps, {0, 2});
      expect(state.draft.organization.name, 'Saved Clinic');
      expect(state.draft.organization.timezone, 'Asia/Dubai');
    });

    test('treats malformed draft JSON as default setup', () async {
      final container = createClinicSetupContainer(
        prefs: {setupDraftPrefsKey: 'not-valid-json'},
      );
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(clinicSetupProvider).draft.organization.name, '');
      expect(container.read(clinicSetupProvider.notifier).initialLoadDone, isTrue);
    });

    test('ignores malformed completed steps JSON', () async {
      final container = createClinicSetupContainer(
        prefs: {setupCompletedStepsPrefsKey: '{"bad": true}'},
      );
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(clinicSetupProvider).completedSteps, isEmpty);
    });

    test('marks completed when session reports setup is done', () async {
      final auth = MutableAuthSessionNotifier(steadyStateSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);

      await pumpDraftLoad(container);

      expect(container.read(clinicSetupProvider).completed, isTrue);
    });

    test('syncWithSession resets cached progress when bootstrap is required again', () async {
      final draft = createDefaultSetup().copyWith(
        organization: const OrganizationDraft(name: 'Stale', timezone: 'Africa/Cairo', currency: 'EGP'),
      );
      final auth = RefreshableAuthSessionNotifier(steadyStateSession());
      final container = createClinicSetupContainer(
        prefs: draftPrefsEntry(draft, completed: true, completedSteps: {0, 1}),
        auth: auth,
      );
      addTearDown(container.dispose);

      await pumpDraftLoad(container);
      expect(container.read(clinicSetupProvider).completed, isTrue);

      auth.replace(bootstrapAdminSession());
      await container.read(clinicSetupProvider.notifier).syncWithSession(auth.state.context);
      await flushMicrotasks();

      final state = container.read(clinicSetupProvider);
      expect(state.completed, isFalse);
      expect(state.step, 0);
      expect(state.completedSteps, isEmpty);
      expect(state.draft.organization.name, '');

      final prefs = await readAllSetupPrefs();
      expect(prefs.containsKey(setupCompletePrefsKey), isFalse);
      expect(prefs.containsKey(setupCompletedStepsPrefsKey), isFalse);
      expect(prefs.containsKey(setupDraftPrefsKey), isFalse);
    });

    test('syncWithSession no-ops when local progress is already cleared', () async {
      final auth = RefreshableAuthSessionNotifier(bootstrapAdminSession());
      final container = createClinicSetupContainer(auth: auth);
      addTearDown(container.dispose);

      await pumpDraftLoad(container);
      final before = container.read(clinicSetupProvider).draft;

      await container.read(clinicSetupProvider.notifier).syncWithSession(auth.state.context);

      expect(container.read(clinicSetupProvider).draft, before);
    });

    test('persistDraft roundtrips draft and completed steps to preferences', () async {
      final container = createClinicSetupContainer();
      addTearDown(container.dispose);

      await pumpDraftLoad(container);
      final notifier = container.read(clinicSetupProvider.notifier);

      notifier.updateOrganization(name: 'Persisted Org');
      notifier.markStepComplete(1);
      notifier.markStepComplete(3);
      await notifier.persistDraft();
      await flushMicrotasks();

      final prefs = await readAllSetupPrefs();
      final decoded = SetupDraft.fromJson(jsonDecode(prefs[setupDraftPrefsKey]! as String) as Map<String, dynamic>);
      expect(decoded.organization.name, 'Persisted Org');
      expect(jsonDecode(prefs[setupCompletedStepsPrefsKey]! as String), [1, 3]);
    });
  });
}
