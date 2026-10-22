import 'dart:async';
import 'dart:convert';

import 'package:ai_clinic/core/contract_versions.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/administrator_billing_page.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:ai_clinic/features/ai/billing/checkout_screen.dart';
import 'package:ai_clinic/features/ai/billing/commercial_notices.dart';
import 'package:ai_clinic/features/ai/billing/payment_history.dart';
import 'package:ai_clinic/features/ai/billing/subscription_summary.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R7-UI2 billing refresh generation', () {
    testWidgets('R7-UI2: generation change reloads summary and ignores stale reply', (tester) async {
      final pending = <Completer<dynamic>>[];
      final client = _client((_) async => _subscriptionResponse(const []));
      Future<dynamic> rpc(String name, Map<String, dynamic> params) {
        final completer = Completer<dynamic>();
        pending.add(completer);
        return completer.future;
      }

      await tester.pumpWidget(_app(SubscriptionSummary(client: client, rpc: rpc, generation: 0)));
      await _flush(tester);
      await tester.pumpWidget(_app(SubscriptionSummary(client: client, rpc: rpc, generation: 1)));
      await _flush(tester);
      expect(pending, hasLength(2));

      pending[1].complete(_statusReply('New plan'));
      await _flush(tester);
      expect(find.text('New plan'), findsOneWidget);

      pending[0].complete(_statusReply('Old plan'));
      await _flush(tester);
      expect(find.text('Old plan'), findsNothing);
      expect(find.text('New plan'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: generation change reloads commercial notices with localized copy', (tester) async {
      var notices = const ['terms_held'];
      final client = _client((request) async {
        if (request.url.path == '/v1/subscription') {
          return http.Response(jsonEncode(_subscriptionBody(notices)), 200);
        }
        return http.Response('{}', 500);
      });

      await tester.pumpWidget(_app(CommercialNotices(client: client, generation: 0)));
      await _flush(tester);
      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.aiBillingNoticeTermsHeld), findsOneWidget);

      notices = const ['duplicate_payment'];
      await tester.pumpWidget(_app(CommercialNotices(client: client, generation: 1)));
      await _flush(tester);
      expect(find.text(en.aiBillingNoticeTermsHeld), findsNothing);
      expect(find.text(en.aiBillingNoticeDuplicatePayment), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: generation change restarts payment history and drops stale next page', (tester) async {
      Completer<http.Response>? stalePage;
      var firstPageReads = 0;
      final client = _client((request) async {
        if (request.url.path != '/v1/payments') {
          return http.Response('{}', 500);
        }
        if (request.url.queryParameters['cursor'] == 'PAY-1') {
          stalePage = Completer<http.Response>();
          return stalePage!.future;
        }
        firstPageReads++;
        if (firstPageReads == 1) {
          return http.Response(_paymentsBody(const ['PAY-1'], hasMore: true, nextCursor: 'PAY-1'), 200);
        }
        return http.Response(_paymentsBody(const ['PAY-9'], hasMore: false, nextCursor: ''), 200);
      });

      await tester.pumpWidget(_app(PaymentHistory(client: client, generation: 0)));
      await _flush(tester);
      expect(find.textContaining('PAY-1'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('billing_payment_history_next')));
      await tester.tap(find.byKey(const Key('billing_payment_history_next')));
      await _flush(tester);
      expect(stalePage, isNotNull);

      await tester.pumpWidget(_app(PaymentHistory(client: client, generation: 1)));
      await _flush(tester);
      expect(find.textContaining('PAY-9'), findsOneWidget);
      expect(find.textContaining('PAY-1'), findsNothing);

      stalePage!.complete(http.Response(_paymentsBody(const ['PAY-2'], hasMore: false, nextCursor: ''), 200));
      await _flush(tester);
      expect(find.textContaining('PAY-2'), findsNothing);
      expect(find.textContaining('PAY-9'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: checkout Paid reports the state change once', (tester) async {
      final seen = <CheckoutShownState>[];
      var polls = 0;
      final client = _client((request) async {
        if (request.url.path == '/v1/checkouts/chk-1') {
          polls++;
          return http.Response(jsonEncode(_checkoutBody('Paid')), 200);
        }
        return http.Response('{}', 500);
      });

      await tester.pumpWidget(_app(CheckoutScreen(
        client: client,
        checkoutId: 'chk-1',
        initialCheckout: CheckoutRead.fromJson(_checkoutBody('Waiting')),
        onCheckoutStateChanged: (read) => seen.add(read.shownState),
      )));
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(polls, 1);
      expect(seen, [CheckoutShownState.paid]);

      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(polls, 2);
      expect(seen, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: Active requests one projection pull and rereads at most four times', (tester) async {
      final harness = _BillingPageHarness(pullSucceeds: true, planFromRead: null);
      await harness.pump(tester);

      expect(harness.statusReads, 1);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(harness.pulls, 1);
      expect(harness.statusReads, 2, reason: 'Active reloads the summary once');

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 30));
        await _flush(tester);
      }
      expect(harness.statusReads, 6, reason: 'four bounded rereads after the Active reload');
      expect(harness.pulls, 1, reason: 'a read refresh never requests the pull again');

      await tester.pump(const Duration(seconds: 60));
      await _flush(tester);
      expect(harness.statusReads, 6, reason: 'no fifth reread after two minutes');
      expect(find.byKey(const Key('billing_projection_pending')), findsOneWidget);
      expect(find.byKey(const Key('billing_refresh')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: projected plan after a reread clears the pending message', (tester) async {
      final harness = _BillingPageHarness(
        pullSucceeds: true,
        planFromRead: (reads) => reads >= 3 ? 'Plan Pro' : null,
      );
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(find.byKey(const Key('billing_projection_pending')), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      expect(harness.statusReads, 3);
      expect(find.text('Plan Pro'), findsOneWidget);
      expect(find.byKey(const Key('billing_projection_pending')), findsNothing);

      await tester.pump(const Duration(seconds: 60));
      await _flush(tester);
      expect(harness.statusReads, 3, reason: 'a confirmed projection stops the rereads');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: failed pull stays visible and manual refresh requests it again', (tester) async {
      final harness = _BillingPageHarness(pullSucceeds: false, planFromRead: null);
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(harness.pulls, 1);
      expect(find.byKey(const Key('billing_projection_pull_failed')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('billing_refresh')));
      await tester.tap(find.byKey(const Key('billing_refresh')));
      await _flush(tester);
      expect(harness.pulls, 2);
      expect(find.byKey(const Key('billing_projection_pull_failed')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: review F4 summary keeps previous content visible during a refresh', (tester) async {
      final pending = <Completer<dynamic>>[];
      var calls = 0;
      Future<dynamic> rpc(String name, Map<String, dynamic> params) {
        calls++;
        if (calls == 1) {
          return Future<dynamic>.value(_statusReply('Old plan'));
        }
        final completer = Completer<dynamic>();
        pending.add(completer);
        return completer.future;
      }
      final client = _client((_) async => _subscriptionResponse(const []));

      await tester.pumpWidget(_app(SubscriptionSummary(client: client, rpc: rpc, generation: 0)));
      await _flush(tester);
      expect(find.text('Old plan'), findsOneWidget);

      await tester.pumpWidget(_app(SubscriptionSummary(client: client, rpc: rpc, generation: 1)));
      await _flush(tester);
      expect(find.text('Old plan'), findsOneWidget);
      expect(find.byKey(const Key('billing_summary_refreshing')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending.single.complete(_statusReply('New plan'));
      await _flush(tester);
      expect(find.text('New plan'), findsOneWidget);
      expect(find.byKey(const Key('billing_summary_refreshing')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: review F4 payment history keeps previous rows visible during a refresh', (tester) async {
      Completer<http.Response>? gate;
      var reads = 0;
      final client = _client((request) async {
        if (request.url.path != '/v1/payments') {
          return http.Response('{}', 500);
        }
        reads++;
        if (reads == 1) {
          return http.Response(_paymentsBody(const ['PAY-1'], hasMore: false, nextCursor: ''), 200);
        }
        gate = Completer<http.Response>();
        return gate!.future;
      });

      await tester.pumpWidget(_app(PaymentHistory(client: client, generation: 0)));
      await _flush(tester);
      expect(find.textContaining('PAY-1'), findsOneWidget);

      await tester.pumpWidget(_app(PaymentHistory(client: client, generation: 1)));
      await _flush(tester);
      expect(find.textContaining('PAY-1'), findsOneWidget);
      expect(find.byKey(const Key('billing_payment_history_refreshing')), findsOneWidget);

      gate!.complete(http.Response(_paymentsBody(const ['PAY-9'], hasMore: false, nextCursor: ''), 200));
      await _flush(tester);
      expect(find.textContaining('PAY-9'), findsOneWidget);
      expect(find.textContaining('PAY-1'), findsNothing);
      expect(find.byKey(const Key('billing_payment_history_refreshing')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: review F2 renewal on a clinic with a plan stays pending until projected fields change', (tester) async {
      final harness = _BillingPageHarness(
        pullSucceeds: true,
        planFromRead: (_) => 'Plan Pro',
        endsAtFromRead: (reads) => reads >= 4 ? '2027-01-01T00:00:00Z' : '2026-11-01T00:00:00Z',
      );
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(harness.statusReads, 2);
      expect(find.byKey(const Key('billing_projection_pending')), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      expect(harness.statusReads, 3);
      expect(
        find.byKey(const Key('billing_projection_pending')),
        findsOneWidget,
        reason: 'the first reread shows the same projection as the baseline, so it must not clear',
      );

      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      expect(harness.statusReads, 4);
      expect(find.byKey(const Key('billing_projection_pending')), findsNothing, reason: 'end date changed');

      await tester.pump(const Duration(seconds: 60));
      await _flush(tester);
      expect(harness.statusReads, 4, reason: 'a confirmed projection stops the rereads');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: review F5 the bound starts at the pull request so the last reread lands within two minutes', (tester) async {
      final harness = _BillingPageHarness(pullSucceeds: true, planFromRead: (_) => null);
      final gate = Completer<void>();
      harness.pullGate = gate;
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(harness.pulls, 1);

      // The pull reply arrives at about 20 seconds after the request.
      await tester.pump(const Duration(seconds: 19));
      gate.complete();
      await _flush(tester);
      expect(harness.statusReads, 2);

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 30));
        await _flush(tester);
      }
      expect(harness.statusReads, 5, reason: 'three rereads by about 110 seconds');

      await tester.pump(const Duration(seconds: 12));
      await _flush(tester);
      expect(harness.statusReads, 6, reason: 'the fourth reread lands two minutes after the pull request');

      await tester.pump(const Duration(seconds: 60));
      await _flush(tester);
      expect(harness.statusReads, 6);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: review F3 a reread is discarded when the session identity changes', (tester) async {
      final harness = _BillingPageHarness(pullSucceeds: true, planFromRead: (_) => null);
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(harness.pulls, 1);

      harness.identity = 'user-2';
      await tester.pump(const Duration(seconds: 30));
      await _flush(tester);
      expect(harness.statusReads, 2, reason: 'no reread is issued for a different session');

      await tester.pump(const Duration(seconds: 90));
      await _flush(tester);
      expect(harness.statusReads, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI2: review F3 a pull reply and rereads after disposal are discarded', (tester) async {
      final harness = _BillingPageHarness(pullSucceeds: true, planFromRead: (_) => null);
      final gate = Completer<void>();
      harness.pullGate = gate;
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(harness.pulls, 1);

      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await _flush(tester);
      await tester.pump(const Duration(seconds: 150));
      await _flush(tester);
      expect(harness.statusReads, 2, reason: 'no reread runs after the billing page is disposed');
      expect(tester.takeException(), isNull);
    });
  });

  group('R7-UI3 commercial notice copy', () {
    testWidgets('R7-UI3: commercial codes map to distinct localized text and unknown codes are neutral', (tester) async {
      final client = _client((request) async {
        if (request.url.path == '/v1/subscription') {
          return http.Response(
            jsonEncode(_subscriptionBody(const [
              'duplicate_payment',
              'payment_withheld',
              'reversal_recorded',
              'terms_held',
              'late_payment_honoured',
              'mystery_code',
            ])),
            200,
          );
        }
        return http.Response('{}', 500);
      });
      await tester.pumpWidget(_app(CommercialNotices(client: client)));
      await _flush(tester);

      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.aiBillingNoticeDuplicatePayment), findsOneWidget);
      expect(find.text(en.aiBillingNoticePaymentWithheld), findsOneWidget);
      expect(find.text(en.aiBillingNoticeReversalRecorded), findsOneWidget);
      expect(find.text(en.aiBillingNoticeTermsHeld), findsOneWidget);
      expect(find.text(en.aiBillingNoticeLatePaymentHonoured), findsOneWidget);
      expect(find.text(en.aiNoticeUnavailable), findsOneWidget);
      expect(find.textContaining('mystery_code'), findsNothing);
      expect(find.text('duplicate_payment'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI3: commercial notices render Arabic text in the Arabic locale', (tester) async {
      final client = _client((request) async {
        if (request.url.path == '/v1/subscription') {
          return http.Response(jsonEncode(_subscriptionBody(const ['payment_withheld'])), 200);
        }
        return http.Response('{}', 500);
      });
      await tester.pumpWidget(_app(CommercialNotices(client: client), locale: const Locale('ar')));
      await _flush(tester);

      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(ar.aiBillingNoticePaymentWithheld), findsOneWidget);
      expect(find.text('payment_withheld'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('R7-UI3: review F1 ended_reversed notice shows its localized administrator text', (tester) async {
      final client = _client((request) async {
        if (request.url.path == '/v1/subscription') {
          return http.Response(jsonEncode(_subscriptionBody(const ['ended_reversed'])), 200);
        }
        return http.Response('{}', 500);
      });
      await tester.pumpWidget(_app(CommercialNotices(client: client)));
      await _flush(tester);

      final en = lookupAppLocalizations(const Locale('en'));
      expect(find.text(en.aiNoticeEndedReversedAdmin), findsOneWidget);
      expect(find.text(en.aiNoticeUnavailable), findsNothing);
      expect(find.text('ended_reversed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// Drives [AdministratorBillingPage] through an Active checkout with injected clients and RPC.
class _BillingPageHarness {
  _BillingPageHarness({required this.pullSucceeds, required this.planFromRead, this.endsAtFromRead});

  final bool pullSucceeds;

  /// Returns the plan name for the nth `get_ai_billing_status` read, or null when not projected.
  final String? Function(int reads)? planFromRead;

  /// Returns the `ends_at` value for the nth status read, or null.
  final String? Function(int reads)? endsAtFromRead;

  /// Session identity reported to the page (review F3).
  String? identity = 'user-1';

  /// When set, the pull reply waits for this completer (review F3, F5).
  Completer<void>? pullGate;

  int statusReads = 0;
  int pulls = 0;
  var _checkoutReads = 0;

  Future<void> pump(WidgetTester tester) async {
    final tokenClient = BillingTokenClient.withRpc(rpc: (_, __) async => _tokenReply());
    final client = _client((request) async {
      switch (request.url.path) {
        case '/v1/checkouts':
          _checkoutReads++;
          final state = _checkoutReads == 1 ? 'Waiting' : 'Active';
          return http.Response(
            jsonEncode({
              'contract_version': 1,
              'checkouts': [_checkoutBody(state)],
            }),
            200,
          );
        case '/v1/subscription':
          return http.Response(jsonEncode(_subscriptionBody(const [])), 200);
        case '/v1/payments':
          return http.Response(_paymentsBody(const [], hasMore: false, nextCursor: ''), 200);
        default:
          return http.Response('{}', 500);
      }
    }, tokenClient: tokenClient);

    Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
      if (name == 'get_ai_billing_status') {
        statusReads++;
        final plan = planFromRead?.call(statusReads);
        return _statusReply(plan, endsAt: endsAtFromRead?.call(statusReads));
      }
      if (name == 'request_ai_status_refresh') {
        pulls++;
        await pullGate?.future;
        return pullSucceeds
            ? {'success': true, 'contract_version': backendRpc, 'data': null}
            : {
                'success': false,
                'contract_version': backendRpc,
                'error_code': 'UNAVAILABLE',
                'error_message': 'down',
                'data': null,
              };
      }
      return {'success': false, 'contract_version': backendRpc, 'data': null};
    }

    await tester.pumpWidget(_app(AdministratorBillingPage(
      tokenClient: tokenClient,
      aboClient: client,
      rpc: rpc,
      identityProbe: () => identity,
    )));
    await _flush(tester);
  }
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

BillingTokenClient _tokenClient() => BillingTokenClient.withRpc(rpc: (_, __) async => _tokenReply());

Map<String, dynamic> _tokenReply() => {
      'success': true,
      'contract_version': backendRpc,
      'data': {
        'token': 'test-token',
        'abo_base_url': 'https://abo.example',
        'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
      },
    };

AboClient _client(
  Future<http.Response> Function(http.Request) handler, {
  BillingTokenClient? tokenClient,
}) {
  return AboClient(
    tokenClient: tokenClient ?? _tokenClient(),
    httpClient: MockClient((request) async {
      final response = await handler(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return response;
      }
      // R2-C3: every successful ABO reply echoes the sent Abo-Contract-Version header.
      return http.Response(
        response.body,
        response.statusCode,
        headers: {...response.headers, 'abo-contract-version': '1'},
      );
    }),
  );
}

http.Response _subscriptionResponse(List<String> notices) =>
    http.Response(jsonEncode(_subscriptionBody(notices)), 200);

Map<String, dynamic> _subscriptionBody(List<String> notices) => {
      'contract_version': 1,
      'subscription_ref': 'AIC-TEST1234',
      'snapshot': null,
      'notices': notices,
    };

Map<String, dynamic> _statusReply(String? plan, {String? endsAt}) => {
      'success': true,
      'contract_version': backendRpc,
      'data': {
        'plan_display_name': plan,
        'notices': <dynamic>[],
        'starts_at': null,
        'ends_at': endsAt,
        'grace_ends_at': null,
        'allowance': null,
        'used': null,
        'queued_count': null,
        'held_count': null,
        'subscription_ref': null,
      },
    };

Map<String, dynamic> _checkoutBody(String state) => {
      'contract_version': 1,
      'reference': 'CK-TEST',
      'shown_state': state,
      'offer': {
        'offer_id': 'plan-1',
        'version': 1,
        'term_unit': 'month',
        'term_count': 1,
        'charged_price_minor': 10000,
        'currency': 'EGP',
      },
      'payment_reference': null,
      'term_ref': null,
      'updated_at': '2026-10-22T10:00:00Z',
    };

String _paymentsBody(List<String> references, {required bool hasMore, required String nextCursor}) {
  return jsonEncode({
    'contract_version': 1,
    'payments': [
      for (final reference in references)
        {
          'reference': reference,
          'paid_at': '2026-10-01T10:00:00Z',
          'amount_minor': 10000,
          'currency': 'EGP',
          'plan_display_name': 'Plan',
          'offer_version': 1,
          'term_unit': 'month',
          'term_count': 1,
          'classification': 'normal',
          'reversals': <dynamic>[],
        },
    ],
    'next_cursor': nextCursor,
    'has_more': hasMore,
  });
}
