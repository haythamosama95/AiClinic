import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/components/components_content.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/dev_text_styles.dart';

/// Components tab with a loading screen while showcase sections are built.
class ComponentsTabSection extends StatefulWidget {
  const ComponentsTabSection({
    required this.direction,
    required this.locale,
    required this.preloadComplete,
    required this.onPreloadComplete,
    super.key,
  });

  final TextDirection direction;
  final String locale;
  final bool preloadComplete;
  final VoidCallback onPreloadComplete;

  @override
  State<ComponentsTabSection> createState() => _ComponentsTabSectionState();
}

class _ComponentsTabSectionState extends State<ComponentsTabSection> {
  var _contentReady = false;

  @override
  void initState() {
    super.initState();
    _contentReady = widget.preloadComplete;
  }

  @override
  void didUpdateWidget(covariant ComponentsTabSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preloadComplete && !_contentReady) {
      _contentReady = true;
    }
  }

  void _handleContentLoaded() {
    if (_contentReady) return;
    setState(() => _contentReady = true);
    widget.onPreloadComplete();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ComponentsIntro(),
        const SizedBox(height: AppSpacing.space16),
        ComponentsContent(progressive: !widget.preloadComplete, onLoadComplete: _handleContentLoaded),
      ],
    );

    return Directionality(
      textDirection: widget.direction,
      child: Localizations.override(
        context: context,
        locale: Locale(widget.locale),
        child: _contentReady
            ? content
            : Stack(
                children: [
                  Offstage(child: content),
                  const SizedBox(width: double.infinity, height: 420, child: _ComponentsLoadingView()),
                ],
              ),
      ),
    );
  }
}

/// Placeholder side nav shown while component sections are loading.
class ComponentsSubNavLoading extends StatelessWidget {
  const ComponentsSubNavLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Component groups', style: DevTextStyles.overline(context)),
        const SizedBox(height: AppSpacing.space2),
        Text('Loading…', style: AppTypography.caption(context).copyWith(color: colors.textTertiary)),
      ],
    );
  }
}

class _ComponentsIntro extends StatelessWidget {
  const _ComponentsIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Milestone 4', style: DevTextStyles.overline(context)),
        Text('Components', style: DevTextStyles.h2(context)),
        const SizedBox(height: AppSpacing.space2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Text(
            'Shared primitives with full variant and state matrices. Toggle theme, direction, language, '
            'density, and AI mode in the header or the App shell demo.',
            style: DevTextStyles.bodyLg(context),
          ),
        ),
      ],
    );
  }
}

class _ComponentsLoadingView extends StatelessWidget {
  const _ComponentsLoadingView();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ColoredBox(
      color: colors.surfaceDefault.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colors.actionPrimary),
            const SizedBox(height: AppSpacing.space4),
            Text('Loading components…', style: AppTypography.body(context).copyWith(color: colors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
