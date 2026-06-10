import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_content_panel.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Authenticated route shell: header, left nav, and feature content regions.
///
/// Navigation contracts and route definitions remain in [AppRoutes] and
/// [appRouterProvider]. Nav selection is local UI state until wired to routes.
class AuthenticatedShell extends StatefulWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  @override
  State<AuthenticatedShell> createState() => _AuthenticatedShellState();
}

class _AuthenticatedShellState extends State<AuthenticatedShell> {
  late String _selectedItemId;
  late Set<String> _expandedGroupIds;

  @override
  void initState() {
    super.initState();
    _selectedItemId = ShellNavConfig.defaultSelectedId();
    _expandedGroupIds = ShellNavConfig.defaultExpandedGroupIds();
  }

  void _onItemSelected(String itemId) {
    final groupId = ShellNavConfig.groupIdFor(itemId);
    if (groupId != null) {
      setState(() {
        _expandedGroupIds = {..._expandedGroupIds, groupId};
      });
    }

    final route = ShellNavConfig.routeFor(itemId);
    if (route != null) {
      context.go(route);
      return;
    }

    setState(() => _selectedItemId = itemId);
  }

  void _onGroupToggled(String groupId) {
    setState(() {
      if (_expandedGroupIds.contains(groupId)) {
        _expandedGroupIds = {..._expandedGroupIds}..remove(groupId);
      } else {
        _expandedGroupIds = {..._expandedGroupIds, groupId};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final location = GoRouterState.of(context).matchedLocation;
    final selectedItemId = ShellNavConfig.itemIdForLocation(location) ?? _selectedItemId;

    return ColoredBox(
      color: colors.accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellNav(
            selectedItemId: selectedItemId,
            expandedGroupIds: _expandedGroupIds,
            onItemSelected: _onItemSelected,
            onGroupToggled: _onGroupToggled,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ShellHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ShellTokens.contentPanelInset,
                      SpacingTokens.sm,
                      ShellTokens.contentPanelInset,
                      ShellTokens.contentPanelInset,
                    ),
                    child: ShellContentPanel(child: widget.child),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
