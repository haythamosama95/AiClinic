import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clinic_setup_notifier_support.dart';

void main() {
  group('ClinicSetupNotifier draft mutations', () {
    late ProviderContainer container;
    late ClinicSetupNotifier notifier;

    setUp(() async {
      container = createClinicSetupContainer();
      await pumpDraftLoad(container);
      notifier = container.read(clinicSetupProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('setStep clamps negative values to zero and clears submit error', () async {
      notifier.state = notifier.state.copyWith(submitError: 'old error');
      notifier.setStep(-3);
      await flushMicrotasks();

      expect(container.read(clinicSetupProvider).step, 0);
      expect(container.read(clinicSetupProvider).submitError, isNull);
    });

    test('markStepComplete ignores negative steps', () {
      notifier.markStepComplete(-1);
      expect(container.read(clinicSetupProvider).completedSteps, isEmpty);
    });

    test('markStepComplete records completed steps', () async {
      notifier.markStepComplete(2);
      await flushMicrotasks();
      expect(container.read(clinicSetupProvider).completedSteps, {2});
    });

    test('updateOrganization updates organization fields', () {
      notifier.updateOrganization(name: 'Clinic A', timezone: 'Europe/London', currency: 'GBP');
      final org = container.read(clinicSetupProvider).draft.organization;
      expect(org.name, 'Clinic A');
      expect(org.timezone, 'Europe/London');
      expect(org.currency, 'GBP');
    });

    group('branches', () {
      test('add, update, confirm, unconfirm, and remove branch', () {
        final initialId = container.read(clinicSetupProvider).draft.branches.single.id;
        final added = notifier.addBranch();
        expect(container.read(clinicSetupProvider).draft.branches, hasLength(2));

        notifier.updateBranch(added.id, name: 'Branch B', code: 'B01', mobile: '201000000001');
        final updated = container.read(clinicSetupProvider).draft.branches.last;
        expect(updated.name, 'Branch B');
        expect(updated.code, 'B01');

        notifier.confirmBranch(added.id);
        expect(container.read(clinicSetupProvider).confirmedBranchIds, contains(added.id));

        notifier.unconfirmBranch(added.id);
        expect(container.read(clinicSetupProvider).confirmedBranchIds, isNot(contains(added.id)));

        notifier.removeBranch(added.id);
        expect(container.read(clinicSetupProvider).draft.branches, hasLength(1));
        expect(container.read(clinicSetupProvider).draft.branches.single.id, initialId);
        expect(container.read(clinicSetupProvider).confirmedBranchIds, isNot(contains(added.id)));
      });
    });

    group('staff', () {
      test('add, update, confirm, unconfirm, and remove staff', () {
        final initialId = container.read(clinicSetupProvider).draft.staff.single.id;
        final added = notifier.addStaff();
        expect(container.read(clinicSetupProvider).draft.staff, hasLength(2));

        notifier.updateStaff(
          added.id,
          name: 'Alice',
          mobile: '201000000002',
          username: 'alice',
          password: 'Secret123',
          role: 'doctor',
          branchIds: const ['branch-1'],
        );
        final updated = container.read(clinicSetupProvider).draft.staff.last;
        expect(updated.name, 'Alice');
        expect(updated.username, 'alice');
        expect(updated.branchIds, ['branch-1']);

        notifier.confirmStaff(added.id);
        expect(container.read(clinicSetupProvider).confirmedStaffIds, contains(added.id));

        notifier.unconfirmStaff(added.id);
        expect(container.read(clinicSetupProvider).confirmedStaffIds, isNot(contains(added.id)));

        notifier.removeStaff(added.id);
        expect(container.read(clinicSetupProvider).draft.staff, hasLength(1));
        expect(container.read(clinicSetupProvider).draft.staff.single.id, initialId);
      });
    });

    group('services', () {
      test('add, update, confirm, unconfirm, and remove service', () {
        final initialId = container.read(clinicSetupProvider).draft.services.single.id;
        final added = notifier.addService();
        expect(container.read(clinicSetupProvider).draft.services, hasLength(2));

        notifier.updateService(added.id, name: 'Consultation', price: 250);
        var updated = container.read(clinicSetupProvider).draft.services.last;
        expect(updated.name, 'Consultation');
        expect(updated.price, 250);

        notifier.updateService(added.id, clearPrice: true);
        updated = container.read(clinicSetupProvider).draft.services.last;
        expect(updated.price, isNull);

        notifier.confirmService(added.id);
        expect(container.read(clinicSetupProvider).confirmedServiceIds, contains(added.id));

        notifier.unconfirmService(added.id);
        expect(container.read(clinicSetupProvider).confirmedServiceIds, isNot(contains(added.id)));

        notifier.removeService(added.id);
        expect(container.read(clinicSetupProvider).draft.services, hasLength(1));
        expect(container.read(clinicSetupProvider).draft.services.single.id, initialId);
      });
    });

    test('resetSetup clears wizard state and persisted completion flags', () async {
      notifier.updateOrganization(name: 'Before Reset');
      notifier.markStepComplete(1);
      notifier.confirmBranch(container.read(clinicSetupProvider).draft.branches.single.id);
      notifier.state = notifier.state.copyWith(completed: true, step: 2);

      await notifier.resetSetup();

      final state = container.read(clinicSetupProvider);
      expect(state.completed, isFalse);
      expect(state.step, 0);
      expect(state.completedSteps, isEmpty);
      expect(state.confirmedBranchIds, isEmpty);
      expect(state.confirmedStaffIds, isEmpty);
      expect(state.confirmedServiceIds, isEmpty);
      expect(state.draft.organization.name, isEmpty);
    });
  });
}
