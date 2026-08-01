import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_config.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_row.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceBranchRow.fromRow', () {
    test('parses required and optional fields', () {
      final row = ServiceBranchRow.fromRow({
        'service_branch_id': 'sb-1',
        'branch_id': 'branch-1',
        'status': 'active',
        'price_override': '150.00',
        'promotion_price': '100.00',
        'promotion_start_date': '2026-01-01',
        'promotion_end_date': '2026-01-31',
        'updated_at': '2026-01-01T10:00:00.000Z',
      });

      expect(row, isNotNull);
      expect(row!.priceOverride, '150.00');
      expect(row.promotionPrice, '100.00');
      expect(row.updatedAt, isNotNull);
    });

    test('treats empty optional strings as null', () {
      final row = ServiceBranchRow.fromRow({
        'service_branch_id': 'sb-1',
        'branch_id': 'branch-1',
        'status': 'active',
        'price_override': '   ',
        'promotion_price': '',
      });

      expect(row?.priceOverride, isNull);
      expect(row?.promotionPrice, isNull);
    });

    test('returns null when required fields are missing', () {
      expect(ServiceBranchRow.fromRow({'service_branch_id': 'sb-1'}), isNull);
    });
  });

  group('ServiceBranchConfig', () {
    final branchRow = ServiceBranchRow.fromRow({
      'service_branch_id': 'sb-1',
      'branch_id': 'branch-1',
      'status': 'active',
      'price_override': '150.00',
      'promotion_price': '100.00',
      'promotion_start_date': '2026-01-01',
      'promotion_end_date': '2026-01-31',
      'updated_at': '2026-01-01T10:00:00.000Z',
    })!;

    test('fromRow maps row to config', () {
      final config = ServiceBranchConfig.fromRow(branchRow, branchName: 'Main');

      expect(config.branchId, 'branch-1');
      expect(config.isActive, isTrue);
      expect(config.priceOverride, Money.parse('150.00'));
      expect(config.promotion, isNotNull);
      expect(config.branchName, 'Main');
    });

    test('fromPending maps draft configuration', () {
      final config = ServiceBranchConfig.fromPending(
        const PendingBranchConfiguration(
          branchId: 'branch-1',
          branchName: 'Main',
          active: false,
          priceOverride: '120.00',
        ),
      );

      expect(config.isActive, isFalse);
      expect(config.serviceBranchId, 'draft-branch-1');
      expect(config.priceOverride, Money.parse('120.00'));
    });

    test('copyWith clears override and promotion', () {
      final config = ServiceBranchConfig.fromRow(branchRow);
      final cleared = config.copyWith(clearPriceOverride: true, clearPromotion: true, status: 'inactive');

      expect(cleared.priceOverride, isNull);
      expect(cleared.promotion, isNull);
      expect(cleared.isActive, isFalse);
    });
  });

  group('PendingBranchConfiguration', () {
    test('detects branch settings and promotion changes', () {
      const inactive = PendingBranchConfiguration(branchId: 'branch-1', active: false);
      expect(inactive.hasBranchSettingsChange, isTrue);
      expect(inactive.hasPromotion, isFalse);

      const overrideOnly = PendingBranchConfiguration(branchId: 'branch-1', priceOverride: '100.00');
      expect(overrideOnly.hasBranchSettingsChange, isTrue);

      final withPromotion = PendingBranchConfiguration(
        branchId: 'branch-1',
        promotion: ServicePromotion(
          price: Money.parse('90.00'),
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 31),
        ),
      );
      expect(withPromotion.hasPromotion, isTrue);
    });

    test('copyWith updates fields', () {
      const original = PendingBranchConfiguration(branchId: 'branch-1', active: true);
      final updated = original.copyWith(active: false, clearPromotion: true);

      expect(updated.active, isFalse);
      expect(updated.promotion, isNull);
    });
  });
}
