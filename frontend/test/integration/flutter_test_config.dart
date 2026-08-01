import 'dart:async';

import '../boundary/harness/live_supabase_harness.dart';
import '../boundary/harness/reset.dart';

/// Initializes the local Supabase stack for boundary-gated integration tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await LiveSupabaseHarness.ensureReady();
  await boundaryCampaignReset();
  try {
    await testMain();
  } finally {
    await boundaryCampaignReset();
  }
}
