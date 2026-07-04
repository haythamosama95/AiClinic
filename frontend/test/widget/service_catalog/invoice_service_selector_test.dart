import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/eligible_service.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_selector_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/invoice_service_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('InvoiceServiceSelector', () {
    testWidgets('shows eligible services with price and promotion badge', (tester) async {
      final rpcClient = _SelectorRpcClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient))],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: InvoiceServiceSelector(
                branchId: 'branch-1',
                currency: 'USD',
                enabled: true,
                onServiceSelected: (_) async {},
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byKey(const Key('invoice_service_selector_field')), 'Con');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('\$120.00'), findsOneWidget);
      expect(find.text('On promotion'), findsOneWidget);
    });
  });
}

class _SelectorRpcClient extends RpcCaptureSupabaseClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    return FakePostgrestRpc({
          'success': true,
          'data': {
            'items': [
              {
                'service_id': 'svc-1',
                'name': 'Consultation',
                'unit_price': '120.00',
                'applied_rule': 'promo',
                'on_promotion': true,
              },
            ],
          },
        })
        as PostgrestFilterBuilder<T>;
  }
}
