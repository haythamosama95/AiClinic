import 'dart:convert';

import 'package:ai_clinic/features/ai/billing/abo_client.dart';
import 'package:ai_clinic/features/ai/billing/billing_contact_form.dart';
import 'package:ai_clinic/features/ai/billing/billing_token_client.dart';
import 'package:ai_clinic/features/ai/billing/checkout_screen.dart';
import 'package:ai_clinic/features/ai/billing/offers_screen.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R3-C1 billing layouts', () {
    testWidgets('offers, contact and resumed checkout lay out in an outer scroll view at short and tall sizes', (
      tester,
    ) async {
      final client = _client((request) async {
        if (request.url.path == '/v1/offers') {
          return http.Response(jsonEncode({'contract_version': 1, 'offers': [_offer(1)]}), 200);
        }
        if (request.url.path == '/v1/billing-contact') {
          return http.Response(jsonEncode({'code': 'not_found', 'contract_version': 1}), 404);
        }
        return http.Response('{}', 500);
      });

      for (final size in [const Size(360, 480), const Size(1200, 1000)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(_app(
          SingleChildScrollView(
            child: Column(
              children: [
                OffersScreen(client: client, onContinue: (_) {}),
                BillingContactForm(client: client, onSaved: (_) {}),
                CheckoutScreen(client: client, initialCheckout: _checkoutRead()),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    });
  });

  group('R3-M4 offer recovery selection', () {
    testWidgets('changing the selected offer clears old terms acceptance', (tester) async {
      final selections = <BillingOffersSelection>[];
      final client = _client((_) async => http.Response(
            jsonEncode({
              'contract_version': 1,
              'offers': [_offer(1), _offer(2)],
            }),
            200,
          ));

      await tester.pumpWidget(_app(SingleChildScrollView(
        child: OffersScreen(
          client: client,
          onContinue: selections.add,
        ),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('billing_accept_terms')));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('billing_accept_terms'))).value, isTrue);

      await tester.tap(find.text('Plan 2'));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('billing_accept_terms'))).value, isFalse);
      expect(selections, isEmpty);
      await tester.tap(find.byKey(const Key('billing_accept_terms')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('billing_continue')));
      expect(selections.single.offer.offerId, 'plan-2');
      expect(selections.single.offer.planDisplayName, 'Plan 2');
      expect(selections.single.offer.termCount, 2);
      expect(selections.single.offer.priceMinor, 10000);
      expect(selections.single.offer.allowanceCredits, 2000);
      expect(selections.single.termsVersion, 2);
      expect(selections.single.offer.terms.text, contains('Plan 2 terms'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('superseded checkout returns control to fresh offer selection', (tester) async {
      var unavailableCallbackCount = 0;
      final client = _client((request) async => http.Response(
            jsonEncode({'code': 'offer_unavailable', 'contract_version': 1}),
            409,
          ));

      await tester.pumpWidget(_app(CheckoutScreen(
        client: client,
        offer: BillingOffer.fromJson(_offer(1)),
        termsVersion: 1,
        onOfferUnavailable: () => unavailableCallbackCount++,
      )));
      await tester.tap(find.byKey(const Key('billing_checkout_submit')));
      await tester.pumpAndSettle();

      expect(unavailableCallbackCount, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

AboClient _client(Future<http.Response> Function(http.Request) handler) {
  final tokenClient = BillingTokenClient.withRpc(
    rpc: (_, __) async => {
      'success': true,
      'data': {
        'token': 'test-token',
        'abo_base_url': 'https://abo.example',
        'expires_at': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
      },
    },
  );
  return AboClient(tokenClient: tokenClient, httpClient: MockClient(handler));
}

Map<String, dynamic> _offer(int version) => {
      'offer_id': 'plan-$version',
      'version': version,
      'plan_display_name': 'Plan $version',
      'term_unit': 'month',
      'term_count': version,
      'price_minor': 10000,
      'currency': 'EGP',
      'allowance_credits': 1000 * version,
      'grace_days': 3,
      'copy': {
        'en': {'name': 'Plan $version', 'summary': 'Summary for plan $version'},
      },
      'terms': {
        'version': version,
        'text': List.filled(80, 'Plan $version terms.').join(' '),
      },
    };

CheckoutRead _checkoutRead() => CheckoutRead(
      contractVersion: 1,
      reference: 'CK-TEST',
      shownState: CheckoutShownState.waiting,
      offer: CheckoutOfferSummary(
        offerId: 'plan-1',
        version: 1,
        termUnit: 'month',
        termCount: 1,
        chargedPriceMinor: 10000,
        currency: 'EGP',
      ),
      updatedAt: DateTime.now().toUtc(),
    );
