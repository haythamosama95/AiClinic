import 'package:flutter/material.dart';

import 'package:ai_clinic/features/design_system/presentation/components/actions/button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/icon_button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/segmented_control_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/split_button_showcase_section.dart';
// Inputs & forms
import 'package:ai_clinic/features/design_system/presentation/components/inputs/choice_controls_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/combobox_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/date_time_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/file_dropzone_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/form_field_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/money_field_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/multi_select_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/number_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/password_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/phone_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/search_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/select_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/slider_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/text_input_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/inputs/textarea_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/component_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

typedef ComponentSectionBuilder = Widget Function();

/// Maps ready section ids to their showcase builders.
final Map<String, ComponentSectionBuilder> componentSectionBuilders = {
  'button': () => const ButtonShowcaseSection(),
  'icon-button': () => const IconButtonShowcaseSection(),
  'split-button': () => const SplitButtonShowcaseSection(),
  'segmented-control': () => const SegmentedControlShowcaseSection(),
  'form-field': () => const FormFieldShowcaseSection(),
  'text-input': () => const TextInputShowcaseSection(),
  'textarea': () => const TextareaShowcaseSection(),
  'search-input': () => const SearchInputShowcaseSection(),
  'password-input': () => const PasswordInputShowcaseSection(),
  'number-input': () => const NumberInputShowcaseSection(),
  'money-field': () => const MoneyFieldShowcaseSection(),
  'phone-input': () => const PhoneInputShowcaseSection(),
  'select': () => const SelectShowcaseSection(),
  'combobox': () => const ComboboxShowcaseSection(),
  'multi-select': () => const MultiSelectShowcaseSection(),
  'checkbox': () => const CheckboxShowcaseSection(),
  'radio-group': () => const RadioGroupShowcaseSection(),
  'switch': () => const SwitchShowcaseSection(),
  'date-picker': () => const DatePickerShowcaseSection(),
  'time-picker': () => const TimePickerShowcaseSection(),
  'date-range-picker': () => const DateRangePickerShowcaseSection(),
  'file-dropzone': () => const FileDropzoneShowcaseSection(),
  'slider': () => const SliderShowcaseSection(),
};

/// Builds a section widget from registry metadata.
Widget buildComponentSection(ShowcaseSectionDef section) {
  if (section.status == ShowcaseSectionStatus.ready) {
    final builder = componentSectionBuilders[section.id];
    if (builder != null) return builder();
  }

  return ShowcaseSection(
    id: section.id,
    title: section.title,
    description: section.description,
    child: PlaceholderSection(title: section.title, message: 'To be implemented later'),
  );
}
