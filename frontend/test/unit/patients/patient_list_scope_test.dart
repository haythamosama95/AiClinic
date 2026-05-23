import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientListScope.tryParse', () {
    test('parses UI and RPC aliases', () {
      expect(PatientListScope.tryParse('thisBranch'), PatientListScope.thisBranch);
      expect(PatientListScope.tryParse('this_branch'), PatientListScope.thisBranch);
      expect(PatientListScope.tryParse('branch'), PatientListScope.thisBranch);

      expect(PatientListScope.tryParse('allBranches'), PatientListScope.allBranches);
      expect(PatientListScope.tryParse('all_branches'), PatientListScope.allBranches);
      expect(PatientListScope.tryParse('organization'), PatientListScope.allBranches);
    });

    test('returns null for invalid scope strings', () {
      expect(PatientListScope.tryParse(null), isNull);
      expect(PatientListScope.tryParse(''), isNull);
      expect(PatientListScope.tryParse('org'), isNull);
      expect(PatientListScope.tryParse('everywhere'), isNull);
    });
  });

  group('PatientListScope.rpcScopeValue', () {
    test('maps to search_patients contract values', () {
      expect(PatientListScope.thisBranch.rpcScopeValue, 'branch');
      expect(PatientListScope.allBranches.rpcScopeValue, 'organization');
    });

    test('default session scope is this branch per spec', () {
      expect(PatientListScope.thisBranch, isNot(PatientListScope.allBranches));
      expect(PatientListScope.thisBranch.rpcScopeValue, 'branch');
    });
  });
}
