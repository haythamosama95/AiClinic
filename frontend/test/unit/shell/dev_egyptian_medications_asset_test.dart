import 'package:ai_clinic/app/shell/dev/dev_egyptian_medications_asset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DevEgyptianMedicationsAsset', () {
    test('batchesFor splits names into fixed-size chunks', () {
      final batches = DevEgyptianMedicationsAsset.batchesFor(['a', 'b', 'c', 'd', 'e'], batchSize: 2);
      expect(batches, [
        ['a', 'b'],
        ['c', 'd'],
        ['e'],
      ]);
    });

    test('loadNames reads bundled medication catalog asset', () async {
      final names = await DevEgyptianMedicationsAsset.loadNames();
      expect(names, isNotEmpty);
      expect(names.first, isNotEmpty);
      expect(names.every((name) => name.length <= 200), isTrue);
    });

    test('asset file is present in bundle', () async {
      final raw = await rootBundle.loadString(DevEgyptianMedicationsAsset.assetPath);
      expect(raw, contains('"names"'));
    });
  });
}
