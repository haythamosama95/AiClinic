import 'package:ai_clinic/features/settings/data/idle_timeout_preferences_store_web.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('idle timeout web preferences', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns default duration when no browser preference exists', () async {
      final duration = await loadIdleDuration();

      expect(duration, IdleTimeoutConfig.defaultDuration);
    });

    test('persists and reloads idle timeout minutes in browser storage', () async {
      await saveIdleDuration(const Duration(minutes: 45));

      final duration = await loadIdleDuration();

      expect(duration, const Duration(minutes: 45));
    });

    test('clamps saved minutes to configured bounds', () async {
      await saveIdleDuration(const Duration(minutes: 999));

      final duration = await loadIdleDuration();

      expect(duration.inMinutes, IdleTimeoutConfig.maxMinutes);
    });
  });
}
