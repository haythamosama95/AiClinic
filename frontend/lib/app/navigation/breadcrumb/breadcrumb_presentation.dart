import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';

/// Where breadcrumb trails render for a route.
enum BreadcrumbPresentation { shell, inPage, none }

abstract final class BreadcrumbPresentationConfig {
  static BreadcrumbPresentation forLocation(String location) {
    if (ShellNavConfig.isDesignSystemLocation(location)) {
      return BreadcrumbPresentation.shell;
    }

    if (_isPatientDetail(location) ||
        _isAppointmentDetail(location) ||
        _isInvoiceDetail(location) ||
        _isVisitWorkspace(location) ||
        _isVisitBilling(location)) {
      return BreadcrumbPresentation.inPage;
    }

    if (_isHubLocation(location)) {
      return BreadcrumbPresentation.shell;
    }

    return BreadcrumbPresentation.none;
  }

  static bool _isHubLocation(String location) {
    return location == AppRoutes.patients ||
        location == AppRoutes.appointmentsCalendar ||
        location == AppRoutes.appointmentsQueue ||
        location == AppRoutes.billingInvoices;
  }

  static bool _isPatientDetail(String location) {
    final prefix = '${AppRoutes.patients}/';
    if (!location.startsWith(prefix)) {
      return false;
    }
    final remainder = location.substring(prefix.length);
    return remainder.isNotEmpty && !remainder.contains('/');
  }

  static bool _isAppointmentDetail(String location) {
    if (!location.startsWith('${AppRoutes.appointments}/')) {
      return false;
    }
    if (AppRoutes.appointmentStaticPaths.contains(location)) {
      return false;
    }
    return !location.startsWith('${AppRoutes.appointments}/schedule/');
  }

  static bool _isVisitWorkspace(String location) {
    if (!location.startsWith('${AppRoutes.visits}/')) {
      return false;
    }
    return location.endsWith('/${AppRoutes.visitDocumentSegment}') ||
        location.endsWith('/${AppRoutes.visitDetailSegment}');
  }

  static bool _isInvoiceDetail(String location) {
    final prefix = '${AppRoutes.billingInvoices}/';
    if (!location.startsWith(prefix)) {
      return false;
    }
    final remainder = location.substring(prefix.length);
    return remainder.isNotEmpty && !remainder.contains('/');
  }

  static bool _isVisitBilling(String location) {
    final prefix = '${AppRoutes.billing}/${AppRoutes.billingVisitSegment}/';
    if (!location.startsWith(prefix)) {
      return false;
    }
    final remainder = location.substring(prefix.length);
    return remainder.isNotEmpty && !remainder.contains('/');
  }
}
