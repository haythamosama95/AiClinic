import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/design_system/presentation/components/components_sub_nav.dart';
import 'package:ai_clinic/features/design_system/presentation/components/components_tab_section.dart';
import 'package:ai_clinic/features/design_system/presentation/dev_section.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_layout.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundations_content.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundations_sub_nav.dart';
import 'package:ai_clinic/features/design_system/presentation/guidelines/guidelines_page.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/patterns_page.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_locale_controls.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_tabs.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Design system dev page shell (web `DevPage`).
class DesignSystemPage extends ConsumerStatefulWidget {
  const DesignSystemPage({this.initialSection = DevSection.components, super.key});

  final DevSection initialSection;

  @override
  ConsumerState<DesignSystemPage> createState() => _DesignSystemPageState();
}

class _DesignSystemPageState extends ConsumerState<DesignSystemPage> {
  late DevSection _section = widget.initialSection;
  var _componentsPreloaded = false;

  @override
  void didUpdateWidget(covariant DesignSystemPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _section = widget.initialSection;
    }
  }

  void _onSectionChanged(DevSection section) {
    setState(() => _section = section);
    final uri = Uri(
      path: AppRoutes.foundationDemo,
      queryParameters: section == DevSection.components ? null : {'section': section.id},
    );
    context.go(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(devPreviewProvider);

    final header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: 'Design System',
          description: 'Foundations, tokens, and component matrices for the AiClinic design reference.',
          tabs: DevTabs(value: _section, onChanged: _onSectionChanged),
        ),
        const SizedBox(height: AppSpacing.space6),
        const DevLocaleControls(),
        const SizedBox(height: AppSpacing.space8),
      ],
    );

    final section = DevSectionLayout(nav: _buildSubNav(), child: _buildTabContent(preview.direction));

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              Expanded(child: section),
            ],
          );
        }

        final viewportHeight =
            MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).vertical -
            AppShellTokens.topBarHeight -
            (AppSpacing.space6 * 2);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            SizedBox(height: viewportHeight.clamp(320, double.infinity), child: section),
          ],
        );
      },
    );
  }

  Widget _buildSubNav() {
    return switch (_section) {
      DevSection.foundations => const FoundationsSubNav(),
      DevSection.components when _componentsPreloaded => const ComponentsSubNav(),
      DevSection.components => const ComponentsSubNavLoading(),
      DevSection.patterns => const PatternsSubNav(),
      DevSection.guidelines => const GuidelinesSubNav(),
    };
  }

  Widget _buildTabContent(TextDirection direction) {
    return switch (_section) {
      DevSection.foundations => Directionality(
        textDirection: direction,
        child: Localizations.override(
          context: context,
          locale: Locale(ref.watch(devPreviewProvider).locale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FoundationsIntro(),
              const SizedBox(height: AppSpacing.space16),
              const FoundationsContent(),
            ],
          ),
        ),
      ),
      DevSection.components => ComponentsTabSection(
        direction: direction,
        locale: ref.watch(devPreviewProvider).locale,
        preloadComplete: _componentsPreloaded,
        onPreloadComplete: () => setState(() => _componentsPreloaded = true),
      ),
      DevSection.patterns => Directionality(
        textDirection: direction,
        child: Localizations.override(
          context: context,
          locale: Locale(ref.watch(devPreviewProvider).locale),
          child: const PatternsPage(),
        ),
      ),
      DevSection.guidelines => Directionality(
        textDirection: direction,
        child: Localizations.override(
          context: context,
          locale: Locale(ref.watch(devPreviewProvider).locale),
          child: const GuidelinesPage(),
        ),
      ),
    };
  }
}

class _FoundationsIntro extends StatelessWidget {
  const _FoundationsIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Milestone 1', style: DevTextStyles.overline(context)),
        Text('Foundations', style: DevTextStyles.h2(context)),
        const SizedBox(height: AppSpacing.space2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Text('Tokens, typography, spacing, motion, and The Signal.', style: DevTextStyles.bodyLg(context)),
        ),
      ],
    );
  }
}
