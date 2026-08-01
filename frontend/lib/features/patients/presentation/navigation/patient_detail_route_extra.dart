import 'dart:ui';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';

/// Navigation payload for patient detail routes opened from the list.
class PatientDetailRouteExtra implements BreadcrumbRouteExtra {
  const PatientDetailRouteExtra({this.preview, this.sourceRect, this.breadcrumbTrail});

  final PatientListItem? preview;
  final Rect? sourceRect;

  @override
  final BreadcrumbTrail? breadcrumbTrail;

  /// Parses [extra] from go_router, supporting legacy `PatientListItem` payloads.
  static PatientDetailRouteExtra fromExtra(Object? extra) {
    if (extra is PatientDetailRouteExtra) {
      return extra;
    }
    if (extra is PatientListItem) {
      return PatientDetailRouteExtra(preview: extra);
    }
    return const PatientDetailRouteExtra();
  }
}
