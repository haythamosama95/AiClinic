import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_hub_navigation.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/invoice_detail_route_extra.dart';
import 'package:ai_clinic/features/billing/presentation/navigation/visit_billing_route_extra.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:ai_clinic/features/visits/presentation/navigation/visit_route_extra.dart';

/// Builds canonical breadcrumb trails and reads trail context from route extras.
abstract final class BreadcrumbTrailResolver {
  /// Single- or multi-segment hub trail for [location] (deep-link fallback).
  static BreadcrumbTrail canonicalFor(String location, {Uri? uri}) {
    if (location == AppRoutes.patients) {
      return BreadcrumbTrail([BreadcrumbEntries.hubPatients()]);
    }
    if (location == AppRoutes.appointmentsCalendar) {
      return BreadcrumbTrail([BreadcrumbEntries.hubCalendar()]);
    }
    if (location == AppRoutes.appointmentsQueue) {
      return BreadcrumbTrail([BreadcrumbEntries.hubQueue()]);
    }
    if (location == AppRoutes.billingInvoices) {
      return BreadcrumbTrail([BreadcrumbEntries.hubInvoices()]);
    }

    final patientId = _patientIdFromLocation(location);
    if (patientId != null) {
      return BreadcrumbTrail([BreadcrumbEntries.hubPatients(), BreadcrumbEntries.patient(patientId, name: '…')]);
    }

    final appointmentId = _appointmentIdFromLocation(location);
    if (appointmentId != null) {
      return BreadcrumbTrail([
        BreadcrumbEntries.hubCalendar(),
        BreadcrumbEntries.appointment(appointmentId, label: '…'),
      ]);
    }

    final invoiceId = _invoiceIdFromLocation(location);
    if (invoiceId != null) {
      return BreadcrumbTrail([BreadcrumbEntries.hubInvoices(), BreadcrumbEntries.invoice(invoiceId, number: '…')]);
    }

    final visitId = _visitIdFromLocation(location);
    if (visitId != null) {
      if (location.endsWith('/${AppRoutes.visitDocumentSegment}')) {
        return BreadcrumbTrail([BreadcrumbEntries.hubCalendar(), BreadcrumbEntries.visitDocument(visitId)]);
      }
      if (location.endsWith('/${AppRoutes.visitDetailSegment}')) {
        return BreadcrumbTrail([BreadcrumbEntries.hubCalendar(), BreadcrumbEntries.visitDetail(visitId)]);
      }
    }

    final billingVisitId = _billingVisitIdFromLocation(location);
    if (billingVisitId != null) {
      return BreadcrumbTrail([BreadcrumbEntries.hubInvoices(), BreadcrumbEntries.visitBilling(billingVisitId)]);
    }

    if (ShellNavConfig.isDesignSystemLocation(location) && uri != null) {
      final section = ShellNavConfig.devSectionForUri(uri);
      return BreadcrumbTrail([
        const BreadcrumbEntry(
          id: 'hub:dev',
          label: BreadcrumbLabel.fixed('Dev'),
          targetLocation: AppRoutes.foundationDemo,
        ),
        BreadcrumbEntry(
          id: 'dev-section',
          label: BreadcrumbLabel.fixed(ShellNavConfig.devSectionBreadcrumbLabel(section)),
        ),
      ]);
    }

    final itemId = ShellNavConfig.itemIdForLocation(location);
    if (itemId != null) {
      final pageLabel = ShellNavConfig.pageTitleForLocation(location) ?? ShellNavConfig.labelFor(itemId);
      if (pageLabel != null) {
        return BreadcrumbTrail([BreadcrumbEntry(id: 'hub:$itemId', label: BreadcrumbLabel.fixed(pageLabel))]);
      }
    }

    return BreadcrumbTrail.empty;
  }

  /// Reads trail from [extra] when the payload implements [BreadcrumbRouteExtra].
  static BreadcrumbTrail? fromExtra(Object? extra) {
    if (extra is PatientDetailRouteExtra) {
      return extra.breadcrumbTrail;
    }
    if (extra is AppointmentDetailRouteExtra) {
      return extra.breadcrumbTrail;
    }
    if (extra is VisitRouteExtra) {
      return extra.breadcrumbTrail;
    }
    if (extra is InvoiceDetailRouteExtra) {
      return extra.breadcrumbTrail;
    }
    if (extra is VisitBillingRouteExtra) {
      return extra.breadcrumbTrail;
    }
    if (extra is BreadcrumbRouteExtra) {
      return extra.breadcrumbTrail;
    }
    return null;
  }

  /// Trail for pushing invoice detail: inherits [parent]; invoices-hub pop semantics
  /// apply only when navigating from the invoices list hub.
  static BreadcrumbTrail composeInvoiceDetailPushTrail({
    required BreadcrumbTrail parent,
    required String invoiceId,
    String? invoiceNumber,
    void Function(BuildContext context)? invoicesHubPopOrGo,
  }) {
    final invoiceEntry = BreadcrumbEntries.invoice(invoiceId, number: invoiceNumber ?? '…');
    final invoicesHubNavigate = invoicesHubPopOrGo ?? popOrGoInvoicesHub;
    if (parent.entries.isEmpty || _isInvoicesListParent(parent)) {
      return BreadcrumbTrail([BreadcrumbEntries.hubInvoices(onNavigate: invoicesHubNavigate)]).append(invoiceEntry);
    }
    return parent.append(invoiceEntry);
  }

  /// Replaces a visit-detail leaf with visit documentation when opening the workspace.
  static BreadcrumbTrail composeVisitDocumentFromDetail({required BreadcrumbTrail parent, required String visitId}) {
    final detailEntryId = 'visit-detail:$visitId';
    final trimmed = parent.entries.isNotEmpty && parent.entries.last.id == detailEntryId
        ? BreadcrumbTrail(parent.entries.sublist(0, parent.entries.length - 1))
        : parent;
    return trimmed.append(BreadcrumbEntries.visitDocument(visitId));
  }

  static bool _isInvoicesListParent(BreadcrumbTrail parent) {
    return parent.entries.length == 1 && parent.entries.single.id == 'hub:invoices';
  }

  /// Parent trail for navigation: current route extra → canonical(current location).
  static BreadcrumbTrail inheritFrom(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      return BreadcrumbTrail.empty;
    }

    try {
      final routeState = GoRouterState.of(context);
      return fromExtra(routeState.extra) ?? canonicalFor(routeState.uri.path, uri: routeState.uri);
    } on GoError {
      // Overlay contexts (e.g. modal dialogs) sit outside RouteBase.builder.
    }

    final routerState = router.state;
    return fromExtra(routerState.extra) ?? canonicalFor(routerState.uri.path, uri: routerState.uri);
  }

  static String? _patientIdFromLocation(String location) {
    final prefix = '${AppRoutes.patients}/';
    if (!location.startsWith(prefix)) {
      return null;
    }
    final remainder = location.substring(prefix.length);
    if (remainder.isEmpty || remainder.contains('/')) {
      return null;
    }
    return remainder;
  }

  static String? _appointmentIdFromLocation(String location) {
    if (!location.startsWith('${AppRoutes.appointments}/')) {
      return null;
    }
    if (AppRoutes.appointmentStaticPaths.contains(location)) {
      return null;
    }
    if (location.startsWith('${AppRoutes.appointments}/schedule/')) {
      return null;
    }
    final remainder = location.substring('${AppRoutes.appointments}/'.length);
    if (remainder.isEmpty || remainder.contains('/')) {
      return null;
    }
    return remainder;
  }

  static String? _invoiceIdFromLocation(String location) {
    final prefix = '${AppRoutes.billingInvoices}/';
    if (!location.startsWith(prefix)) {
      return null;
    }
    final remainder = location.substring(prefix.length);
    if (remainder.isEmpty || remainder.contains('/')) {
      return null;
    }
    return remainder;
  }

  static String? _visitIdFromLocation(String location) {
    final prefix = '${AppRoutes.visits}/';
    if (!location.startsWith(prefix)) {
      return null;
    }
    final remainder = location.substring(prefix.length);
    final segments = remainder.split('/');
    if (segments.length != 2) {
      return null;
    }
    return segments[0];
  }

  static String? _billingVisitIdFromLocation(String location) {
    final prefix = '${AppRoutes.billing}/${AppRoutes.billingVisitSegment}/';
    if (!location.startsWith(prefix)) {
      return null;
    }
    final remainder = location.substring(prefix.length);
    if (remainder.isEmpty || remainder.contains('/')) {
      return null;
    }
    return remainder;
  }
}
