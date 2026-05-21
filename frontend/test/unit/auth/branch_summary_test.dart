import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchSummary', () {
    test('fromRow parses branch fields', () {
      final summary = BranchSummary.fromRow({
        'id': 'branch-test-uuid',
        'name': 'Main Branch',
        'code': 'MAIN',
        'address': '123 Clinic St',
        'phone': '+20 100 000 0000',
        'maps_url': 'https://maps.example/main',
      });

      expect(summary, isNotNull);
      expect(summary!.id, 'branch-test-uuid');
      expect(summary.name, 'Main Branch');
      expect(summary.code, 'MAIN');
      expect(summary.address, '123 Clinic St');
      expect(summary.phone, '+20 100 000 0000');
      expect(summary.mapsUrl, 'https://maps.example/main');
    });

    test('fromRow rejects rows without id or name', () {
      expect(BranchSummary.fromRow({'id': '', 'name': 'X'}), isNull);
      expect(BranchSummary.fromRow({'id': 'x', 'name': ''}), isNull);
    });

    test('detailTooltip includes populated optional fields', () {
      const summary = BranchSummary(
        id: 'branch-test-uuid',
        name: 'Main Branch',
        code: 'MAIN',
        address: '123 Clinic St',
        phone: '+20 100 000 0000',
        mapsUrl: 'https://maps.example/main',
      );

      final tooltip = summary.detailTooltip;
      expect(tooltip, contains('Branch ID: branch-test-uuid'));
      expect(tooltip, contains('Code: MAIN'));
      expect(tooltip, contains('Address: 123 Clinic St'));
      expect(tooltip, contains('Phone: +20 100 000 0000'));
      expect(tooltip, contains('Maps: https://maps.example/main'));
    });

    test('detailTooltip omits empty optional fields', () {
      const summary = BranchSummary(id: 'branch-test-uuid', name: 'Main Branch');

      expect(summary.detailTooltip, 'Branch ID: branch-test-uuid');
      expect(summary.detailTooltip, isNot(contains('Code:')));
    });
  });
}
