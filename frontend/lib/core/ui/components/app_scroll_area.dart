import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Constrained scroll viewport with optional edge fades (web `ScrollArea`).
class AppScrollArea extends StatefulWidget {
  const AppScrollArea({
    required this.child,
    this.maxHeight = 240,
    this.fadeEdges = true,
    this.semanticLabel = 'Scrollable content',
    super.key,
  });

  final Widget child;
  final double maxHeight;
  final bool fadeEdges;
  final String semanticLabel;

  @override
  State<AppScrollArea> createState() => _AppScrollAreaState();
}

class _AppScrollAreaState extends State<AppScrollArea> {
  static const _fadeHeight = 16.0;
  static const _scrollbarThickness = 6.0;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderDefault),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            Semantics(
              role: SemanticsRole.region,
              container: true,
              label: widget.semanticLabel,
              child: ScrollbarTheme(
                data: ScrollbarThemeData(
                  thickness: WidgetStateProperty.all(_scrollbarThickness),
                  thumbColor: WidgetStateProperty.all(colors.borderDefault),
                  trackColor: WidgetStateProperty.all(Colors.transparent),
                  radius: const Radius.circular(3),
                  crossAxisMargin: 0,
                  mainAxisMargin: 0,
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: widget.maxHeight),
                    child: SingleChildScrollView(controller: _scrollController, child: widget.child),
                  ),
                ),
              ),
            ),
            if (widget.fadeEdges) ...[
              Positioned(top: 0, left: 0, right: 0, child: _FadeEdgeOverlay(colors: colors, atTop: true)),
              Positioned(bottom: 0, left: 0, right: 0, child: _FadeEdgeOverlay(colors: colors, atTop: false)),
            ],
          ],
        ),
      ),
    );
  }
}

class _FadeEdgeOverlay extends StatelessWidget {
  const _FadeEdgeOverlay({required this.colors, required this.atTop});

  final AppSemanticColors colors;
  final bool atTop;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: _AppScrollAreaState._fadeHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: atTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: atTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [colors.surfaceDefault, colors.surfaceDefault.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
