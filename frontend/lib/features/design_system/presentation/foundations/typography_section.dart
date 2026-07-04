import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'foundation_constants.dart';
import 'foundation_section.dart';

class _TypographySamples {
  const _TypographySamples({
    required this.display,
    required this.h1,
    required this.body,
    required this.mono,
    required this.data,
    required this.count,
    required this.time,
  });

  final String display;
  final String h1;
  final String body;
  final String mono;
  final String data;
  final String count;
  final String time;
}

_TypographySamples _samplesForLocale(String languageCode) {
  if (languageCode == 'ar') {
    return const _TypographySamples(
      display: 'نظام العيادة',
      h1: 'سجل المرضى',
      body: 'تسجيل مريض جديد وإدارة المواعيد والفواتير.',
      mono: 'INV-2026-00482',
      data: '١٬٢٥٠٫٠٠ ج.م',
      count: '٣٦',
      time: '١٤:٣٠',
    );
  }

  return const _TypographySamples(
    display: 'Clinic Console',
    h1: 'Patient Registry',
    body: 'Register patients, manage appointments, and issue invoices.',
    mono: 'INV-2026-00482',
    data: 'EGP 1,250.00',
    count: '36',
    time: '14:30',
  );
}

/// Typography foundation section with locale-aware samples and type scale table.
class TypographySection extends StatelessWidget {
  const TypographySection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final samples = _samplesForLocale(Localizations.localeOf(context).languageCode);

    return FoundationSection(
      id: 'typography',
      title: 'Typography',
      description: 'Inter + Geist for Latin; IBM Plex Sans Arabic on :lang(ar). Tabular nums for data.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SampleBlock(
                    label: 'Display LG',
                    child: Text(samples.display, style: AppTypography.displayLg(context)),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  _SampleBlock(label: 'H1', child: Text(samples.h1, style: AppTypography.h1(context))),
                  const SizedBox(height: AppSpacing.space6),
                  _SampleBlock(
                    label: 'Body',
                    child: Text(
                      samples.body,
                      style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  _SampleBlock(label: 'Mono / IDs', child: Text(samples.mono, style: AppTypography.mono(context))),
                  const SizedBox(height: AppSpacing.space6),
                  _SampleBlock(
                    label: 'Tabular data',
                    child: Row(
                      children: [
                        Text(samples.data, style: AppTypography.h2(context)),
                        const SizedBox(width: AppSpacing.space8),
                        Text(samples.count, style: AppTypography.h2(context)),
                        const SizedBox(width: AppSpacing.space8),
                        Text(samples.time, style: AppTypography.h2(context)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = FoundationBreakpoints.gridColumns(
                constraints.maxWidth,
                smCols: 2,
                lgCols: 2,
              );

              if (columns == 1) {
                return Column(
                  children: [
                    for (final row in typographyScaleRows) _ScaleRow(token: row.$1, size: row.$2),
                  ],
                );
              }

              final rows = <Widget>[];
              for (var i = 0; i < typographyScaleRows.length; i += 2) {
                rows.add(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ScaleRow(token: typographyScaleRows[i].$1, size: typographyScaleRows[i].$2)),
                      const SizedBox(width: AppSpacing.space3),
                      if (i + 1 < typographyScaleRows.length)
                        Expanded(
                          child: _ScaleRow(token: typographyScaleRows[i + 1].$1, size: typographyScaleRows[i + 1].$2),
                        )
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                );
                if (i + 2 < typographyScaleRows.length) {
                  rows.add(const SizedBox(height: AppSpacing.space3));
                }
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }
}

class _SampleBlock extends StatelessWidget {
  const _SampleBlock({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.overline(context)),
        const SizedBox(height: AppSpacing.space2),
        child,
      ],
    );
  }
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({required this.token, required this.size});

  final String token;
  final String size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Aa', style: AppTypography.forToken(context, token)),
          Text('$token · $size', style: AppTypography.caption(context)),
        ],
      ),
    );
  }
}
