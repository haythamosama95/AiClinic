import 'dart:async';

import '../boundary/harness/live_supabase_harness.dart';
import '../boundary/harness/reset.dart';

/// Boots integration tests. Harness setup stays in each file's [setUpAll] so
/// widget tests can register [TestWidgetsFlutterBinding] before
/// [LiveSupabaseHarness.ensureReady] runs inside a test zone.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  try {
    await testMain();
  } finally {
    if (LiveSupabaseHarness.isAvailable) {
      await boundaryCampaignReset();
    }
  }
}
