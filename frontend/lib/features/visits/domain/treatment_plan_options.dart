import 'package:flutter/foundation.dart';

/// A selectable treatment-plan field option (dosage, frequency, duration).
@immutable
class TreatmentPlanOption {
  const TreatmentPlanOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Prescription frequency options (web `FREQUENCY_OPTIONS`).
const treatmentFrequencyOptions = <TreatmentPlanOption>[
  TreatmentPlanOption(value: 'od', label: 'Once daily'),
  TreatmentPlanOption(value: 'bd', label: 'Twice daily'),
  TreatmentPlanOption(value: 'tds', label: 'Three times daily'),
  TreatmentPlanOption(value: 'qid', label: 'Four times daily'),
  TreatmentPlanOption(value: 'q4h', label: 'Every 4 hours'),
  TreatmentPlanOption(value: 'q6h', label: 'Every 6 hours'),
  TreatmentPlanOption(value: 'q8h', label: 'Every 8 hours'),
  TreatmentPlanOption(value: 'prn', label: 'As needed'),
  TreatmentPlanOption(value: 'stat', label: 'Single dose'),
];

/// Prescription duration options (web `DURATION_OPTIONS`).
const treatmentDurationOptions = <TreatmentPlanOption>[
  TreatmentPlanOption(value: '3d', label: '3 days'),
  TreatmentPlanOption(value: '5d', label: '5 days'),
  TreatmentPlanOption(value: '7d', label: '7 days'),
  TreatmentPlanOption(value: '10d', label: '10 days'),
  TreatmentPlanOption(value: '14d', label: '14 days'),
  TreatmentPlanOption(value: '21d', label: '21 days'),
  TreatmentPlanOption(value: '30d', label: '30 days'),
  TreatmentPlanOption(value: 'ongoing', label: 'Ongoing'),
];

String treatmentFrequencyLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '—';
  }
  for (final option in treatmentFrequencyOptions) {
    if (option.value == value) {
      return option.label;
    }
  }
  return value;
}

String treatmentDurationLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '—';
  }
  for (final option in treatmentDurationOptions) {
    if (option.value == value) {
      return option.label;
    }
  }
  return value;
}
