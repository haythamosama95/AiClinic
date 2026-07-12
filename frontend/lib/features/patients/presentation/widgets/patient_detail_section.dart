import 'package:flutter/widgets.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';

/// Tab sections on the patient detail page.
enum PatientDetailSection {
  visits,
  documents,
  billing;

  String get id => name;

  static PatientDetailSection? fromId(String id) {
    return switch (id) {
      'visits' => PatientDetailSection.visits,
      'documents' => PatientDetailSection.documents,
      'billing' => PatientDetailSection.billing,
      _ => null,
    };
  }
}

/// Localized label for a [PatientDetailSection] tab.
String patientDetailSectionLabel(BuildContext context, PatientDetailSection section) {
  final l10n = context.l10n;
  return switch (section) {
    PatientDetailSection.visits => l10n.visits,
    PatientDetailSection.documents => l10n.documents,
    PatientDetailSection.billing => l10n.billing,
  };
}
