import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_route_extra.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

/// Navigation payload for appointment detail routes opened from the calendar.
class AppointmentDetailRouteExtra implements BreadcrumbRouteExtra {
  const AppointmentDetailRouteExtra({this.preview, this.breadcrumbTrail});

  final AppointmentListItem? preview;

  @override
  final BreadcrumbTrail? breadcrumbTrail;

  /// Parses [extra] from go_router, supporting legacy `AppointmentListItem` payloads.
  static AppointmentDetailRouteExtra fromExtra(Object? extra) {
    if (extra is AppointmentDetailRouteExtra) {
      return extra;
    }
    if (extra is AppointmentListItem) {
      return AppointmentDetailRouteExtra(preview: extra);
    }
    return const AppointmentDetailRouteExtra();
  }
}
