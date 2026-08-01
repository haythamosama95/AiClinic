import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clinic_setup_notifier_support.dart';

void main() {
  group('ClinicSetupNotifier validation focus', () {
    late ProviderContainer container;
    late ClinicSetupNotifier notifier;

    setUp(() async {
      container = createClinicSetupContainer();
      addTearDown(container.dispose);
      await pumpDraftLoad(container);
      notifier = container.read(clinicSetupProvider.notifier);
    });

    test('revealBranchValidationErrors unconfirms branch and sets focus', () {
      final branchId = notifier.state.draft.branches.first.id;
      notifier.confirmBranch(branchId);

      notifier.revealBranchValidationErrors({'branch-0-name': 'Required'});

      final state = container.read(clinicSetupProvider);
      expect(state.confirmedBranchIds, isNot(contains(branchId)));
      expect(state.validationFocusEntityId, branchId);
    });

    test('revealStaffValidationErrors unconfirms staff and sets focus', () {
      final staffId = notifier.state.draft.staff.first.id;
      notifier.confirmStaff(staffId);

      notifier.revealStaffValidationErrors({'staff-0-name': 'Required'});

      final state = container.read(clinicSetupProvider);
      expect(state.confirmedStaffIds, isNot(contains(staffId)));
      expect(state.validationFocusEntityId, staffId);
    });

    test('revealServiceValidationErrors unconfirms service and sets focus', () {
      final serviceId = notifier.state.draft.services.first.id;
      notifier.confirmService(serviceId);

      notifier.revealServiceValidationErrors({'service-0-name': 'Required'});

      final state = container.read(clinicSetupProvider);
      expect(state.confirmedServiceIds, isNot(contains(serviceId)));
      expect(state.validationFocusEntityId, serviceId);
    });

    test('clearValidationFocus clears focus when set', () {
      notifier.revealServiceValidationErrors({'service-0-name': 'Required'});
      expect(container.read(clinicSetupProvider).validationFocusEntityId, isNotNull);

      notifier.clearValidationFocus();
      expect(container.read(clinicSetupProvider).validationFocusEntityId, isNull);

      notifier.clearValidationFocus();
      expect(container.read(clinicSetupProvider).validationFocusEntityId, isNull);
    });
  });
}
