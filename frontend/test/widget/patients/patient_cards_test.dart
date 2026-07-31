import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/billing/presentation/providers/organization_currency_provider.dart';
import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_branch_pill.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_date_stamp.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_document_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_invoice_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_notes_dialog.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_record_grid.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_visit_record_card.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_service.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../support/visit_rpc_test_client.dart';
import 'patients_widget_test_harness.dart';

const _invoiceId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _SpyVisitAttachmentService extends VisitAttachmentService {
  _SpyVisitAttachmentService()
      : super(_FakeSupabaseClient(), VisitRepository(VisitRpcTestClient()));

  var downloadCallCount = 0;
  String? lastAttachmentId;

  @override
  Future<void> downloadAndOpen({
    required String attachmentId,
    required VisitAttachmentFileType fileType,
    String? preferredName,
    http.Client? client,
  }) async {
    downloadCallCount++;
    lastAttachmentId = attachmentId;
  }
}

VisitAttachmentItem _downloadableAttachment({bool canDownload = true}) {
  return VisitAttachmentItem(
    id: 'attachment-1',
    fileType: VisitAttachmentFileType.pdf,
    label: 'lab-results.pdf',
    uploadedBy: 'user-1',
    sizeBytes: 2048,
    createdAt: DateTime.utc(2026, 1, 15),
    canDownload: canDownload,
    canDelete: false,
  );
}

PatientVisitDocument _document({required VisitAttachmentItem attachment}) {
  return PatientVisitDocument(
    visitId: 'visit-1',
    visitDate: DateTime.utc(2026, 3, 10),
    attachment: attachment,
  );
}

InvoiceListItem _invoice() {
  return InvoiceListItem(
    id: _invoiceId,
    invoiceNumber: 'INV-000123',
    status: InvoiceStatus.issued,
    patientDisplayName: 'Test Patient',
    patientId: patientsTestPatientId,
    branchId: 'branch-a',
    branchCode: 'MAIN',
    subtotal: Money.parse('100.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    paidAmount: Money.zero,
    balance: Money.parse('100.00'),
    createdAt: DateTime.utc(2026, 6, 2, 10),
    issuedAt: DateTime.utc(2026, 6, 2, 11),
    currency: 'USD',
  );
}

Future<void> _pumpMaterial(
  WidgetTester tester, {
  required Widget child,
  List<Override> overrides = const [],
}) async {
  if (find.byType(MaterialApp).evaluate().isNotEmpty) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('PatientVisitRecordCard', () {
    testWidgets('trivial: fromVisit renders doctor, badges, and branch pill', (tester) async {
      final visit = VisitListItem(
        id: 'visit-1',
        visitDate: DateTime.utc(2026, 5, 12),
        doctorName: 'Dr. Nadia Farouk',
        status: VisitStatus.completed,
        branchName: 'Main Clinic',
      );

      await _pumpMaterial(
        tester,
        child: PatientVisitRecordCard.fromVisit(visit),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dr. Nadia Farouk'), findsOneWidget);
      expect(find.text(AppointmentType.planned.label), findsOneWidget);
      expect(find.text(VisitStatus.completed.label), findsOneWidget);
      expect(find.text('Main Clinic'), findsOneWidget);
      expect(find.byType(PatientBranchPill), findsOneWidget);
    });

    testWidgets('trivial: fromAppointment renders doctor, badges, and branch pill', (tester) async {
      final appointment = AppointmentListItem(
        id: 'appt-1',
        patientId: patientsTestPatientId,
        patientName: 'Test Patient',
        doctorName: 'Dr. Omar Saleh',
        startTime: DateTime.utc(2026, 6, 1, 9),
        endTime: DateTime.utc(2026, 6, 1, 9, 30),
        type: AppointmentType.planned,
        status: AppointmentStatus.confirmed,
      );

      await _pumpMaterial(
        tester,
        child: PatientVisitRecordCard.fromAppointment(
          appointment,
          branchName: 'North Branch',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dr. Omar Saleh'), findsOneWidget);
      expect(find.text(AppointmentType.planned.label), findsOneWidget);
      expect(find.text(AppointmentStatus.confirmed.label), findsOneWidget);
      expect(find.text('North Branch'), findsOneWidget);
    });
  });

  group('PatientDocumentCard', () {
    testWidgets('trivial: renders document info', (tester) async {
      final document = _document(attachment: _downloadableAttachment());

      await _pumpMaterial(tester, child: PatientDocumentCard(document: document));
      await tester.pumpAndSettle();

      expect(find.text('Patient file'), findsOneWidget);
      expect(find.text('lab-results.pdf'), findsOneWidget);
      expect(find.text('Linked visit'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('advanced: download action appears only when downloadable', (tester) async {
      final downloadable = _document(attachment: _downloadableAttachment());
      final locked = _document(
        attachment: _downloadableAttachment(canDownload: false),
      );
      final attachmentService = _SpyVisitAttachmentService();

      await _pumpMaterial(
        tester,
        child: PatientDocumentCard(document: downloadable),
        overrides: [
          visitAttachmentServiceProvider.overrideWithValue(attachmentService),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'Download file'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Download file'));
      await tester.pumpAndSettle();

      expect(attachmentService.downloadCallCount, 1);
      expect(attachmentService.lastAttachmentId, 'attachment-1');

      await _pumpMaterial(tester, child: PatientDocumentCard(document: locked));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppButton, 'Download file'), findsNothing);
    });
  });

  group('PatientInvoiceCard', () {
    testWidgets('advanced: tapping navigates to invoice detail route', (tester) async {
      final navigationLog = PatientsTestNavigationLog();

      await pumpPatientsRouter(
        tester,
        navigationLog: navigationLog,
        home: PatientInvoiceCard(invoice: _invoice()),
        overrides: patientsProviderOverrides(
          extraOverrides: [
            organizationCurrencyProvider.overrideWith((ref) => 'USD'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('INV-000123'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PatientInvoiceCard),
          matching: find.widgetWithText(AppBadge, InvoiceStatus.issued.label),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('INV-000123'));
      await tester.pumpAndSettle();

      expect(
        navigationLog.visitedLocations,
        contains(AppRoutes.billingInvoiceDetail(_invoiceId)),
      );
    });
  });

  group('PatientNotesDialog', () {
    testWidgets('trivial: displays supplied notes text', (tester) async {
      const notes = 'Patient reports mild seasonal allergies.';

      await pumpPatientsDialogShell(
        tester,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => PatientNotesDialog.show(context, notes: notes),
            child: const Text('Open notes'),
          ),
        ),
      );
      await pumpPatientsFrames(tester);

      await tester.tap(find.text('Open notes'));
      await pumpPatientsFrames(tester);

      expect(find.text('Clinical notes'), findsOneWidget);
      expect(
        find.text('Optional context visible to staff on the patient profile.'),
        findsOneWidget,
      );
      expect(find.text(notes), findsOneWidget);
    });
  });

  group('PatientBranchPill', () {
    testWidgets('trivial: renders branch name', (tester) async {
      await _pumpMaterial(
        tester,
        child: const PatientBranchPill(branchName: 'Downtown Clinic'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Downtown Clinic'), findsOneWidget);
    });
  });

  group('PatientDateStamp', () {
    testWidgets('trivial: renders formatted date parts', (tester) async {
      final date = DateTime.utc(2026, 3, 15);

      await _pumpMaterial(tester, child: PatientDateStamp(date: date));
      await tester.pumpAndSettle();

      expect(find.text(DateFormat('d').format(date)), findsOneWidget);
      expect(find.text(DateFormat.MMM().format(date).toUpperCase()), findsOneWidget);
      expect(find.text(DateFormat('y').format(date)), findsOneWidget);
    });

    testWidgets('edge case: compact omits year and showWeekday adds weekday text', (tester) async {
      final date = DateTime.utc(2026, 3, 15);

      await _pumpMaterial(
        tester,
        child: PatientDateStamp(date: date, compact: true),
      );
      await tester.pumpAndSettle();

      expect(find.text(DateFormat('y').format(date)), findsNothing);

      await _pumpMaterial(
        tester,
        child: PatientDateStamp(date: date, showWeekday: true),
      );
      await tester.pumpAndSettle();

      expect(find.text(DateFormat.EEEE().format(date)), findsOneWidget);
    });
  });

  group('PatientRecordCard', () {
    testWidgets('trivial: renders child and optional leading widget', (tester) async {
      await _pumpMaterial(
        tester,
        child: PatientRecordCard(
          leading: const Text('Leading'),
          child: const Text('Record body'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Leading'), findsOneWidget);
      expect(find.text('Record body'), findsOneWidget);
    });
  });

  group('PatientRecordGrid', () {
    testWidgets('trivial: renders all children after stagger timers', (tester) async {
      await _pumpMaterial(
        tester,
        child: PatientRecordGrid(
          children: const [
            Text('Card one'),
            Text('Card two'),
            Text('Card three'),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Card one'), findsOneWidget);
      expect(find.text('Card two'), findsOneWidget);
      expect(find.text('Card three'), findsOneWidget);
    });
  });
}
