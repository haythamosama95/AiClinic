import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// Master–detail page scaffold — split panels on wide, drawer on narrow.
///
/// On [AppBreakpoints.lg] and above, composes [AppResizablePanels] with list
/// (inline-start) and detail (inline-end). Below that breakpoint the list
/// fills the scaffold and the detail pane opens in a controlled overlay
/// [AppDrawer] when [detailOpen] is true. Call [onDetailOpen] from list
/// selection to request detail presentation on narrow viewports (parent may
/// alternatively navigate to a detail route).
class MasterDetailPattern extends StatelessWidget {
  const MasterDetailPattern({
    required this.listPane,
    required this.detailPane,
    this.detailOpen = false,
    this.onDetailOpen,
    this.onDetailClose,
    this.drawerTitle,
    this.drawerDescription,
    this.drawerFooter,
    this.initialListFraction = 0.45,
    this.listMinFraction = 0.25,
    this.listMaxFraction = 0.65,
    this.drawerSize = AppDrawerSize.md,
    super.key,
  });

  final Widget listPane;
  final Widget detailPane;
  final bool detailOpen;
  final VoidCallback? onDetailOpen;
  final VoidCallback? onDetailClose;
  final String? drawerTitle;
  final String? drawerDescription;
  final Widget? drawerFooter;
  final double initialListFraction;
  final double listMinFraction;
  final double listMaxFraction;
  final AppDrawerSize drawerSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = PatternScaffold.useSplitLayout(constraints.maxWidth);

        if (useSplit) {
          return AppResizablePanels(
            panels: [
              AppResizablePanel(
                initialFraction: initialListFraction,
                minFraction: listMinFraction,
                maxFraction: listMaxFraction,
                child: _MasterDetailPane(bordered: true, child: listPane),
              ),
              AppResizablePanel(
                child: _MasterDetailPane(child: detailPane),
              ),
            ],
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            _MasterDetailPane(child: listPane),
            if (detailOpen)
              Positioned.fill(
                child: _MasterDetailDrawerOverlay(
                  title: drawerTitle ?? '',
                  description: drawerDescription,
                  body: detailPane,
                  footer: drawerFooter,
                  size: drawerSize,
                  onClose: onDetailClose,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MasterDetailPane extends StatelessWidget {
  const _MasterDetailPane({
    required this.child,
    this.bordered = false,
  });

  final Widget child;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget pane = AppScrollArea(child: child);

    if (bordered) {
      pane = DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            end: BorderSide(color: colors.borderSubtle),
          ),
        ),
        child: pane,
      );
    }

    return pane;
  }
}

class _MasterDetailDrawerOverlay extends StatelessWidget {
  const _MasterDetailDrawerOverlay({
    required this.title,
    required this.body,
    required this.size,
    this.description,
    this.footer,
    this.onClose,
  });

  final String title;
  final String? description;
  final Widget body;
  final Widget? footer;
  final AppDrawerSize size;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          GestureDetector(
            onTap: onClose,
            child: ColoredBox(
              color: colors.surfaceBackdrop,
              child: const SizedBox.expand(),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: _drawerWidth(size, context),
              height: double.infinity,
              child: AppDrawer(
                title: title,
                description: description,
                body: body,
                footer: footer,
                size: size,
                onClose: onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _drawerWidth(AppDrawerSize size, BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return switch (size) {
      AppDrawerSize.sm => (screenWidth * 0.4).clamp(280.0, 400.0),
      AppDrawerSize.md => (screenWidth * 0.5).clamp(320.0, 480.0),
      AppDrawerSize.lg => (screenWidth * 0.6).clamp(400.0, 640.0),
    };
  }
}
