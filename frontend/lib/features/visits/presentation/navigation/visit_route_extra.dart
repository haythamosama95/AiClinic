import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';

/// Navigation payload for visit routes.
class VisitRouteExtra implements BreadcrumbRouteExtra {
  const VisitRouteExtra({this.breadcrumbTrail});

  @override
  final BreadcrumbTrail? breadcrumbTrail;

  static VisitRouteExtra fromExtra(Object? extra) {
    if (extra is VisitRouteExtra) {
      return extra;
    }
    if (extra is BreadcrumbRouteExtra) {
      return VisitRouteExtra(breadcrumbTrail: extra.breadcrumbTrail);
    }
    return const VisitRouteExtra();
  }
}
