import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/dev/presentation/sections/components_showcase_section.dart';
import 'package:ai_clinic/features/dev/presentation/sections/foundations_showcase_section.dart';
import 'package:ai_clinic/features/dev/presentation/sections/guidelines_showcase_section.dart';
import 'package:ai_clinic/features/dev/presentation/sections/patterns_showcase_section.dart';
import 'package:ai_clinic/features/dev/presentation/widgets/showcase_locale_controls.dart';

/// Design system showcase mirroring the web-reference Dev page.
///
/// Debug builds reach this page from the shell footer item **Theme Showcase**
/// at [AppRoutes.foundationDemo].
class ThemeShowcasePage extends StatefulWidget {
  const ThemeShowcasePage({super.key});

  @override
  State<ThemeShowcasePage> createState() => _ThemeShowcasePageState();
}

class _ThemeShowcasePageState extends State<ThemeShowcasePage> {
  static const _tabs = [
    AppTabItem(id: 'foundations', label: 'Foundations'),
    AppTabItem(id: 'components', label: 'Components'),
    AppTabItem(id: 'patterns', label: 'Patterns'),
    AppTabItem(id: 'guidelines', label: 'Guidelines'),
  ];

  var _section = 'foundations';

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Center(child: Text('Theme showcase is only available in debug builds.'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: 'Design System',
            description: 'Foundations, tokens, and component matrices for the AiClinic design reference.',
            tabs: AppTabs(
              items: _tabs,
              selectedId: _section,
              onChanged: (id) => setState(() => _section = id),
              semanticLabel: 'Design system sections',
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          const ShowcaseLocaleControls(),
          const SizedBox(height: AppSpacing.s8),
          switch (_section) {
            'foundations' => const FoundationsShowcaseSection(),
            'components' => const ComponentsShowcaseSection(),
            'patterns' => const PatternsShowcaseSection(),
            'guidelines' => const GuidelinesShowcaseSection(),
            _ => const FoundationsShowcaseSection(),
          },
        ],
      ),
    );
  }
}
