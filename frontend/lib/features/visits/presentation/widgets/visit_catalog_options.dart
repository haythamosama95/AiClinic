import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Fixed frequency options copied verbatim from web `FREQUENCY_OPTIONS`.
const List<AppSelectOption> kFrequencyOptions = [
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

/// Fixed duration options copied verbatim from web `DURATION_OPTIONS`.
const List<AppSelectOption> kDurationOptions = [
  AppSelectOption(value: '3d', label: '3 days'),
  AppSelectOption(value: '5d', label: '5 days'),
  AppSelectOption(value: '7d', label: '7 days'),
  AppSelectOption(value: '10d', label: '10 days'),
  AppSelectOption(value: '14d', label: '14 days'),
  AppSelectOption(value: '21d', label: '21 days'),
  AppSelectOption(value: '30d', label: '30 days'),
  AppSelectOption(value: 'ongoing', label: 'Ongoing'),
];

/// Resolves a frequency value to its display label (web `getFrequencyLabel`).
String getFrequencyLabel(String value) {
  for (final option in kFrequencyOptions) {
    if (option.value == value) {
      return option.label;
    }
  }
  return value;
}

/// Resolves a duration value to its display label (web `getDurationLabel`).
String getDurationLabel(String value) {
  for (final option in kDurationOptions) {
    if (option.value == value) {
      return option.label;
    }
  }
  return value;
}

/// Maps a stored frequency value or label back to an [AppSelectOption] value.
String resolveFrequencyValue(String? stored) {
  if (stored == null || stored.trim().isEmpty) {
    return '';
  }
  final trimmed = stored.trim();
  for (final option in kFrequencyOptions) {
    if (option.value == trimmed || option.label == trimmed) {
      return option.value;
    }
  }
  return trimmed;
}

/// Maps a stored duration value or label back to an [AppSelectOption] value.
String resolveDurationValue(String? stored) {
  if (stored == null || stored.trim().isEmpty) {
    return '';
  }
  final trimmed = stored.trim();
  for (final option in kDurationOptions) {
    if (option.value == trimmed || option.label == trimmed) {
      return option.value;
    }
  }
  return trimmed;
}
