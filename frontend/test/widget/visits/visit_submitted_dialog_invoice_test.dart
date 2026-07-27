import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/locale_provider.dart';
import 'package:ai_clinic/core/money/money.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_window_facade.dart';
import 'package:ai_clinic/features/billing/domain/invoice_detail.dart';
import 'package:ai_clinic/features/billing/domain/invoice_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_summary_facade.dart';
import 'package:ai_clinic/features/setup/presentation/providers/branch_name_facade.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submitted_dialog.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import '../../support/visit_encounter_test_support.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';

void main() {
  group('VisitSubmittedDialog.showForVisit invoice summary', () {
    testWidgets('renders invoice details when appointment resolves successfully', (tester) async {
      await _pumpDialog(
        tester,
        appointmentWindow: AppointmentWindow(
          startTime: DateTime.utc(2026, 5, 31, 9),
          endTime: DateTime.utc(2026, 5, 31, 9, 30),
          breadcrumbLabel: 'Jane Doe · May 31, 2026',
        ),
      );

      expect(find.text('INV-20260727-0001'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
    });

    testWidgets('renders invoice details when appointment lookup fails', (tester) async {
      await _pumpDialog(tester, appointmentWindow: null);

      expect(find.text('INV-20260727-0001'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
    });
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required AppointmentWindow? appointmentWindow,
}) async {
  final visit = sampleEncounterVisit();
  final invoice = _sampleInvoice();

  await tester.binding.setSurfaceSize(const Size(900, 1200));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localeProvider.overrideWith(_LocaleHarness.new),
        patientSummaryForVisitProvider.overrideWith(
          (ref, patientId) async => const PatientSummary(fullName: 'Jane Doe'),
        ),
        appointmentWindowProvider.overrideWith(
          (ref, appointmentId) async {
            if (appointmentWindow == null) {
              throw StateError('appointment not found');
            }
            return appointmentWindow;
          },
        ),
        branchNameProvider.overrideWith(
          (ref, branchId) async => 'Main Branch',
        ),
        clinicSetupOrganizationProvider.overrideWith(
          (ref) async => const OrganizationProfile(
            id: 'org-1',
            name: 'Test Clinic',
            currencyCode: 'USD',
            timezone: 'UTC',
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _DialogLauncher(visit: visit, invoice: invoice),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

class _DialogLauncher extends ConsumerStatefulWidget {
  const _DialogLauncher({required this.visit, required this.invoice});

  final VisitDetail visit;
  final InvoiceDetail invoice;

  @override
  ConsumerState<_DialogLauncher> createState() => _DialogLauncherState();
}

class _DialogLauncherState extends ConsumerState<_DialogLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VisitSubmittedDialog.showForVisit(
        context,
        ref,
        visit: widget.visit,
        invoicePreview: null,
        persistedInvoice: widget.invoice,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SizedBox());
  }
}

class _LocaleHarness extends LocaleNotifier {
  @override
  Locale build() => const Locale('en');
}

InvoiceDetail _sampleInvoice() {
  return InvoiceDetail(
    id: 'inv-12345678-abcd-efgh-ijkl-mnopqrstuvwx',
    invoiceNumber: 'INV-20260727-0001',
    status: InvoiceStatus.issued,
    branchId: encounterTestBranchId,
    patientId: encounterTestPatientId,
    visitId: encounterTestVisitId,
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    currency: 'USD',
    balance: Money.parse('100.00'),
    createdAt: DateTime.utc(2026, 7, 27),
    updatedAt: DateTime.utc(2026, 7, 27),
    items: [
      InvoiceItem(
        id: 'item-1',
        description: 'Consultation',
        quantity: '1',
        unitPrice: Money.parse('100.00'),
        lineSubtotal: Money.parse('100.00'),
        lineDiscountAmount: Money.zero,
        lineTotal: Money.parse('100.00'),
      ),
    ],
    payments: [],
  );
}
