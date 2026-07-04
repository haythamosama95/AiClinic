import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/dev_section.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/dev_section_layout.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundations_content.dart';
import 'package:ai_clinic/features/design_system/presentation/foundations/foundations_sub_nav.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_locale_controls.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_page_header.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_tabs.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Design system dev page shell (web `DevPage`).
class DesignSystemPage extends ConsumerStatefulWidget {
  const DesignSystemPage({super.key});

  @override
  ConsumerState<DesignSystemPage> createState() => _DesignSystemPageState();
}

class _DesignSystemPageState extends ConsumerState<DesignSystemPage> {
  DevSection _section = DevSection.foundations;

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(devPreviewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DevPageHeader(
          title: 'Design System',
          description: 'Foundations, tokens, and component matrices for the AiClinic design reference.',
          tabs: DevTabs(value: _section, onChanged: (section) => setState(() => _section = section)),
        ),
        const SizedBox(height: AppSpacing.space6),
        const DevLocaleControls(),
        const SizedBox(height: AppSpacing.space8),
        DevSectionLayout(nav: _buildSubNav(), child: _buildTabContent(preview.direction)),
      ],
    );
  }

  Widget _buildSubNav() {
    return switch (_section) {
      DevSection.foundations => const FoundationsSubNav(),
      _ => const _ComingSoonSubNav(),
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
              _FoundationsIntro(),
              const SizedBox(height: AppSpacing.space16),
              const FoundationsContent(),
            ],
          ),
        ),
      ),
      _ => const _ComingSoonTab(),
    };
  }
}

class _FoundationsIntro extends StatelessWidget {
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
          child: Text(
            'Tokens, typography, spacing, motion, and The Signal.',
            style: DevTextStyles.bodyLg(context),
          ),
        ),
      ],
    );
  }
}

class _ComingSoonSubNav extends StatelessWidget {
  const _ComingSoonSubNav();

  @override
  Widget build(BuildContext context) {
    return Text('Sections', style: DevTextStyles.overline(context));
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space12),
        child: Text('Coming soon', style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
      ),
    );
  }
}
