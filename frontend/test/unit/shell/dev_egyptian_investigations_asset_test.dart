import 'package:ai_clinic/app/shell/dev/dev_egyptian_investigations_asset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DevEgyptianInvestigationsAsset', () {
    test('batchesFor splits names into fixed-size chunks', () {
      final batches = DevEgyptianInvestigationsAsset.batchesFor(['a', 'b', 'c', 'd', 'e'], batchSize: 2);
      expect(batches, [
        ['a', 'b'],
        ['c', 'd'],
        ['e'],
      ]);
    });

    test('loadNames reads bundled investigation catalog asset', () async {
      final names = await DevEgyptianInvestigationsAsset.loadNames();
      expect(names, isNotEmpty);
      expect(names.first, isNotEmpty);
      expect(names.every((name) => name.length <= 200), isTrue);
      expect(names, contains('Complete Blood Count (CBC)'));
      expect(names, contains('Chest X-Ray'));
    });

    test('asset file is present in bundle', () async {
      final raw = await rootBundle.loadString(DevEgyptianInvestigationsAsset.assetPath);
      expect(raw, contains('"names"'));
    });
  });
}
