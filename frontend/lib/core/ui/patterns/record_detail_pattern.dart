import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// Record detail page scaffold — header, tabs, and section body slots.
///
/// Composes [AppPageHeader] (title + status badge + actions + optional
/// [AppTabs]) → [body]. Callers place [AppDescriptionList], related
/// [AppTable], and [AppTimeline] widgets in [body] per active tab.
class RecordDetailPattern extends StatelessWidget {
  const RecordDetailPattern({
    required this.title,
    required this.body,
    this.description,
    this.breadcrumb,
    this.statusBadge,
    this.actions,
    this.tabs,
    this.selectedTabId,
    this.onTabChanged,
    this.tabItems,
    this.tabsSemanticLabel = 'Record sections',
    super.key,
  });

  final String title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? statusBadge;
  final Widget? actions;
  final Widget? tabs;
  final List<AppTabItem>? tabItems;
  final String? selectedTabId;
  final ValueChanged<String>? onTabChanged;
  final String tabsSemanticLabel;
  final Widget body;

  Widget? get _resolvedTabs {
    if (tabs != null) return tabs;
    if (tabItems == null ||
        selectedTabId == null ||
        onTabChanged == null) {
      return null;
    }
    return AppTabs(
      items: tabItems!,
      selectedId: selectedTabId!,
      onChanged: onTabChanged!,
      semanticLabel: tabsSemanticLabel,
    );
  }

  Widget? get _resolvedActions {
    if (statusBadge == null && actions == null) return null;
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ?statusBadge,
        ?actions,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PatternScaffold.pagePadding(constraints.maxWidth);

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageHeader(
                title: title,
                description: description,
                breadcrumb: breadcrumb,
                actions: _resolvedActions,
                tabs: _resolvedTabs,
              ),
              const SizedBox(height: PatternScaffold.sectionGap - AppSpacing.s2),
              Expanded(
                child: AppScrollArea(child: body),
              ),
            ],
          ),
        );
      },
    );
  }
}
