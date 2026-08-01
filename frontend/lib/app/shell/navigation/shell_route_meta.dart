import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';

/// Route titles and descriptions for shell placeholder pages (web `routes.tsx`).
abstract final class ShellRouteMeta {
  static const _descriptions = <String, String>{
    'home': 'Your clinic workspace overview and quick actions.',
    'dashboard': 'Key metrics, activity, and operational insights at a glance.',
    'patients': 'Manage patient records, demographics, and care history.',
    'appointments': 'Schedule, confirm, and track patient appointments.',
    'encounters': 'Document visits, diagnoses, and clinical notes.',
    'workspace': 'Your active tasks, drafts, and in-progress clinical work.',
    'invoices': 'Create, send, and reconcile patient invoices.',
    'services': 'Catalog procedures, packages, and billable services.',
    'clinic-management': 'Organization identity, locations, team accounts, and access roles.',
    'staff': 'Team directory, roles, and provider profiles.',
    'shifts': 'Staff scheduling, coverage, and shift assignments.',
    'reports': 'Operational and clinical reports across your organization.',
    'settings': 'Clinic preferences, integrations, and account configuration.',
    'dev': 'Design system foundations and component reference.',
  };

  static String titleFor(String itemId) => ShellNavConfig.labelFor(itemId) ?? itemId;

  static String descriptionFor(String itemId) {
    return _descriptions[itemId] ?? 'The ${titleFor(itemId)} area of AiClinic.';
  }
}
