import 'package:flutter/foundation.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/navigation/nav_model.dart';

/// Shell nav section for the in-app design system route.
enum ShellDevSection { foundations, components }

/// Route metadata for shell placeholder pages — mirrors web `routes.tsx`.
@immutable
class ShellRouteMeta {
  const ShellRouteMeta({required this.title, required this.description});

  final String title;
  final String description;
}

const shellRouteDescriptions = <String, String>{
  'home': 'Your clinic workspace overview and quick actions.',
  'dashboard': 'Key metrics, activity, and operational insights at a glance.',
  'patients': 'Manage patient records, demographics, and care history.',
  'appointments': 'Schedule, confirm, and track patient appointments.',
  'encounters': 'Document visits, diagnoses, and clinical notes.',
  'workspace': 'Your active tasks, drafts, and in-progress clinical work.',
  'billing': 'Charges, payments, and revenue cycle management.',
  'invoices': 'Create, send, and reconcile patient invoices.',
  'services': 'Catalog procedures, packages, and billable services.',
  'staff': 'Team directory, roles, and provider profiles.',
  'shifts': 'Staff scheduling, coverage, and shift assignments.',
  'reports': 'Operational and clinical reports across your organization.',
  'settings': 'Clinic preferences, integrations, and account configuration.',
  'dev': 'Design system foundations and component reference.',
};

const _shellNavRouteById = <String, String>{
  'home': AppRoutes.home,
  'dashboard': AppRoutes.dashboard,
  'patients': AppRoutes.patients,
  'appointments': AppRoutes.appointments,
  'encounters': AppRoutes.encounters,
  'workspace': AppRoutes.workspace,
  'billing': AppRoutes.billingHub,
  'invoices': AppRoutes.billingInvoices,
  'services': AppRoutes.settingsServices,
  'staff': AppRoutes.settingsStaff,
  'shifts': AppRoutes.shiftsCalendar,
  'reports': AppRoutes.reports,
  'settings': AppRoutes.settings,
  'dev': AppRoutes.devFoundations,
};

/// All top-level shell nav locations — mirrors web hash routes (`#home`, `#dev/*`, …).
const shellNavRoutePaths = <String>{
  AppRoutes.home,
  AppRoutes.dashboard,
  AppRoutes.patients,
  AppRoutes.appointments,
  AppRoutes.encounters,
  AppRoutes.workspace,
  AppRoutes.billingHub,
  AppRoutes.billingInvoices,
  AppRoutes.settingsServices,
  AppRoutes.settingsStaff,
  AppRoutes.shiftsCalendar,
  AppRoutes.reports,
  AppRoutes.settings,
  AppRoutes.devFoundations,
  AppRoutes.devComponents,
};

/// Whether [location] is a primary sidebar destination (not a feature sub-route).
bool isShellNavLocation(String location) {
  if (location.startsWith(AppRoutes.dev)) {
    return true;
  }
  return shellNavRoutePaths.contains(location);
}

ShellRouteMeta shellMetaForNavId(String id) {
  final item = allNavItems.where((nav) => nav.id == id).firstOrNull;
  return ShellRouteMeta(
    title: item?.label ?? id,
    description:
        shellRouteDescriptions[id] ??
        'The ${item?.label ?? id} area of AiClinic.',
  );
}

/// Resolves sidebar nav id to a go_router location.
String? shellRouteForNavId(String navId) => _shellNavRouteById[navId];

/// Derives the active sidebar item from the current matched location.
String shellActiveNavIdForLocation(String location) {
  if (location.startsWith(AppRoutes.dev)) return 'dev';
  if (location == AppRoutes.home) return 'home';
  if (location == AppRoutes.dashboard) return 'dashboard';
  if (location.startsWith(AppRoutes.patients)) return 'patients';
  if (location.startsWith(AppRoutes.appointments)) return 'appointments';
  if (location.startsWith(AppRoutes.visits) ||
      location.startsWith(AppRoutes.encounters)) {
    return 'encounters';
  }
  if (location.startsWith(AppRoutes.workspace)) return 'workspace';
  if (location.startsWith(AppRoutes.billingInvoices)) return 'invoices';
  if (location.startsWith('/billing')) return 'billing';
  if (location.startsWith(AppRoutes.settingsServices)) return 'services';
  if (location.startsWith(AppRoutes.settingsStaff)) return 'staff';
  if (location.startsWith(AppRoutes.shifts)) return 'shifts';
  if (location == AppRoutes.reports) return 'reports';
  if (location.startsWith(AppRoutes.settings)) return 'settings';

  return 'home';
}

/// Whether shell content should use full width (e.g. component matrices).
bool shellFullWidthForLocation(String location) {
  return location.startsWith(AppRoutes.devComponents);
}

ShellDevSection shellDevSectionForLocation(String location) {
  if (location.startsWith(AppRoutes.devComponents)) {
    return ShellDevSection.components;
  }
  return ShellDevSection.foundations;
}

String shellBreadcrumbLabelForLocation(String location) {
  if (location.startsWith(AppRoutes.dev)) {
    return shellDevSectionForLocation(location) == ShellDevSection.foundations
        ? 'Foundations'
        : 'Components';
  }
  return shellMetaForNavId(shellActiveNavIdForLocation(location)).title;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
