import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// Whether the editor form renders as a full page or embedded in dialog/drawer.
enum EditorFormPresentation {
  /// Full page with [AppPageHeader].
  page,

  /// Embedded body — parent supplies dialog/drawer chrome.
  embedded,
}

/// One grouped form section inside [EditorFormPattern].
class EditorFormSection {
  const EditorFormSection({
    required this.title,
    required this.fields,
    this.description,
    this.actions,
    this.twoColumn = false,
  });

  final String title;
  final String? description;
  final List<Widget> fields;
  final Widget? actions;

  /// When true, paired fields render in two columns on wide viewports.
  final bool twoColumn;
}

/// Editor / form page scaffold — grouped sections, alerts, and sticky footer.
///
/// Composes page header (or embedded body) → [AppSectionHeader] +
/// [AppFormField] sections (single-column default; 2-col paired on wide via
/// [LayoutBuilder]) → sticky footer actions. Exposes [summaryAlert] and
/// [staleEditAlert] slots for backend rule errors and stale-edit conflicts.
/// Validation is caller-driven.
class EditorFormPattern extends StatelessWidget {
  const EditorFormPattern({
    required this.sections,
    required this.footer,
    this.presentation = EditorFormPresentation.page,
    this.title,
    this.description,
    this.breadcrumb,
    this.headerActions,
    this.summaryAlert,
    this.staleEditAlert,
    this.leadingContent,
    this.trailingContent,
    super.key,
  });

  final EditorFormPresentation presentation;
  final String? title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? headerActions;
  final List<EditorFormSection> sections;
  final Widget? leadingContent;
  final Widget? trailingContent;
  final Widget? summaryAlert;
  final Widget? staleEditAlert;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PatternScaffold.pagePadding(constraints.maxWidth);
        final twoColumn = PatternScaffold.useFormTwoColumn(constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AppScrollArea(
                child: Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (presentation == EditorFormPresentation.page &&
                          title != null)
                        AppPageHeader(
                          title: title!,
                          description: description,
                          breadcrumb: breadcrumb,
                          actions: headerActions,
                        ),
                      if (presentation == EditorFormPresentation.page &&
                          title != null)
                        const SizedBox(height: PatternScaffold.sectionGap),
                      if (staleEditAlert != null) ...[
                        staleEditAlert!,
                        const SizedBox(height: AppSpacing.s4),
                      ],
                      if (leadingContent != null) ...[
                        leadingContent!,
                        const SizedBox(height: PatternScaffold.sectionGap),
                      ],
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: PatternScaffold.sectionGap),
                        _EditorFormSectionView(
                          section: sections[i],
                          twoColumn: twoColumn,
                        ),
                      ],
                      if (summaryAlert != null) ...[
                        const SizedBox(height: AppSpacing.s4),
                        summaryAlert!,
                      ],
                      if (trailingContent != null) ...[
                        const SizedBox(height: PatternScaffold.sectionGap),
                        trailingContent!,
                      ],
                      const SizedBox(height: AppSpacing.s4),
                    ],
                  ),
                ),
              ),
            ),
            _EditorFormFooter(footer: footer, padding: padding),
          ],
        );
      },
    );
  }
}

class _EditorFormSectionView extends StatelessWidget {
  const _EditorFormSectionView({
    required this.section,
    required this.twoColumn,
  });

  final EditorFormSection section;
  final bool twoColumn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: section.title,
          description: section.description,
          actions: section.actions,
        ),
        const SizedBox(height: AppSpacing.s4),
        if (section.twoColumn && twoColumn && section.fields.length > 1)
          _TwoColumnFields(fields: section.fields)
        else
          _SingleColumnFields(fields: section.fields),
      ],
    );
  }
}

class _SingleColumnFields extends StatelessWidget {
  const _SingleColumnFields({required this.fields});

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s4),
          fields[i],
        ],
      ],
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.fields});

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final left = fields[i];
      final right = i + 1 < fields.length ? fields[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: AppSpacing.s4),
            Expanded(child: right ?? const SizedBox.shrink()),
          ],
        ),
      );
      if (i + 2 < fields.length) {
        rows.add(const SizedBox(height: AppSpacing.s4));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _EditorFormFooter extends StatelessWidget {
  const _EditorFormFooter({
    required this.footer,
    required this.padding,
  });

  final Widget footer;
  final EdgeInsetsDirectional padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border(
          top: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: padding.start,
          end: padding.end,
          top: AppSpacing.s4,
          bottom: AppSpacing.s4,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _EditorFormFooterActions(child: footer),
        ),
      ),
    );
  }
}

/// Unwraps [Row] footers into a wrapping layout on narrow widths.
class _EditorFormFooterActions extends StatelessWidget {
  const _EditorFormFooterActions({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      textDirection: Directionality.of(context),
      children: _extractChildren(child),
    );
  }

  List<Widget> _extractChildren(Widget widget) {
    if (widget is Row) {
      return widget.children;
    }
    if (widget is Wrap) {
      return widget.children;
    }
    return [widget];
  }
}
