import 'package:ai_clinic/core/ui/components/app_select.dart';

/// Prescription frequency options (web `FREQUENCY_OPTIONS`).
const treatmentFrequencyOptions = <AppSelectOption>[
  AppSelectOption(value: 'od', label: 'Once daily'),
  AppSelectOption(value: 'bd', label: 'Twice daily'),
  AppSelectOption(value: 'tds', label: 'Three times daily'),
  AppSelectOption(value: 'qid', label: 'Four times daily'),
  AppSelectOption(value: 'q4h', label: 'Every 4 hours'),
  AppSelectOption(value: 'q6h', label: 'Every 6 hours'),
  AppSelectOption(value: 'q8h', label: 'Every 8 hours'),
  AppSelectOption(value: 'prn', label: 'As needed'),
  AppSelectOption(value: 'stat', label: 'Single dose'),
];

/// Prescription duration options (web `DURATION_OPTIONS`).
const treatmentDurationOptions = <AppSelectOption>[
  AppSelectOption(value: '3d', label: '3 days'),
  AppSelectOption(value: '5d', label: '5 days'),
  AppSelectOption(value: '7d', label: '7 days'),
  AppSelectOption(value: '10d', label: '10 days'),
  AppSelectOption(value: '14d', label: '14 days'),
  AppSelectOption(value: '21d', label: '21 days'),
  AppSelectOption(value: '30d', label: '30 days'),
  AppSelectOption(value: 'ongoing', label: 'Ongoing'),
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
