import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Decorative login backdrop that evokes the authenticated shell without
/// mounting [AuthenticatedShell] or reading auth/session providers.
class LoginStaticBackdrop extends StatelessWidget {
  const LoginStaticBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ColoredBox(
      color: colors.surfaceCanvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          AppColorPrimitives.surfaceSunkenDark,
                          colors.surfaceCanvas,
                          AppColorPrimitives.surfaceAiDark.withValues(alpha: 0.45),
                        ]
                      : [
                          AppColorPrimitives.teal50.withValues(alpha: 0.55),
                          colors.surfaceCanvas,
                          AppColorPrimitives.violet50.withValues(alpha: 0.35),
                        ],
                ),
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _BackdropPatternPainter(isDark: isDark))),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: AppShellTokens.sidebarExpandedWidth,
                child: ColoredBox(
                  color: colors.surfaceDefault.withValues(alpha: isDark ? 0.72 : 0.88),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SkeletonBlock(width: 120, height: 28, color: colors.surfaceMuted),
                        const SizedBox(height: AppSpacing.space8),
                        for (var i = 0; i < 6; i++) ...[
                          _SkeletonBlock(width: double.infinity, height: AppShellTokens.navItemHeight, color: colors.surfaceMuted),
                          const SizedBox(height: AppSpacing.space2),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: AppShellTokens.topBarHeight,
                      child: ColoredBox(
                        color: colors.surfaceDefault.withValues(alpha: isDark ? 0.65 : 0.82),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
                          child: Row(
                            children: [
                              _SkeletonBlock(width: 180, height: 20, color: colors.surfaceMuted),
                              const Spacer(),
                              _SkeletonBlock(width: 120, height: AppShellTokens.topBarActionHeight, color: colors.surfaceMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.space6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SkeletonBlock(width: 220, height: 28, color: colors.surfaceMuted),
                            const SizedBox(height: AppSpacing.space2),
                            _SkeletonBlock(width: 320, height: 16, color: colors.surfaceMuted),
                            const SizedBox(height: AppSpacing.space6),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: _SkeletonPanel(color: colors.surfaceMuted),
                                  ),
                                  const SizedBox(width: AppSpacing.space4),
                                  Expanded(child: _SkeletonPanel(color: colors.surfaceMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkeletonPanel extends StatelessWidget {
  const _SkeletonPanel({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}

class _BackdropPatternPainter extends CustomPainter {
  const _BackdropPatternPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? AppColorPrimitives.neutral600 : AppColorPrimitives.neutral300).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    const radius = 1.2;

    for (var x = spacing / 2; x < size.width; x += spacing) {
      for (var y = spacing / 2; y < size.height; y += spacing) {
        final wave = math.sin((x + y) / 84) * 0.35 + 0.65;
        if (wave < 0.55) continue;
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPatternPainter oldDelegate) => oldDelegate.isDark != isDark;
}
