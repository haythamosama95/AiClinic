import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';

/// Navigation payload for visit billing routes.
class VisitBillingRouteExtra implements BreadcrumbRouteExtra {
  const VisitBillingRouteExtra({this.breadcrumbTrail});

  @override
  final BreadcrumbTrail? breadcrumbTrail;

  static VisitBillingRouteExtra fromExtra(Object? extra) {
    if (extra is VisitBillingRouteExtra) {
      return extra;
    }
    if (extra is BreadcrumbRouteExtra) {
      return VisitBillingRouteExtra(breadcrumbTrail: extra.breadcrumbTrail);
    }
    return const VisitBillingRouteExtra();
  }
}
