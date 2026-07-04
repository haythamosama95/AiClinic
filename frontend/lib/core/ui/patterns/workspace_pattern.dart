import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// Logical pane identifiers for [WorkspacePattern] compact layout.
enum WorkspacePane {
  context,
  primary,
  ai,
}

/// Workspace page scaffold — nested resizable panes with dockable AI slot.
///
/// On wide viewports composes nested [AppResizablePanels]: context pane ·
/// primary pane · dockable [AppAiPanel] slot. On smaller widths collapses to
/// [AppSegmentedControl] tabbed panes.
class WorkspacePattern extends StatelessWidget {
  const WorkspacePattern({
    required this.contextPane,
    required this.primaryPane,
    this.title,
    this.headerActions,
    this.aiPane,
    this.aiPaneOpen = true,
    this.onAiPaneToggle,
    this.selectedPane = WorkspacePane.primary,
    this.onPaneChanged,
    this.contextInitialFraction = 0.22,
    this.contextMinFraction = 0.18,
    this.contextMaxFraction = 0.35,
    this.primaryInitialFraction = 0.62,
    this.primaryMinFraction = 0.4,
    this.primaryMaxFraction = 0.75,
    super.key,
  });

  final String? title;
  final Widget? headerActions;
  final Widget contextPane;
  final Widget primaryPane;
  final Widget? aiPane;
  final bool aiPaneOpen;
  final VoidCallback? onAiPaneToggle;
  final WorkspacePane selectedPane;
  final ValueChanged<WorkspacePane>? onPaneChanged;
  final double contextInitialFraction;
  final double contextMinFraction;
  final double contextMaxFraction;
  final double primaryInitialFraction;
  final double primaryMinFraction;
  final double primaryMaxFraction;

  static const List<AppSegmentedOption<WorkspacePane>> _paneOptions = [
    AppSegmentedOption(
      value: WorkspacePane.context,
      label: 'Context',
      icon: LucideIcons.user,
    ),
    AppSegmentedOption(
      value: WorkspacePane.primary,
      label: 'Work',
      icon: LucideIcons.fileText,
    ),
    AppSegmentedOption(
      value: WorkspacePane.ai,
      label: 'AI',
      icon: LucideIcons.sparkles,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = PatternScaffold.useWorkspaceSplit(constraints.maxWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || headerActions != null || onAiPaneToggle != null)
              _WorkspaceHeader(
                title: title,
                actions: headerActions,
                aiPaneOpen: aiPaneOpen,
                onAiPaneToggle: onAiPaneToggle,
                showAiToggle: useSplit && aiPane != null,
              ),
            Expanded(
              child: useSplit
                  ? _WorkspaceSplitLayout(
                      contextPane: contextPane,
                      primaryPane: primaryPane,
                      aiPane: aiPaneOpen ? aiPane : null,
                      contextInitialFraction: contextInitialFraction,
                      contextMinFraction: contextMinFraction,
                      contextMaxFraction: contextMaxFraction,
                      primaryInitialFraction: primaryInitialFraction,
                      primaryMinFraction: primaryMinFraction,
                      primaryMaxFraction: primaryMaxFraction,
                    )
                  : _WorkspaceCompactLayout(
                      contextPane: contextPane,
                      primaryPane: primaryPane,
                      aiPane: aiPane,
                      selectedPane: selectedPane,
                      onPaneChanged: onPaneChanged,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    this.title,
    this.actions,
    this.aiPaneOpen = true,
    this.onAiPaneToggle,
    this.showAiToggle = false,
  });

  final String? title;
  final Widget? actions;
  final bool aiPaneOpen;
  final VoidCallback? onAiPaneToggle;
  final bool showAiToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s2,
        ),
        child: Row(
          children: [
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: typography.bodyStrong.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              )
            else
              const Spacer(),
            if (actions != null) ...[
              actions!,
              const SizedBox(width: AppSpacing.s2),
            ],
            if (showAiToggle && onAiPaneToggle != null)
              AppIconButton(
                icon: aiPaneOpen
                    ? LucideIcons.panelRightClose
                    : LucideIcons.panelRightOpen,
                semanticLabel:
                    aiPaneOpen ? 'Hide AI panel' : 'Show AI panel',
                size: AppIconButtonSize.sm,
                onPressed: onAiPaneToggle,
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSplitLayout extends StatelessWidget {
  const _WorkspaceSplitLayout({
    required this.contextPane,
    required this.primaryPane,
    this.aiPane,
    required this.contextInitialFraction,
    required this.contextMinFraction,
    required this.contextMaxFraction,
    required this.primaryInitialFraction,
    required this.primaryMinFraction,
    required this.primaryMaxFraction,
  });

  final Widget contextPane;
  final Widget primaryPane;
  final Widget? aiPane;
  final double contextInitialFraction;
  final double contextMinFraction;
  final double contextMaxFraction;
  final double primaryInitialFraction;
  final double primaryMinFraction;
  final double primaryMaxFraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final workArea = aiPane != null
        ? AppResizablePanels(
            panels: [
              AppResizablePanel(
                initialFraction: primaryInitialFraction,
                minFraction: primaryMinFraction,
                maxFraction: primaryMaxFraction,
                child: _WorkspacePane(child: primaryPane),
              ),
              AppResizablePanel(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                  child: _WorkspacePane(child: aiPane!),
                ),
              ),
            ],
          )
        : _WorkspacePane(child: primaryPane);

    return AppResizablePanels(
      panels: [
        AppResizablePanel(
          initialFraction: contextInitialFraction,
          minFraction: contextMinFraction,
          maxFraction: contextMaxFraction,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: BorderDirectional(
                end: BorderSide(color: colors.borderSubtle),
              ),
            ),
            child: _WorkspacePane(child: contextPane),
          ),
        ),
        AppResizablePanel(child: workArea),
      ],
    );
  }
}

class _WorkspaceCompactLayout extends StatelessWidget {
  const _WorkspaceCompactLayout({
    required this.contextPane,
    required this.primaryPane,
    this.aiPane,
    required this.selectedPane,
    this.onPaneChanged,
  });

  final Widget contextPane;
  final Widget primaryPane;
  final Widget? aiPane;
  final WorkspacePane selectedPane;
  final ValueChanged<WorkspacePane>? onPaneChanged;

  @override
  Widget build(BuildContext context) {
    final options = aiPane != null
        ? WorkspacePattern._paneOptions
        : WorkspacePattern._paneOptions
            .where((o) => o.value != WorkspacePane.ai)
            .toList();

    final paneContent = switch (selectedPane) {
      WorkspacePane.context => contextPane,
      WorkspacePane.primary => primaryPane,
      WorkspacePane.ai => aiPane ?? const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onPaneChanged != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
            child: AppSegmentedControl<WorkspacePane>(
              options: options,
              value: selectedPane,
              onChanged: onPaneChanged!,
              semanticLabel: 'Workspace panes',
              size: AppSegmentedControlSize.sm,
            ),
          ),
        ],
        Expanded(child: _WorkspacePane(child: paneContent)),
      ],
    );
  }
}

class _WorkspacePane extends StatelessWidget {
  const _WorkspacePane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppScrollArea(child: child);
  }
}
