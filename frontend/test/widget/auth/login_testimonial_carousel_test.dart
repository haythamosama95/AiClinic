import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('testimonial image assets are bundled', () async {
    for (final path in [
      'assets/images/auth/testimonial_1.jpg',
      'assets/images/auth/testimonial_2.jpg',
      'assets/images/auth/testimonial_3.jpg',
    ]) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(10_000), reason: path);
    }
  });
}
