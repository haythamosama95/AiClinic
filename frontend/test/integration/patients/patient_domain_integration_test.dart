import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 integration scaffold — domain models compose for list/search payloads.
void main() {
  group('Patient management domain integration (Phase 1)', () {
    test('search result items parse under both list scopes', () {
      const row = {
        'id': 'p-integration',
        'full_name': 'Integration Patient',
        'branch_id': 'branch-a',
        'branch_name': 'Branch A',
      };

      for (final scope in PatientListScope.values) {
        expect(scope.rpcScopeValue, isIn(['branch', 'organization']));
        expect(PatientListItem.fromRow(row), isNotNull);
      }
    });

    test('default scope contract: this branch maps to branch RPC scope', () {
      expect(PatientListScope.thisBranch.rpcScopeValue, 'branch');
    });
  });
}
