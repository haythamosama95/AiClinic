import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

/// Single segment in a breadcrumb trail.
@immutable
class BreadcrumbEntry {
  const BreadcrumbEntry({required this.id, required this.label, this.targetLocation, this.onNavigate});

  /// Stable key within a trail, e.g. `hub:patients`, `patient:abc`.
  final String id;

  final BreadcrumbLabel label;

  /// go_router location for tap navigation when [onNavigate] is absent.
  final String? targetLocation;

  /// Optional override when navigation is not a simple `go`.
  final void Function(BuildContext context)? onNavigate;

  BreadcrumbEntry copyWith({
    BreadcrumbLabel? label,
    String? targetLocation,
    void Function(BuildContext context)? onNavigate,
  }) {
    return BreadcrumbEntry(
      id: id,
      label: label ?? this.label,
      targetLocation: targetLocation ?? this.targetLocation,
      onNavigate: onNavigate ?? this.onNavigate,
    );
  }

  /// Uses [existing] label when this entry is still a `…` placeholder.
  BreadcrumbEntry mergePreservedLabelFrom(BreadcrumbEntry? existing) {
    if (existing == null || !_isEllipsisPlaceholder(label)) {
      return this;
    }
    if (_isEllipsisPlaceholder(existing.label)) {
      return this;
    }
    return copyWith(label: existing.label);
  }

  static bool _isEllipsisPlaceholder(BreadcrumbLabel label) {
    return label is FixedBreadcrumbLabel && label.text == '…';
  }
}

/// Canonical breadcrumb entry factories.
abstract final class BreadcrumbEntries {
  static BreadcrumbEntry hubPatients() => BreadcrumbEntry(
    id: 'hub:patients',
    label: BreadcrumbLabel.l10n((l10n) => l10n.patients),
    targetLocation: AppRoutes.patients,
  );

  static BreadcrumbEntry hubCalendar() => BreadcrumbEntry(
    id: 'hub:calendar',
    label: BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbCalendar),
    targetLocation: AppRoutes.appointmentsCalendar,
  );

  static BreadcrumbEntry hubQueue() => BreadcrumbEntry(
    id: 'hub:queue',
    label: BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbQueue),
    targetLocation: AppRoutes.appointmentsQueue,
  );

  static BreadcrumbEntry hubInvoices({void Function(BuildContext context)? onNavigate}) => BreadcrumbEntry(
    id: 'hub:invoices',
    label: BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbInvoices),
    targetLocation: AppRoutes.billingInvoices,
    onNavigate: onNavigate,
  );

  static BreadcrumbEntry patient(String id, {required String name}) => BreadcrumbEntry(
    id: 'patient:$id',
    label: BreadcrumbLabel.fixed(name),
    targetLocation: AppRoutes.patientDetail(id),
  );

  static BreadcrumbEntry appointment(String id, {required String label}) => BreadcrumbEntry(
    id: 'appointment:$id',
    label: BreadcrumbLabel.fixed(label),
    targetLocation: AppRoutes.appointmentDetail(id),
  );

  static String appointmentLabelFromPreview(AppointmentListItem preview) {
    final date = DateFormat('MMM d, yyyy').format(preview.startTime.toLocal());
    return '${preview.patientName} · $date';
  }

  static BreadcrumbEntry invoice(String id, {required String number}) => BreadcrumbEntry(
    id: 'invoice:$id',
    label: BreadcrumbLabel.fixed(number),
    targetLocation: AppRoutes.billingInvoiceDetail(id),
  );

  static BreadcrumbEntry visitDocument(String visitId, {String? title}) => BreadcrumbEntry(
    id: 'visit-doc:$visitId',
    label: title != null
        ? BreadcrumbLabel.fixed(title)
        : BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbVisitDocumentation),
  );

  static BreadcrumbEntry visitDetail(String visitId, {String? title}) => BreadcrumbEntry(
    id: 'visit-detail:$visitId',
    label: title != null ? BreadcrumbLabel.fixed(title) : BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbVisitChronicle),
  );

  static BreadcrumbEntry visitBilling(String visitId) => BreadcrumbEntry(
    id: 'visit-billing:$visitId',
    label: BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbVisitBilling),
    targetLocation: AppRoutes.billingVisit(visitId),
  );
}
