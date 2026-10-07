@Tags(['fullstack'])
library;

import 'dart:io';

import 'package:ai_clinic/features/ai/availability/ai_availability_reader.dart';
import 'package:ai_clinic/features/ai/host/ai_feature_host_page.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../boundary/harness/boundary_test_context.dart';
import '../boundary/harness/live_supabase_harness.dart';
import '../boundary/harness/role_sessions.dart';
import '../widget/ai/ai_surface_test_harness.dart';

void main() {
  late BoundaryTestContext ctx;
  late int backendRpc;

  setUpAll(() async {
    await LiveSupabaseHarness.ensureReady();
    backendRpc = _readBackendRpcVersion();
    ctx = await BoundaryTestContext.create();
  });

  setUp(() async {
    await ctx.resetInstallation();
  });

  group('E2E-P6.1-01', () {
    test('E2E-P6.1-01 staff session reads active status via get_ai_status without ABO calls', () async {
      final clinic = await ctx.ensureClinic(label: 'p61_status');
      final installationId = 'p61-${clinic.suffix}';
      await _seedActiveCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.doctor);

      final client = LiveSupabaseHarness.client;
      final directStatus = await client.rpc(
        'get_ai_status',
        params: {'p_contract_version': backendRpc},
      );
      expect(directStatus, isA<Map>());
      final statusMap = Map<String, dynamic>.from(directStatus as Map);
      expect(statusMap['success'], isTrue);
      expect(statusMap['contract_version'], backendRpc);
      final data = Map<String, dynamic>.from(statusMap['data'] as Map);
      expect(data['available'], isTrue);
      expect(data['state'], 'active');

      final networkSpy = InMemoryPlatformNetworkSpy();
      final composition = buildLiveVisitSummaryComposition(
        client: client,
        visitId: testVisitId,
        networkSpy: networkSpy,
        reachabilityPort: FakePlatformReachabilityPort(reachable: false),
      );

      final availability = await composition.dependencies.availabilityReader.read();
      expect(availability.enrolled, isTrue, reason: 'production reader should follow get_ai_status available');

      final reader = composition.dependencies.availabilityReader;
      expect(reader, isA<SupabaseAiAvailabilityReader>());

      expect(networkSpy.platformCallCount, 0);
      expect(networkSpy.urls.where((url) => url.contains('abo') || url.contains('/v1/')), isEmpty);
    });
  });
}

int _readBackendRpcVersion() {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final packagePath = File('$repoRoot/packages/vendor-contracts/src/version.ts');
  final match = RegExp(r'backendRpc\s*:\s*(\d+)').firstMatch(packagePath.readAsStringSync());
  expect(match, isNotNull, reason: 'backendRpc not found in version.ts');
  return int.parse(match!.group(1)!);
}

Future<void> _seedActiveCoverage({
  required BoundaryTestContext ctx,
  required String orgId,
  required String installationId,
}) async {
  await ctx.sql.execute('''
DELETE FROM ai_internal.clinic_ai_coverage WHERE organization_id = '$orgId'::uuid;

INSERT INTO ai_internal.clinic_ai_coverage (
  organization_id,
  installation_id,
  binding_epoch,
  clinic_seq,
  state,
  reason,
  term_ref,
  plan_display_name,
  starts_at,
  ends_at,
  grace_ends_at,
  allowance,
  used,
  band,
  queued_count,
  held_count,
  suspended,
  event_at,
  applied_at
) VALUES (
  '$orgId'::uuid,
  '$installationId'::uuid,
  1,
  1,
  'active',
  'none',
  'TERM-P61',
  'P6.1 Test Plan',
  now() - interval '30 days',
  now() + interval '30 days',
  now() + interval '37 days',
  10000,
  0,
  'ok',
  0,
  0,
  false,
  timestamp '2020-06-15 12:00:00+00',
  timestamp '2021-03-20 08:00:00+00'
);

UPDATE ai_internal.feed_state
SET last_success_at = now()
WHERE singleton;
''');
}
