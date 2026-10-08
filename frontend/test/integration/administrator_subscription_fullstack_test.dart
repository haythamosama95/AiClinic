@Tags(['fullstack'])
library;

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/config/supabase_config.dart';
import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../boundary/harness/boundary_test_context.dart';
import '../boundary/harness/fixture_factory.dart';
import '../boundary/harness/live_supabase_harness.dart' hide markTestSkipped;
import '../boundary/harness/role_sessions.dart';
import '../helpers/auth_test_support.dart';
import '../widget/ai/ai_surface_test_harness.dart';

final _aboUrl = Platform.environment['ABO_URL'] ?? 'http://127.0.0.1:8788';
final _paymobUrl = Platform.environment['PAYMOB_URL'] ?? 'http://127.0.0.1:8789';
var _hfsStackReady = false;
const _billingHost = 'billing.vendor.test';
const _paymobHmacSecret = 'paymob-hmac-unconfigured';

const _subscriptionSummaryKey = Key('billing_subscription_summary');
const _commercialNoticesKey = Key('billing_commercial_notices');
const _paymentHistoryKey = Key('billing_payment_history');
const _paymentHistoryNextKey = Key('billing_payment_history_next');

class _FullstackSubscriptionTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

const _paymobHmacFields = <String>[
  'amount_cents',
  'created_at',
  'currency',
  'error_occured',
  'has_parent_transaction',
  'id',
  'integration_id',
  'is_3d_secure',
  'is_auth',
  'is_capture',
  'is_refunded',
  'is_standalone_payment',
  'is_voided',
  'order.id',
  'owner',
  'pending',
  'source_data.pan',
  'source_data.sub_type',
  'source_data.type',
  'success',
];

void main() {
  _FullstackSubscriptionTestBinding();

  late BoundaryTestContext ctx;

  setUpAll(() async {
    _hfsStackReady = await _probeHfsReady();
    if (_hfsStackReady) {
      await LiveSupabaseHarness.ensureReady();
    }
  });

  setUp(() async {
    if (!_hfsStackReady) {
      return;
    }
    ctx = await BoundaryTestContext.create();
    await ctx.resetInstallation();
  });

  group('E2E-P6.4-01', () {
    testWidgets('E2E-P6.4-01', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack subscription tests.',
        );
      }

      final clinic = await ctx.ensureClinic(label: 'p64_dup');
      final installationId = _deterministicUuid('b641', clinic.suffix);
      await _seedActiveCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final billingToken = await _issueBillingToken();
      await _putBillingContact(billingToken);
      final offer = await _fetchFirstOffer(billingToken);

      final checkouts = await Future.wait([
        _createCheckout(
          billingToken: billingToken,
          offer: offer,
          clientRequestId: 'p64-dup-1-${clinic.suffix}',
        ),
        _createCheckout(
          billingToken: billingToken,
          offer: offer,
          clientRequestId: 'p64-dup-2-${clinic.suffix}',
        ),
      ]);
      final checkout1 = checkouts[0];
      final checkout2 = checkouts[1];

      await _replayPaymobFixtureForCheckout('success.json', checkoutId: checkout1.checkoutId);
      await _replayPaymobFixtureForCheckout('success.json', checkoutId: checkout2.checkoutId);

      final payments = await _waitForPayments(billingToken, count: 2);
      expect(payments.length, 2);
      final second = payments.last;
      expect(second['classification'], 'likely_duplicate');

      final subscription = await _fetchSubscription(billingToken);
      expect(subscription['notices'], contains('duplicate_payment'));

      final billingStatus = await _fetchBillingStatus();
      expect(billingStatus['queued_count'], 1);

      await _openSubscriptionPageFromRenew(tester, clinic: clinic);

      expect(find.byKey(_subscriptionSummaryKey), findsOneWidget);
      expect(find.byKey(_commercialNoticesKey), findsOneWidget);
      expect(find.byKey(_paymentHistoryKey), findsOneWidget);
      expect(find.text('duplicate_payment'), findsOneWidget);
      expect(find.text('likely_duplicate'), findsOneWidget);
      expect(find.text('${payments.first['reference']}'), findsOneWidget);
      expect(find.text('${payments.last['reference']}'), findsOneWidget);
      expect(find.text('${billingStatus['queued_count']}'), findsWidgets);
    });
  });

  group('E2E-P6.4-02', () {
    testWidgets('E2E-P6.4-02', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack subscription tests.',
        );
      }

      final clinic = await ctx.ensureClinic(label: 'p64_refund');
      final installationId = _deterministicUuid('b642', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final billingToken = await _issueBillingToken();
      await _putBillingContact(billingToken);
      final offer = await _fetchFirstOffer(billingToken);

      final checkout = await _createCheckout(
        billingToken: billingToken,
        offer: offer,
        clientRequestId: 'p64-refund-${clinic.suffix}',
      );
      final txnId = _transactionIdForCheckout(checkout.checkoutId);
      await _replayPaymobFixtureForCheckout(
        'success.json',
        checkoutId: checkout.checkoutId,
        transactionId: txnId,
      );
      await _waitForPayments(billingToken, count: 1);

      await _replayPaymobFixtureForCheckout(
        'refund-parent.json',
        checkoutId: checkout.checkoutId,
        transactionId: txnId + 2,
      );
      await _waitForReversal(billingToken);

      final subscription = await _fetchSubscription(billingToken);
      expect(subscription['notices'], containsAll(['reversal_recorded', 'terms_held']));

      final billingStatus = await _fetchBillingStatus();
      final notices = (billingStatus['notices'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      expect(notices.map((entry) => entry['code']), contains('ended_reversed'));

      await _openSubscriptionPageFromRenew(tester, clinic: clinic);

      expect(find.byKey(_subscriptionSummaryKey), findsOneWidget);
      expect(find.byKey(_commercialNoticesKey), findsOneWidget);
      expect(find.byKey(_paymentHistoryKey), findsOneWidget);
      expect(find.text('reversal_recorded'), findsOneWidget);
      expect(find.text('terms_held'), findsOneWidget);
      expect(find.text('ended_reversed'), findsOneWidget);
    });
  });

  group('E2E-P6.4-03', () {
    testWidgets('E2E-P6.4-03', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack subscription tests.',
        );
      }

      final clinic = await ctx.ensureClinic(label: 'p64_late');
      final installationId = _deterministicUuid('b643', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final billingToken = await _issueBillingToken();
      await _putBillingContact(billingToken);
      final offer = await _fetchFirstOffer(billingToken);

      final lateCheckout = await _createCheckout(
        billingToken: billingToken,
        offer: offer,
        clientRequestId: 'p64-late-${clinic.suffix}',
      );
      await _setCheckoutCancelled(lateCheckout.checkoutId);
      await _replayPaymobFixtureForCheckout('success.json', checkoutId: lateCheckout.checkoutId);
      await _waitForPayments(billingToken, count: 1);

      await _scriptPaymobInquiry('amount_mismatch');
      final withheldCheckout = await _createCheckout(
        billingToken: billingToken,
        offer: offer,
        clientRequestId: 'p64-withheld-${clinic.suffix}',
      );
      await _replayPaymobFixtureForCheckout(
        'success.json',
        checkoutId: withheldCheckout.checkoutId,
      );
      await _scriptPaymobInquiry('bound_success');

      final subscription = await _fetchSubscription(billingToken);
      expect(subscription['notices'], containsAll(['late_payment_honoured', 'payment_withheld']));

      await _openSubscriptionPageFromRenew(tester, clinic: clinic);

      expect(find.byKey(_commercialNoticesKey), findsOneWidget);
      expect(find.text('late_payment_honoured'), findsOneWidget);
      expect(find.text('payment_withheld'), findsOneWidget);
    });
  });

  group('E2E-P6.4-04', () {
    testWidgets('E2E-P6.4-04', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack subscription tests.',
        );
      }

      final clinic = await ctx.ensureClinic(label: 'p64_page');
      final installationId = _deterministicUuid('b644', clinic.suffix);
      await _seedEndsSoonCoverage(
        ctx: ctx,
        orgId: clinic.organizationId,
        installationId: installationId,
      );

      final sessions = RoleSessions(ctx, clinic);
      await sessions.signInAs(StaffRole.administrator);

      final billingToken = await _issueBillingToken();
      await _putBillingContact(billingToken);
      final offer = await _fetchFirstOffer(billingToken);

      for (var batch = 0; batch < 3; batch++) {
        final batchCheckoutIds = <String>[];
        for (var i = 0; i < 10; i++) {
          final checkout = await _createCheckout(
            billingToken: billingToken,
            offer: offer,
            clientRequestId: 'p64-page-$batch-$i-${clinic.suffix}',
          );
          batchCheckoutIds.add(checkout.checkoutId);
          await _replayPaymobFixtureForCheckout('success.json', checkoutId: checkout.checkoutId);
        }
        await _waitForPayments(billingToken, count: (batch + 1) * 10);
        if (batch < 2) {
          await _ageCheckoutFacts(batchCheckoutIds);
        }
      }

      final allReferences = <String>[];
      String? cursor;
      do {
        final page = await _fetchPayments(billingToken, cursor: cursor);
        final payments = (page['payments'] as List).cast<Map<String, dynamic>>();
        for (final payment in payments) {
          final reference = payment['reference']?.toString();
          if (reference != null) {
            allReferences.add(reference);
          }
        }
        final hasMore = page['has_more'] == true;
        cursor = hasMore ? page['next_cursor']?.toString() : null;
      } while (cursor != null && cursor.isNotEmpty);

      expect(allReferences.length, 30);

      final firstPage = await _fetchPayments(billingToken);
      expect((firstPage['payments'] as List).length, 20);
      expect(firstPage['has_more'], isTrue);
      final nextCursor = firstPage['next_cursor'] as String;
      expect(nextCursor, isNotEmpty);

      await _openSubscriptionPageFromRenew(tester, clinic: clinic);

      expect(find.byKey(_paymentHistoryKey), findsOneWidget);
      expect(find.byKey(_paymentHistoryNextKey), findsOneWidget);
      for (final reference in allReferences.take(20)) {
        expect(find.text(reference), findsOneWidget);
      }

      await tester.tap(find.byKey(_paymentHistoryNextKey));
      await tester.pumpAndSettle();

      for (final reference in allReferences) {
        expect(find.text(reference), findsOneWidget);
      }
    });
  });

  group('E2E-P6.4-05', () {
    testWidgets('E2E-P6.4-05', (tester) async {
      if (!_hfsStackReady) {
        fail(
          'H-FS stack unavailable (ABO at $_aboUrl). Start the H-FS stack before running fullstack subscription tests.',
        );
      }

      final orgA = await ctx.fixtures.bootstrapOnly(label: 'p64_org_a');
      final orgB = await ctx.fixtures.bootstrapOnly(label: 'p64_org_b');

      final orgARefs = await _arrangePaidSubscription(ctx, orgA);
      final orgBRefs = await _arrangePaidSubscription(ctx, orgB);

      final sessions = RoleSessions(ctx, orgA);
      await sessions.signInAs(StaffRole.administrator);

      await _openSubscriptionPageFromRenew(tester, clinic: orgA);

      expect(find.byKey(_subscriptionSummaryKey), findsOneWidget);
      expect(find.byKey(_paymentHistoryKey), findsOneWidget);
      expect(find.text(orgARefs.subscriptionRef), findsOneWidget);
      expect(find.text(orgARefs.paymentReference), findsOneWidget);
      expect(find.text(orgBRefs.subscriptionRef), findsNothing);
      expect(find.text(orgBRefs.paymentReference), findsNothing);
    });
  });
}

class _PaidSubscriptionRefs {
  const _PaidSubscriptionRefs({
    required this.subscriptionRef,
    required this.paymentReference,
  });

  final String subscriptionRef;
  final String paymentReference;
}

Future<_PaidSubscriptionRefs> _arrangePaidSubscription(
  BoundaryTestContext ctx,
  BoundaryClinicFixture clinic,
) async {
  final installationId = _deterministicUuid('b645', clinic.suffix);
  await _seedEndsSoonCoverage(
    ctx: ctx,
    orgId: clinic.organizationId,
    installationId: installationId,
  );

  await ctx.signInAdminForClinic(clinic);
  final billingToken = await _issueBillingToken();
  await _putBillingContact(billingToken);
  final offer = await _fetchFirstOffer(billingToken);
  final checkout = await _createCheckout(
    billingToken: billingToken,
    offer: offer,
    clientRequestId: 'p64-boundary-${clinic.suffix}',
  );
  await _replayPaymobFixtureForCheckout('success.json', checkoutId: checkout.checkoutId);
  final payments = await _waitForPayments(billingToken, count: 1);
  final subscription = await _fetchSubscription(billingToken);
  await ctx.signOut();
  return _PaidSubscriptionRefs(
    subscriptionRef: subscription['subscription_ref']?.toString() ?? '',
    paymentReference: payments.first['reference']?.toString() ?? '',
  );
}

Future<void> _openSubscriptionPageFromRenew(
  WidgetTester tester, {
  required BoundaryClinicFixture clinic,
}) async {
  final router = _billingRouter(
    branchIds: [clinic.branchId],
    activeBranchId: clinic.branchId,
  );
  final composition = buildLiveVisitSummaryComposition(
    client: LiveSupabaseHarness.client,
    visitId: testVisitId,
    staffIsAdministrator: true,
    reachabilityPort: FakePlatformReachabilityPort(reachable: false),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
        authSessionProvider.overrideWith(
          () => MutableAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(
                role: StaffRole.administrator,
                branchIds: [clinic.branchId],
                activeBranchId: clinic.branchId,
              ),
            ),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.go(AppRoutes.ai);
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: liveVisitSummaryHostBody(visitId: testVisitId, composition: composition),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('ai_notice_renew')));
  await tester.pumpAndSettle();
}

GoRouter _billingRouter({
  StaffRole role = StaffRole.administrator,
  List<String>? branchIds,
  String? activeBranchId,
}) {
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(LiveSupabaseHarness.client),
      authSessionProvider.overrideWith(
        () => MutableAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(
              role: role,
              branchIds: branchIds ?? const ['00000000-0000-4000-8000-000000000001'],
              activeBranchId: activeBranchId,
            ),
          ),
        ),
      ),
    ],
  );
  return container.read(appRouterProvider);
}

Future<bool> _probeHfsReady() async {
  try {
    final response = await http
        .get(
          Uri.parse('$_aboUrl/v1/offers'),
          headers: {'Host': _billingHost},
        )
        .timeout(const Duration(seconds: 3));
    return response.statusCode < 500;
  } on Exception {
    return false;
  }
}

Future<String> _issueBillingToken() async {
  final response = await LiveSupabaseHarness.client.rpc(
    'issue_billing_token',
    params: {'p_contract_version': backendRpc},
  );
  final tokenMap = Map<String, dynamic>.from(response as Map);
  final data = Map<String, dynamic>.from(tokenMap['data'] as Map);
  return data['token'] as String;
}

Future<Map<String, dynamic>> _fetchBillingStatus() async {
  final response = await LiveSupabaseHarness.client.rpc(
    'get_ai_billing_status',
    params: {'p_contract_version': backendRpc},
  );
  final statusMap = Map<String, dynamic>.from(response as Map);
  return Map<String, dynamic>.from(statusMap['data'] as Map);
}

Future<Map<String, dynamic>> _fetchFirstOffer(String billingToken) async {
  final response = await http.get(
    Uri.parse('$_aboUrl/v1/offers'),
    headers: _aboHeaders(billingToken),
  );
  expect(response.statusCode, 200);
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final offers = (body['offers'] as List).cast<Map<String, dynamic>>();
  expect(offers, isNotEmpty);
  return offers.first;
}

Future<void> _putBillingContact(String billingToken) async {
  final response = await http.put(
    Uri.parse('$_aboUrl/v1/billing-contact'),
    headers: {
      ..._aboHeaders(billingToken),
      'content-type': 'application/json',
    },
    body: jsonEncode({
      'client_request_id': 'p64-contact-${DateTime.now().microsecondsSinceEpoch}',
      'name': 'P6.4 Administrator',
      'email': 'p64-admin@clinic.test',
      'phone': '+201001234567',
    }),
  );
  expect(response.statusCode, 200);
}

class _CreatedCheckout {
  const _CreatedCheckout({required this.checkoutId, required this.reference});

  final String checkoutId;
  final String reference;
}

Future<_CreatedCheckout> _createCheckout({
  required String billingToken,
  required Map<String, dynamic> offer,
  required String clientRequestId,
}) async {
  final response = await http.post(
    Uri.parse('$_aboUrl/v1/checkouts'),
    headers: {
      ..._aboHeaders(billingToken),
      'content-type': 'application/json',
    },
    body: jsonEncode({
      'client_request_id': clientRequestId,
      'offer_id': offer['offer_id'],
      'offer_version': offer['version'],
      'terms_version': (offer['terms'] as Map)['version'],
    }),
  );
  expect(response.statusCode, 201, reason: 'POST /v1/checkouts should succeed');
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return _CreatedCheckout(
    checkoutId: body['checkout_id']?.toString() ?? '',
    reference: body['reference']?.toString() ?? '',
  );
}

Map<String, String> _aboHeaders(String billingToken) {
  return {
    'Authorization': 'Bearer $billingToken',
    'Host': _billingHost,
    'Abo-Contract-Version': '$aboClinic',
    'accept': 'application/json',
  };
}

Future<Map<String, dynamic>> _fetchSubscription(String billingToken) async {
  final response = await http.get(
    Uri.parse('$_aboUrl/v1/subscription'),
    headers: _aboHeaders(billingToken),
  );
  expect(response.statusCode, 200);
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _fetchPayments(String billingToken, {String? cursor}) async {
  final uri = cursor == null || cursor.isEmpty
      ? Uri.parse('$_aboUrl/v1/payments')
      : Uri.parse('$_aboUrl/v1/payments?cursor=${Uri.encodeComponent(cursor)}');
  final response = await http.get(uri, headers: _aboHeaders(billingToken));
  expect(response.statusCode, 200);
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<List<Map<String, dynamic>>> _waitForPayments(
  String billingToken, {
  required int count,
}) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    final page = await _fetchPayments(billingToken);
    final payments = (page['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (payments.length >= count) {
      return payments;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Timed out waiting for $count payments');
}

Future<void> _waitForReversal(String billingToken) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    final page = await _fetchPayments(billingToken);
    final payments = (page['payments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (payments.isNotEmpty) {
      final reversals = payments.first['reversals'];
      if (reversals is List && reversals.isNotEmpty) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('Timed out waiting for reversal in payment history');
}

Future<void> _replayPaymobFixtureForCheckout(
  String fixtureName, {
  required String checkoutId,
  int? transactionId,
}) async {
  final orderId = await _readPaymobOrderId(checkoutId);
  final txnId = transactionId ?? _transactionIdForCheckout(checkoutId);
  final amountMinor = await _readCheckoutAmountMinor(checkoutId);
  await _scriptPaymobStub(orderId: orderId, amountMinor: amountMinor);

  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final fixturePath = '$repoRoot/abo/test/fixtures/paymob/$fixtureName';
  final fixture = jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final obj = Map<String, dynamic>.from(fixture['obj'] as Map);
  obj['id'] = txnId;
  obj['order'] = {'id': int.parse(orderId)};
  final body = jsonEncode({'type': fixture['type'], 'obj': obj});
  final hmac = _signPaymobObj(obj);
  final response = await http.post(
    Uri.parse('$_aboUrl/notify/paymob?hmac=${Uri.encodeComponent(hmac)}'),
    headers: {
      'Host': _billingHost,
      'content-type': 'application/json',
      'cf-connecting-ip': '203.0.113.10',
    },
    body: body,
  );
  expect(response.statusCode, 200, reason: 'paymob fixture $fixtureName should be accepted by the running stack');
}

Future<void> _scriptPaymobInquiry(String inquiry) async {
  final response = await http.post(
    Uri.parse('$_paymobUrl/__script'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'inquiry': inquiry}),
  );
  expect(response.statusCode, 204);
}

Future<void> _scriptPaymobStub({required String orderId, required int amountMinor}) async {
  final response = await http.post(
    Uri.parse('$_paymobUrl/__script'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'amount_cents': '$amountMinor',
      'intention_order_id': orderId,
      'inquiry': 'bound_success',
    }),
  );
  expect(response.statusCode, 204);
}

String _signPaymobObj(Map<String, dynamic> obj) {
  final concatenated = _paymobHmacFields.map((field) => _paymobFieldValue(obj, field)).join();
  final digest = Hmac(sha512, utf8.encode(_paymobHmacSecret)).convert(utf8.encode(concatenated));
  return digest.toString();
}

String _paymobFieldValue(Map<String, dynamic> obj, String field) {
  if (field == 'order.id') {
    return '${(obj['order'] as Map)['id']}';
  }
  if (field.startsWith('source_data.')) {
    final key = field.split('.').last;
    return '${(obj['source_data'] as Map)[key]}';
  }
  final raw = obj[field];
  if (raw is bool) {
    return raw ? 'true' : 'false';
  }
  return '$raw';
}

int _transactionIdForCheckout(String checkoutId) {
  return 99000 + checkoutId.hashCode.abs() % 10000;
}

Future<String> _readPaymobOrderId(String checkoutId) async {
  final row = await _queryAboD1(
    "SELECT order_id FROM paymob_intention WHERE checkout_id = '${checkoutId.replaceAll("'", "''")}' LIMIT 1",
  );
  final orderId = row?['order_id']?.toString();
  if (orderId == null || orderId.isEmpty) {
    fail('paymob_intention.order_id missing for checkout $checkoutId');
  }
  return orderId;
}

Future<int> _readCheckoutAmountMinor(String checkoutId) async {
  final row = await _queryAboD1(
    "SELECT charged_price_minor FROM checkout WHERE checkout_id = '${checkoutId.replaceAll("'", "''")}' LIMIT 1",
  );
  return int.parse(row?['charged_price_minor']?.toString() ?? '800');
}

Future<void> _setCheckoutCancelled(String checkoutId) async {
  await _executeAboD1(
    "UPDATE checkout_status SET state = 'cancelled', last_event_at = datetime('now') WHERE checkout_id = '${checkoutId.replaceAll("'", "''")}'",
  );
}

Future<void> _ageCheckoutFacts(List<String> checkoutIds) async {
  if (checkoutIds.isEmpty) {
    return;
  }
  final keys = checkoutIds.map((id) => "'${id.replaceAll("'", "''")}'").join(', ');
  await _executeAboD1(
    "UPDATE fact_log SET created_at = datetime('now', '-2 hours') WHERE \"table\" = 'checkout' AND key IN ($keys)",
  );
}

Future<String?> _aboSqlitePath() async {
  final repoRoot = File('pubspec.yaml').existsSync() ? Directory.current.parent.path : Directory.current.path;
  final dbDir = Directory('$repoRoot/e2e/fullstack/.wrangler/abo/v3/d1/miniflare-D1DatabaseObject');
  if (!dbDir.existsSync()) {
    return null;
  }
  final files = dbDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sqlite'))
      .toList();
  if (files.isEmpty) {
    return null;
  }
  return files.first.path;
}

Future<Map<String, Object?>?> _queryAboD1(String sql) async {
  final dbFile = await _aboSqlitePath();
  if (dbFile == null) {
    fail('Local ABO D1 database not found under e2e/fullstack/.wrangler/abo');
  }
  final result = await Process.run('sqlite3', ['-json', dbFile, sql]);
  if (result.exitCode != 0) {
    fail('sqlite3 query failed: ${result.stderr}');
  }
  final output = '${result.stdout}'.trim();
  if (output.isEmpty) {
    return null;
  }
  final rows = jsonDecode(output) as List;
  if (rows.isEmpty) {
    return null;
  }
  return Map<String, Object?>.from(rows.first as Map);
}

Future<void> _executeAboD1(String sql) async {
  final dbFile = await _aboSqlitePath();
  if (dbFile == null) {
    fail('Local ABO D1 database not found under e2e/fullstack/.wrangler/abo');
  }
  final result = await Process.run('sqlite3', [dbFile, sql]);
  if (result.exitCode != 0) {
    fail('sqlite3 execute failed: ${result.stderr}');
  }
}

String _deterministicUuid(String prefix, String label) {
  final hash = '$prefix$label'.hashCode.abs();
  final p1 = hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  final p2 = (hash >> 4).toRadixString(16).padLeft(4, '0').substring(0, 4);
  final p3 = (hash >> 8).toRadixString(16).padLeft(3, '0').substring(0, 3);
  final p4 = (hash >> 12).toRadixString(16).padLeft(3, '0').substring(0, 3);
  final p5 = hash.toRadixString(16).padLeft(12, '0').substring(0, 12);
  return '$p1-$p2-4$p3-8$p4-$p5';
}

Future<void> _seedActiveCoverage({
  required BoundaryTestContext ctx,
  required String orgId,
  required String installationId,
}) async {
  await ctx.sql.execute('''
DELETE FROM ai_internal.clinic_ai_coverage WHERE organization_id = '$orgId'::uuid;

INSERT INTO ai_internal.membership (user_id, organization_id, role)
SELECT sm.auth_user_id, '$orgId'::uuid, sm.role
FROM public.staff_members sm
JOIN public.staff_branch_assignments sba
  ON sba.staff_member_id = sm.id
  AND sba.is_deleted = false
JOIN public.branches b
  ON b.id = sba.branch_id
  AND b.organization_id = '$orgId'::uuid
  AND b.is_deleted = false
WHERE sm.is_deleted = false
  AND sm.is_active = true
ON CONFLICT (user_id, organization_id) DO NOTHING;

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
  NULL,
  'TERM-P64',
  'P6.4 Test Plan',
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

Future<void> _seedEndsSoonCoverage({
  required BoundaryTestContext ctx,
  required String orgId,
  required String installationId,
}) async {
  await _seedActiveCoverage(ctx: ctx, orgId: orgId, installationId: installationId);
  await ctx.sql.execute('''
UPDATE ai_internal.clinic_ai_coverage
SET ends_at = now() + interval '3 days',
    grace_ends_at = now() + interval '10 days'
WHERE organization_id = '$orgId'::uuid;
''');
}
