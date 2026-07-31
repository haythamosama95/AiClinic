import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';

/// Seeds [breadcrumbTrailProvider] with a fixed trail for widget tests.
class SeedBreadcrumbTrailNotifier extends BreadcrumbTrailNotifier {
  SeedBreadcrumbTrailNotifier(this._trail);

  final BreadcrumbTrail _trail;

  @override
  BreadcrumbTrail build() => _trail;
}

Override breadcrumbTrailOverride(BreadcrumbTrail trail) {
  return breadcrumbTrailProvider.overrideWith(() => SeedBreadcrumbTrailNotifier(trail));
}

/// Deep-link canonical fallback for visit documentation routes.
BreadcrumbTrail weakVisitDocumentTrail(String visitId) => BreadcrumbTrail([
  BreadcrumbEntries.hubCalendar(),
  BreadcrumbEntries.visitDocument(visitId),
]);

BreadcrumbTrail calendarAppointmentVisitTrail({
  required String appointmentId,
  required String visitId,
  String appointmentLabel = '…',
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubCalendar(),
      BreadcrumbEntries.appointment(appointmentId, label: appointmentLabel),
      BreadcrumbEntries.visitDocument(visitId),
    ]);

BreadcrumbTrail invoiceToVisitTrail({
  required String invoiceId,
  required String invoiceNumber,
  required String visitId,
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubInvoices(),
      BreadcrumbEntries.invoice(invoiceId, number: invoiceNumber),
      BreadcrumbEntries.visitDocument(visitId),
    ]);

BreadcrumbTrail invoiceDetailTrail({
  required String invoiceId,
  required String invoiceNumber,
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubInvoices(),
      BreadcrumbEntries.invoice(invoiceId, number: invoiceNumber),
    ]);

BreadcrumbTrail queueToAppointmentTrail({
  required String appointmentId,
  String appointmentLabel = '…',
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubQueue(),
      BreadcrumbEntries.appointment(appointmentId, label: appointmentLabel),
    ]);

BreadcrumbTrail calendarToAppointmentTrail({
  required String appointmentId,
  String appointmentLabel = '…',
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubCalendar(),
      BreadcrumbEntries.appointment(appointmentId, label: appointmentLabel),
    ]);

BreadcrumbTrail patientDetailTrail({
  required String patientId,
  String patientName = '…',
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubPatients(),
      BreadcrumbEntries.patient(patientId, name: patientName),
    ]);

BreadcrumbTrail patientsToVisitTrail({
  required String patientId,
  required String patientName,
  required String visitId,
}) =>
    BreadcrumbTrail([
      BreadcrumbEntries.hubPatients(),
      BreadcrumbEntries.patient(patientId, name: patientName),
      BreadcrumbEntries.visitDocument(visitId),
    ]);
