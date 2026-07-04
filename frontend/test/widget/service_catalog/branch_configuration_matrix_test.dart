import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_config.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/branch_configuration_matrix.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/promotion_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BranchConfigurationMatrix', () {
    testWidgets('shows override hint and toggles promotion panel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BranchConfigurationMatrix(
                defaultPrice: Money.parse('200.00'),
                branches: const [
                  ServiceBranchConfig(
                    serviceBranchId: 'sb-1',
                    branchId: 'branch-1',
                    branchName: 'Branch A',
                    status: 'active',
                  ),
                ],
                onConfigureBranch: ({required branch, required active, required priceOverride}) async {},
                onSetPromotion: ({required branch, required price, required startDate, required endDate}) async {},
                onClearPromotion: ({required branch}) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Empty uses default (200.00)'), findsOneWidget);
      expect(find.text('Promotion'), findsOneWidget);
      expect(find.text('Promotion price'), findsNothing);

      await tester.tap(find.text('Promotion'));
      await tester.pumpAndSettle();

      expect(find.text('Promotion price'), findsOneWidget);
    });
  });

  group('PromotionEditor', () {
    testWidgets('validates promotion price and date range', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PromotionEditor(
                effectivePrice: '120.00',
                onSave: ({required price, required startDate, required endDate}) async {},
                onClear: () async {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Set promotion'));
      await tester.pumpAndSettle();

      expect(find.text('Promotion price is required.'), findsOneWidget);
      expect(find.text('Promotion requires both start and end dates.'), findsWidgets);

      await tester.enterText(find.widgetWithText(AppTextField, 'Promotion price'), '150.00');
      await tester.tap(find.text('Set promotion'));
      await tester.pumpAndSettle();

      expect(find.text('Promotion price cannot exceed the effective price.'), findsOneWidget);
    });

    testWidgets('shows expired badge for past promotion', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: PromotionEditor(
              effectivePrice: '120.00',
              initialPromotion: ServicePromotion(
                price: Money.parse('100.00'),
                startDate: DateTime(2020, 1, 1),
                endDate: DateTime(2020, 1, 31),
              ),
              onSave: ({required price, required startDate, required endDate}) async {},
              onClear: () async {},
            ),
          ),
        ),
      );

      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Clear promotion'), findsOneWidget);
    });
  });
}
