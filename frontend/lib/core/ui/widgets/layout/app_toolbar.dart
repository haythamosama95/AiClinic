import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';

/// Standard strip above tables and lists with start, center, and end slots.
class AppToolbar extends StatelessWidget {
  /// Creates a toolbar.
  ///
  /// On viewports narrower than [compactBreakpoint], [compactEnd] replaces
  /// [end] when provided so features can surface a single Filters control.
  const AppToolbar({
    this.start,
    this.center,
    this.end,
    this.sticky = false,
    this.compactBreakpoint = AppBreakpoints.sm,
    this.compactEnd,
    super.key,
  });

  final Widget? start;
  final Widget? center;
  final Widget? end;
  final bool sticky;

  /// Minimum width before the toolbar switches to the compact layout.
  ///
  /// Set to `null` to always use the wide layout.
  final double? compactBreakpoint;

  /// Replacement for [end] below [compactBreakpoint] (e.g. a Filters button).
  final Widget? compactEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brightness = Theme.of(context).brightness;

    Widget bar = Semantics(
      container: true,
      label: 'Toolbar',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderDefault),
          borderRadius: AppRadii.lgAll,
          boxShadow: sticky
              ? AppShadows.forLevel(0, brightness)
              : null,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s3,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = compactBreakpoint != null &&
                  constraints.maxWidth < compactBreakpoint!;
              final resolvedEnd =
                  compact && compactEnd != null ? compactEnd : end;

              if (compact) {
                return _CompactToolbarLayout(
                  start: start,
                  center: center,
                  end: resolvedEnd,
                  width: constraints.maxWidth,
                );
              }

              return _WideToolbarLayout(
                start: start,
                center: center,
                end: resolvedEnd,
              );
            },
          ),
        ),
      ),
    );

    if (sticky) {
      bar = Material(
        color: colors.surfaceDefault,
        elevation: 0,
        child: bar,
      );
    }

    return bar;
  }
}

class _WideToolbarLayout extends StatelessWidget {
  const _WideToolbarLayout({
    this.start,
    this.center,
    this.end,
  });

  final Widget? start;
  final Widget? center;
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (start != null)
          Flexible(
            fit: FlexFit.loose,
            child: _ToolbarSlot(child: start!),
          ),
        if (center != null)
          Expanded(
            child: Center(
              child: _ToolbarSlot(child: center!),
            ),
          ),
        if (end != null)
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _ToolbarSlot(child: end!),
            ),
          ),
      ],
    );
  }
}

class _CompactToolbarLayout extends StatelessWidget {
  const _CompactToolbarLayout({
    required this.width,
    this.start,
    this.center,
    this.end,
  });

  final double width;
  final Widget? start;
  final Widget? center;
  final Widget? end;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s3,
      runSpacing: AppSpacing.s3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (start != null) _ToolbarSlot(child: start!),
        if (center != null) _ToolbarSlot(child: center!),
        if (end != null)
          SizedBox(
            width: width,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _ToolbarSlot(child: end!),
            ),
          ),
      ],
    );
  }
}

class _ToolbarSlot extends StatelessWidget {
  const _ToolbarSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
