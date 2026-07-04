import 'package:flutter/material.dart';

import 'package:ai_clinic/features/design_system/presentation/components/actions/button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/icon_button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/segmented_control_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/actions/split_button_showcase_section.dart';
import 'package:ai_clinic/features/design_system/presentation/components/component_registry.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';

typedef ComponentSectionBuilder = Widget Function();

/// Maps ready section ids to their showcase builders.
final Map<String, ComponentSectionBuilder> componentSectionBuilders = {
  'button': () => const ButtonShowcaseSection(),
  'icon-button': () => const IconButtonShowcaseSection(),
  'split-button': () => const SplitButtonShowcaseSection(),
  'segmented-control': () => const SegmentedControlShowcaseSection(),
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
    child: PlaceholderSection(
      title: section.title,
      message: 'To be implemented later',
    ),
  );
}
