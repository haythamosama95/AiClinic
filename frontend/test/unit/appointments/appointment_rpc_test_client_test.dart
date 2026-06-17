import 'package:flutter_test/flutter_test.dart';

import '../../support/appointment_rpc_test_client.dart';

void main() {
  group('appointmentRpcDefaultListItem', () {
    test('uses deterministic default start when startLocal is omitted', () {
      final item = appointmentRpcDefaultListItem();
      final start = DateTime.parse(item['start_time'] as String).toLocal();

      expect(start, DateTime(2026, 6, 15, 10, 0));
      expect(item['end_time'], DateTime(2026, 6, 15, 10, 30).toUtc().toIso8601String());
    });

    test('respects explicit startLocal override', () {
      final customStart = DateTime(2026, 7, 1, 14, 15);
      final item = appointmentRpcDefaultListItem(startLocal: customStart);

      expect(DateTime.parse(item['start_time'] as String).toLocal(), customStart);
    });
  });
}
