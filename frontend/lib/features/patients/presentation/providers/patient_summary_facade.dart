import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/locale_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Read-only patient identity for cross-feature visit surfaces.
@immutable
class PatientSummary {
  const PatientSummary({required this.fullName, this.ageLabel});

  final String fullName;
  final String? ageLabel;
}

/// Loads a compact patient summary for visit documentation and confirmation surfaces.
final patientSummaryForVisitProvider = FutureProvider.autoDispose.family<PatientSummary, String>((ref, patientId) async {
  final l10n = lookupAppLocalizations(ref.watch(localeProvider));

  try {
    final patient = await ref.watch(patientDetailProvider(patientId).future);
    final age = PatientPresentationFormatting.ageYears(patient.dateOfBirth);
    final ageLabel = age == null ? null : '$age years old';

    return PatientSummary(fullName: patient.fullName, ageLabel: ageLabel);
  } catch (_) {
    return PatientSummary(fullName: l10n.patientNameFallback);
  }
});
