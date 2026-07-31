import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/billing/domain/visit_billing_models.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/visit_billing/visit_invoice_summary_panel.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_combined_confirmation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_confirmation_data.dart';

import 'visit_widget_test_harness.dart';

VisitSubmittedConfirmationData _confirmationData({
  VisitConfirmationKind kind = VisitConfirmationKind.completed,
  String patientName = 'Jane Doe',
  String branchName = 'Main Branch',
  DateTime? actionAt,
  VisitBillingInvoicePreview? invoicePreview,
}) {
  final visit = sampleEncounterVisit(doctorName: 'Dr Test');
  final start = DateTime.utc(2026, 5, 31, 9);
  final end = DateTime.utc(2026, 5, 31, 9, 30);
  return VisitSubmittedConfirmationData.fromVisit(
    visit: visit,
    patientName: patientName,
    branchName: branchName,
    appointmentStart: start,
    appointmentEnd: end,
    kind: kind,
    actionAt: actionAt ?? DateTime.utc(2026, 5, 31, 10, 15),
    invoicePreview: invoicePreview,
  );
}

Future<void> _pumpConfirmation(
  WidgetTester tester, {
  required VisitSubmittedConfirmationData data,
  List<Override> overrides = const [],
}) async {
  await pumpVisitsSurface(
    tester,
    overrides: [
      organizationCurrencyProvider.overrideWith((ref) => 'USD'),
      ...overrides,
    ],
    child: VisitSubmittedCombinedConfirmation(data: data),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

VisitBillingInvoicePreview _invoicePreview() {
  return const VisitBillingInvoicePreview(
    number: 'INV-PREVIEW-0001',
    lines: [
      VisitSelectedServiceLine(
        id: 'line-1',
        serviceId: 'svc-1',
        name: 'Consultation',
        unitPrice: 100,
        quantity: 1,
      ),
    ],
    discountType: VisitBillingDiscountType.none,
    discountValue: 0,
    subtotal: 100,
    discountAmount: 0,
    total: 100,
  );
}

void main() {
  group('VisitSubmittedCombinedConfirmation — VisitConfirmationKind.completed', () {
    testWidgets('trivial: renders title, body, filing reference, and visit details grid', (tester) async {
      final data = _confirmationData();
      await _pumpConfirmation(tester, data: data);

      expect(find.text('Visit completed'), findsOneWidget);
      expect(find.textContaining('The visit for'), findsOneWidget);
      expect(find.text('Jane Doe'), findsWidgets);
      expect(find.text('Filing reference'), findsOneWidget);
      expect(find.text(data.filingReference), findsOneWidget);
      expect(find.text('Visit details'), findsOneWidget);
      expect(find.text('Doctor'), findsOneWidget);
      expect(find.text('Dr Test'), findsOneWidget);
      expect(find.text('Branch'), findsWidgets);
      expect(find.text('Main Branch'), findsOneWidget);
      expect(find.text('Appointment'), findsOneWidget);
      expect(find.text('Visit date'), findsOneWidget);
      expect(find.text('Record locked · available in patient chart'), findsOneWidget);
      expect(find.text('Filed'), findsWidgets);
    });

    testWidgets('regression: filing reference matches formatVisitFilingReference output', (tester) async {
      final visit = sampleEncounterVisit();
      final data = _confirmationData();
      final expected = formatVisitFilingReference(visit);

      await _pumpConfirmation(tester, data: data);

      expect(find.text(expected), findsOneWidget);
      expect(expected, startsWith('ENC-2026-0531-'));
      expect(expected.endsWith('EEEE'), isTrue);
    });
  });

  group('VisitSubmittedCombinedConfirmation — VisitConfirmationKind.edited', () {
    testWidgets('trivial: renders edited copy and visit reference label', (tester) async {
      final data = _confirmationData(kind: VisitConfirmationKind.edited);
      await _pumpConfirmation(tester, data: data);

      expect(find.text('Changes saved'), findsOneWidget);
      expect(find.textContaining('Documentation for'), findsOneWidget);
      expect(find.text('Visit reference'), findsOneWidget);
      expect(find.text('Updated'), findsWidgets);
      expect(find.text('Record updated · available in patient chart'), findsOneWidget);
    });
  });

  group('VisitSubmittedCombinedConfirmation — optional data', () {
    testWidgets('edge case: builds without invoice preview', (tester) async {
      final data = _confirmationData();
      await _pumpConfirmation(tester, data: data);

      expect(find.byType(VisitInvoiceSummaryPanel), findsNothing);
      expect(find.byType(VisitSubmittedCombinedConfirmation), findsOneWidget);
    });

    testWidgets('advanced: renders invoice preview panel when provided', (tester) async {
      final data = _confirmationData(invoicePreview: _invoicePreview());
      await _pumpConfirmation(tester, data: data);

      expect(find.byType(VisitInvoiceSummaryPanel), findsOneWidget);
      expect(find.text('INV-PREVIEW-0001'), findsOneWidget);
    });

    testWidgets('edge case: handles missing branch match without throwing', (tester) async {
      final data = _confirmationData(branchName: 'Branch');
      await _pumpConfirmation(tester, data: data);

      expect(find.text('Branch'), findsWidgets);
      expect(find.byType(VisitSubmittedCombinedConfirmation), findsOneWidget);
    });
  });

  group('VisitSubmittedCombinedConfirmation — timestamps', () {
    testWidgets('advanced: shows Filed timestamp from actionAt', (tester) async {
      final actionAt = DateTime.utc(2026, 5, 31, 10, 15);
      final data = _confirmationData(actionAt: actionAt);
      await _pumpConfirmation(tester, data: data);

      final filedLabel = 'Filed ${DateFormat('EEEE, MMM d, yyyy · h:mm a').format(actionAt.toLocal())}';
      expect(find.text(filedLabel), findsOneWidget);
    });

    testWidgets('advanced: visit date label uses visitDate', (tester) async {
      final visitDate = DateTime.utc(2026, 5, 31);
      final data = VisitSubmittedConfirmationData(
        patientName: 'Jane Doe',
        doctorName: 'Dr Test',
        visitDate: visitDate,
        appointmentStart: DateTime.utc(2026, 5, 31, 9),
        appointmentEnd: DateTime.utc(2026, 5, 31, 9, 30),
        filingReference: formatVisitFilingReference(sampleEncounterVisit(visitDate: visitDate)),
        branchName: 'Main Branch',
      );
      await _pumpConfirmation(tester, data: data);

      expect(
        find.text(DateFormat('MMM d, yyyy').format(visitDate.toLocal())),
        findsOneWidget,
      );
    });
  });
}
