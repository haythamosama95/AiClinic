import 'package:ai_clinic/app/shell/dev/dev_clinic_seed_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DevClinicSeedSpec', () {
    test('defines three branches with two branch staff each plus two multi-branch staff', () {
      expect(DevClinicSeedSpec.branches, hasLength(3));
      for (final branch in DevClinicSeedSpec.branches) {
        expect(branch.branchStaff, hasLength(2));
      }
      expect(DevClinicSeedSpec.allBranchStaff, hasLength(2));
    });

    test('all branches are open daily from 9 AM to 9 PM', () {
      for (final branch in DevClinicSeedSpec.branches) {
        final schedule = DevClinicSeedSpec.workingScheduleFor(branch.scheduleKind);
        for (final day in schedule.days) {
          expect(day.isWorkingDay, isTrue, reason: '${day.day} should be a working day');
          expect(day.openTime, DevClinicSeedSpec.branchOpenTime);
          expect(day.closeTime, DevClinicSeedSpec.branchCloseTime);
        }
      }
    });

    test('patient names and phones are unique per branch index', () {
      final phones = <String>{};
      for (var branchIndex = 1; branchIndex <= 3; branchIndex++) {
        for (var patientIndex = 1; patientIndex <= DevClinicSeedSpec.patientsPerBranch; patientIndex++) {
          phones.add(DevClinicSeedSpec.patientPhone(branchIndex: branchIndex, patientIndex: patientIndex));
        }
      }

      expect(phones.length, 3 * DevClinicSeedSpec.patientsPerBranch);
      expect(
        DevClinicSeedSpec.patientFullName(branchCode: 'DTWN', index: 1),
        startsWith(DevClinicSeedSpec.patientNamePrefix),
      );
    });
  });
}
