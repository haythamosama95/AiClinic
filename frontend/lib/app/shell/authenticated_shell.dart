import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/config/shell_nav_config.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

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
    setState(() {
      _selectedItemId = itemId;
      final groupId = ShellNavConfig.groupIdFor(itemId);
      if (groupId != null) {
        _expandedGroupIds = {..._expandedGroupIds, groupId};
      }
    });
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
    final title = ShellNavConfig.labelFor(_selectedItemId) ?? 'Dashboard';

    return ColoredBox(
      color: colors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellNav(
            selectedItemId: _selectedItemId,
            expandedGroupIds: _expandedGroupIds,
            onItemSelected: _onItemSelected,
            onGroupToggled: _onGroupToggled,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShellHeader(title: title),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
