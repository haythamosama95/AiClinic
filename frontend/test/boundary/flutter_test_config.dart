import 'dart:async';

import 'harness/live_supabase_harness.dart';
import 'harness/reset.dart';

/// Runs once per `flutter test test/boundary` invocation: reset DB before and after the campaign.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await LiveSupabaseHarness.ensureReady();
  await boundaryCampaignReset();
  try {
    await testMain();
  } finally {
    await boundaryCampaignReset();
  }
}
