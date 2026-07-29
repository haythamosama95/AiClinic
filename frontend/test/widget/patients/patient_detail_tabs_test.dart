import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
import 'package:ai_clinic/core/ui/components/app_error_state.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/billing/data/invoice_repository.dart';
import 'package:ai_clinic/features/billing/presentation/providers/invoice_detail_provider.dart';
import 'package:ai_clinic/features/billing/domain/invoice_list_item.dart';
import 'package:ai_clinic/features/billing/domain/invoice_status.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/patients/domain/patient_visit_document.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_document_card.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_invoice_card.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

import '../../helpers/role_permission_seed.dart';
import 'patients_widget_test_harness.dart';

const _visitId = 'visit-detail-tab-001';
const _appointmentId = 'appointment-detail-tab-001';
const _invoiceId = 'invoice-detail-tab-001';

Future<void> _pumpPatientDetailPage(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Set<String>? permissions,
}) async {
  await pumpPatientsSurface(
    tester,
    child: const PatientDetailPage(patientId: patientsTestPatientId),
    overrides: overrides.isEmpty
        ? patientsProviderOverrides(patientId: patientsTestPatientId)
        : overrides,
    permissions: permissions,
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) {
  return AppLocalizations.of(
    tester.element(find.byType(MaterialApp)),
  )!;
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

VisitListItem _sampleVisit() {
  return VisitListItem(
    id: _visitId,
    visitDate: DateTime.utc(2026, 3, 10),
    doctorName: 'Dr. Smith',
    status: VisitStatus.completed,
    branchName: 'Branch A',
  );
}

AppointmentListItem _sampleAppointment() {
  return AppointmentListItem(
    id: _appointmentId,
    patientId: patientsTestPatientId,
    patientName: 'Test Patient',
    doctorName: 'Dr. Ada',
    startTime: DateTime.utc(2026, 6, 15, 10),
    endTime: DateTime.utc(2026, 6, 15, 10, 30),
    type: AppointmentType.planned,
    status: AppointmentStatus.scheduled,
  );
}

PatientVisitDocument _sampleDocument() {
  return PatientVisitDocument(
    visitId: 'visit-doc-001',
    visitDate: DateTime.utc(2026, 3, 10),
    attachment: VisitAttachmentItem(
      id: 'attachment-detail-tab-001',
      fileType: VisitAttachmentFileType.pdf,
      label: 'lab-report.pdf',
      uploadedBy: 'user-1',
      sizeBytes: 2048,
      createdAt: DateTime.utc(2026, 3, 10),
      canDownload: true,
      canDelete: false,
    ),
  );
}

InvoiceListItem _sampleInvoice() {
  return InvoiceListItem(
    id: _invoiceId,
    status: InvoiceStatus.issued,
    subtotal: Money.parse('120.00'),
    discountAmount: Money.zero,
    insuranceCoveredAmount: Money.zero,
    paidAmount: Money.zero,
    balance: Money.parse('120.00'),
    createdAt: DateTime.utc(2026, 6, 1),
    currency: 'USD',
    invoiceNumber: 'INV-DETAIL-001',
  );
}

void main() {
  group('PatientDetailPage tabs', () {
    testWidgets('trivial: visits, documents, and billing tabs are present and switchable', (tester) async {
      await _pumpPatientDetailPage(
        tester,
        overrides: patientsProviderOverrides(
          patientId: patientsTestPatientId,
          pastVisits: [_sampleVisit()],
          visitDocuments: [_sampleDocument()],
          patientInvoices: InvoiceListPageResult(
            items: [_sampleInvoice()],
            hasMore: false,
          ),
        ),
      );

      final l10n = _l10n(tester);

      expect(find.text(l10n.visits), findsOneWidget);
      expect(find.text(l10n.documents), findsOneWidget);
      expect(find.text(l10n.billing), findsOneWidget);

      expect(find.byKey(const ValueKey('visit-$_visitId')), findsOneWidget);

      await _selectTab(tester, l10n.documents);
      expect(find.byType(PatientDocumentCard), findsOneWidget);
      expect(find.text('lab-report.pdf'), findsOneWidget);

      await _selectTab(tester, l10n.billing);
      expect(find.byType(PatientInvoiceCard), findsOneWidget);
      expect(find.text('INV-DETAIL-001'), findsOneWidget);

      await _selectTab(tester, l10n.visits);
      expect(find.byKey(const ValueKey('visit-$_visitId')), findsOneWidget);
    });

    group('Visits tab', () {
      testWidgets('trivial: loading shows skeleton affordances', (tester) async {
        await pumpPatientsSurface(
          tester,
          child: const PatientDetailPage(patientId: patientsTestPatientId),
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            extraOverrides: [
              patientPastVisitsProvider(patientsTestPatientId).overrideWith(
                (ref) => Completer<List<VisitListItem>>().future,
              ),
            ],
          ),
        );
        await tester.pump();

        expect(find.byType(AppSkeleton), findsWidgets);
      });

      testWidgets('advanced: error shows message surface', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            extraOverrides: [
              patientPastVisitsProvider(patientsTestPatientId).overrideWith(
                (ref) async => throw StateError('Visits failed'),
              ),
            ],
          ),
        );

        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Visits failed'), findsOneWidget);
      });

      testWidgets('trivial: empty state shows no visits yet', (tester) async {
        await _pumpPatientDetailPage(tester);

        final l10n = _l10n(tester);

        expect(find.text(l10n.noVisitsYet), findsOneWidget);
        expect(find.text(l10n.noVisitsYetDescription), findsOneWidget);
        expect(find.byType(AppEmptyState), findsOneWidget);
      });

      testWidgets('trivial: success renders visit and appointment record cards', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            pastVisits: [_sampleVisit()],
            upcomingAppointments: [_sampleAppointment()],
          ),
        );

        expect(find.byKey(const ValueKey('visit-$_visitId')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('appointment-$_appointmentId')),
          findsOneWidget,
        );
      });
    });

    group('Documents tab', () {
      Future<void> openDocumentsTab(WidgetTester tester) async {
        await _selectTab(tester, _l10n(tester).documents);
      }

      testWidgets('trivial: loading shows skeleton affordances', (tester) async {
        await pumpPatientsSurface(
          tester,
          child: const PatientDetailPage(patientId: patientsTestPatientId),
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            extraOverrides: [
              patientVisitDocumentsProvider(patientsTestPatientId).overrideWith(
                (ref) => Completer<List<PatientVisitDocument>>().future,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await openDocumentsTab(tester);

        expect(find.byType(AppSkeleton), findsWidgets);
      });

      testWidgets('advanced: error shows message surface', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            extraOverrides: [
              patientVisitDocumentsProvider(patientsTestPatientId).overrideWith(
                (ref) async => throw StateError('Documents failed'),
              ),
            ],
          ),
        );
        await openDocumentsTab(tester);

        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Documents failed'), findsOneWidget);
      });

      testWidgets('trivial: empty state shows no documents', (tester) async {
        await _pumpPatientDetailPage(tester);
        await openDocumentsTab(tester);

        final l10n = _l10n(tester);

        expect(find.text(l10n.noDocuments), findsOneWidget);
        expect(find.text(l10n.noDocumentsDescription), findsOneWidget);
      });

      testWidgets('trivial: success renders document cards', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            visitDocuments: [_sampleDocument()],
          ),
        );
        await openDocumentsTab(tester);

        expect(find.byType(PatientDocumentCard), findsOneWidget);
        expect(find.text('lab-report.pdf'), findsOneWidget);
      });
    });

    group('Billing tab', () {
      Future<void> openBillingTab(WidgetTester tester) async {
        await _selectTab(tester, _l10n(tester).billing);
      }

      testWidgets('trivial: loading shows skeleton affordances', (tester) async {
        await pumpPatientsSurface(
          tester,
          child: const PatientDetailPage(patientId: patientsTestPatientId),
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            extraOverrides: [
              patientInvoicesProvider(patientsTestPatientId).overrideWith(
                (ref) => Completer<InvoiceListPageResult>().future,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await openBillingTab(tester);

        expect(find.byType(AppSkeleton), findsWidgets);
      });

      testWidgets('advanced: error shows message surface', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            extraOverrides: [
              patientInvoicesProvider(patientsTestPatientId).overrideWith(
                (ref) async => throw StateError('Billing failed'),
              ),
            ],
          ),
        );
        await openBillingTab(tester);

        expect(find.byType(AppErrorState), findsOneWidget);
        expect(find.text('Billing failed'), findsOneWidget);
      });

      testWidgets('trivial: empty state shows no invoices', (tester) async {
        await _pumpPatientDetailPage(tester);
        await openBillingTab(tester);

        final l10n = _l10n(tester);

        expect(find.text(l10n.noInvoices), findsOneWidget);
        expect(find.text(l10n.noInvoicesDescription), findsOneWidget);
      });

      testWidgets('trivial: success renders invoice cards', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            patientInvoices: InvoiceListPageResult(
              items: [_sampleInvoice()],
              hasMore: false,
            ),
          ),
        );
        await openBillingTab(tester);

        expect(find.byType(PatientInvoiceCard), findsOneWidget);
        expect(find.text('INV-DETAIL-001'), findsOneWidget);
      });

      testWidgets('edge case: no billing permission shows access message', (tester) async {
        await _pumpPatientDetailPage(
          tester,
          permissions: RolePermissionSeed.doctor,
          overrides: patientsProviderOverrides(
            patientId: patientsTestPatientId,
            auth: patientsAuthSession(permissions: RolePermissionSeed.doctor),
            patientInvoices: InvoiceListPageResult(
              items: [_sampleInvoice()],
              hasMore: false,
            ),
          ),
        );
        await openBillingTab(tester);

        final l10n = _l10n(tester);

        expect(find.text(l10n.billingNoAccess), findsOneWidget);
        expect(find.byType(PatientInvoiceCard), findsNothing);
      });
    });
  });
}
