import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/presentation/models/invoice_list_controls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InvoiceListControls.copyWith', () {
    test('clearing status via null requires clearStatus flag', () {
      const controls = InvoiceListControls(status: InvoiceStatus.issued);

      expect(
        controls.copyWith(status: null).status,
        InvoiceStatus.issued,
        reason: 'nullable copyWith fields must use clearStatus to reset',
      );
      expect(controls.copyWith(clearStatus: true).status, isNull);
    });

    test('replacing status with another value works', () {
      const controls = InvoiceListControls(status: InvoiceStatus.issued);

      expect(
        controls.copyWith(status: InvoiceStatus.paid).status,
        InvoiceStatus.paid,
      );
    });

    test('clearing branch via null requires clearBranch flag', () {
      const controls = InvoiceListControls(branch: 'branch-1');

      expect(
        controls.copyWith(branch: null).branch,
        'branch-1',
        reason: 'nullable copyWith fields must use clearBranch to reset',
      );
      expect(controls.copyWith(clearBranch: true).branch, isNull);
    });
  });
}
