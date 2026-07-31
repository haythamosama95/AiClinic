import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_resolver.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/invoice_detail_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/visits/presentation/navigation/visit_route_extra.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/breadcrumb_test_support.dart';

void main() {
  group('BreadcrumbTrailResolver.canonicalFor', () {
    test('hub routes return single segment', () {
      expect(BreadcrumbTrailResolver.canonicalFor(AppRoutes.patients).entries.single.id, 'hub:patients');
      expect(BreadcrumbTrailResolver.canonicalFor(AppRoutes.appointmentsCalendar).entries.single.id, 'hub:calendar');
      expect(BreadcrumbTrailResolver.canonicalFor(AppRoutes.appointmentsQueue).entries.single.id, 'hub:queue');
      expect(BreadcrumbTrailResolver.canonicalFor(AppRoutes.billingInvoices).entries.single.id, 'hub:invoices');
    });

    test('patient detail deep link includes placeholder patient segment', () {
      final trail = BreadcrumbTrailResolver.canonicalFor(AppRoutes.patientDetail('patient-1'));

      expect(trail.entries, hasLength(2));
      expect(trail.entries[0].id, 'hub:patients');
      expect(trail.entries[1].id, 'patient:patient-1');
    });

    test('appointment detail deep link defaults to calendar parent', () {
      final trail = BreadcrumbTrailResolver.canonicalFor(AppRoutes.appointmentDetail('apt-1'));

      expect(trail.entries, hasLength(2));
      expect(trail.entries[0].id, 'hub:calendar');
      expect(trail.entries[1].id, 'appointment:apt-1');
    });

    test('visit document deep link uses weak calendar fallback', () {
      final visitId = 'visit-1';
      final trail = BreadcrumbTrailResolver.canonicalFor(AppRoutes.visitDocument(visitId));

      expect(trail.entries, hasLength(2));
      expect(trail.entries[0].id, 'hub:calendar');
      expect(trail.entries[1].id, 'visit-doc:$visitId');
      expect(trail.isWeakVisitDocumentDefault, isTrue);
    });

    test('invoice detail deep link includes placeholder invoice segment', () {
      final trail = BreadcrumbTrailResolver.canonicalFor(AppRoutes.billingInvoiceDetail('inv-1'));

      expect(trail.entries, hasLength(2));
      expect(trail.entries[0].id, 'hub:invoices');
      expect(trail.entries[1].id, 'invoice:inv-1');
    });
  });

  group('BreadcrumbTrailResolver.fromExtra', () {
    final sampleTrail = BreadcrumbTrail([
      BreadcrumbEntries.hubInvoices(),
      BreadcrumbEntries.invoice('inv-1', number: 'INV-1'),
    ]);

    test('reads trail from typed route extras', () {
      expect(BreadcrumbTrailResolver.fromExtra(PatientDetailRouteExtra(breadcrumbTrail: sampleTrail)), sampleTrail);
      expect(BreadcrumbTrailResolver.fromExtra(AppointmentDetailRouteExtra(breadcrumbTrail: sampleTrail)), sampleTrail);
      expect(BreadcrumbTrailResolver.fromExtra(VisitRouteExtra(breadcrumbTrail: sampleTrail)), sampleTrail);
      expect(BreadcrumbTrailResolver.fromExtra(InvoiceDetailRouteExtra(breadcrumbTrail: sampleTrail)), sampleTrail);
    });

    test('returns null for unrelated payloads', () {
      expect(BreadcrumbTrailResolver.fromExtra(null), isNull);
      expect(BreadcrumbTrailResolver.fromExtra('string'), isNull);
      expect(BreadcrumbTrailResolver.fromExtra(42), isNull);
    });
  });

  group('BreadcrumbTrailResolver.composeInvoiceDetailPushTrail', () {
    test('from invoices list hub prepends pop-capable invoices hub', () {
      final trail = BreadcrumbTrailResolver.composeInvoiceDetailPushTrail(
        parent: BreadcrumbTrail([BreadcrumbEntries.hubInvoices()]),
        invoiceId: 'inv-1',
        invoiceNumber: 'INV-1',
      );

      expect(trail.entries, hasLength(2));
      expect(trail.entries[0].id, 'hub:invoices');
      expect(trail.entries[0].onNavigate, isNotNull);
      expect(trail.entries[1].id, 'invoice:inv-1');
    });

    test('from patient detail inherits patient trail', () {
      final trail = BreadcrumbTrailResolver.composeInvoiceDetailPushTrail(
        parent: patientDetailTrail(patientId: 'patient-1', patientName: 'Layla Hassan'),
        invoiceId: 'inv-1',
        invoiceNumber: 'INV-1',
      );

      expect(trail.entries, hasLength(3));
      expect(trail.entries[0].id, 'hub:patients');
      expect(trail.entries[1].id, 'patient:patient-1');
      expect(trail.entries[2].id, 'invoice:inv-1');
    });
  });

  group('BreadcrumbTrailResolver.composeVisitDocumentFromDetail', () {
    test('replaces visit-detail leaf with visit documentation', () {
      final trail = BreadcrumbTrailResolver.composeVisitDocumentFromDetail(
        parent: BreadcrumbTrail([BreadcrumbEntries.hubCalendar(), BreadcrumbEntries.visitDetail('visit-1')]),
        visitId: 'visit-1',
      );

      expect(trail.entries, hasLength(2));
      expect(trail.entries[0].id, 'hub:calendar');
      expect(trail.entries[1].id, 'visit-doc:visit-1');
    });
  });
}
