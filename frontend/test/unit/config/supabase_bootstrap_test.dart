import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(SupabaseBootstrap.debugResetForTests);

  test('debugMarkReadyForTests marks bootstrap ready', () {
    SupabaseBootstrap.debugResetForTests();
    expect(SupabaseBootstrap.isReady, isFalse);
    SupabaseBootstrap.debugMarkReadyForTests();
    expect(SupabaseBootstrap.isReady, isTrue);
  });

  test('debugResetForTests clears readiness', () {
    SupabaseBootstrap.debugMarkReadyForTests();
    SupabaseBootstrap.debugResetForTests();
    expect(SupabaseBootstrap.isReady, isFalse);
  });
}
