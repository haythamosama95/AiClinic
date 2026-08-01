import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';

/// Navigation payload for invoice detail routes.
class InvoiceDetailRouteExtra implements BreadcrumbRouteExtra {
  const InvoiceDetailRouteExtra({this.breadcrumbTrail});

  @override
  final BreadcrumbTrail? breadcrumbTrail;

  static InvoiceDetailRouteExtra fromExtra(Object? extra) {
    if (extra is InvoiceDetailRouteExtra) {
      return extra;
    }
    if (extra is BreadcrumbRouteExtra) {
      return InvoiceDetailRouteExtra(breadcrumbTrail: extra.breadcrumbTrail);
    }
    return const InvoiceDetailRouteExtra();
  }
}
