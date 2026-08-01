import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';

/// Route payloads that carry breadcrumb trail context.
abstract interface class BreadcrumbRouteExtra {
  BreadcrumbTrail? get breadcrumbTrail;
}
