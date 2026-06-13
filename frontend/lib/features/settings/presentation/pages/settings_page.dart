import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/clinic_setup_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/general_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_tab_bar.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_roles_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_settings_tab.dart';

/// Clinic workstation settings hub with a scrollable section tab header.
class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialTabId = SettingsTabs.defaultTabId, super.key});

  final String initialTabId;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _tabTransitionDuration = Duration(milliseconds: 220);

  late String _selectedTabId;
  var _tabTransitionDirection = 1;

  @override
  void initState() {
    super.initState();
    _selectedTabId = SettingsTabs.byId(widget.initialTabId)?.id ?? SettingsTabs.defaultTabId;
  }

  void _onTabSelected(String tabId) {
    if (tabId == _selectedTabId) {
      return;
    }

    final currentIndex = _tabIndexFor(_selectedTabId);
    final nextIndex = _tabIndexFor(tabId);

    setState(() {
      _tabTransitionDirection = nextIndex >= currentIndex ? 1 : -1;
      _selectedTabId = tabId;
    });
  }

  int _tabIndexFor(String tabId) {
    return SettingsTabs.all.indexWhere((tab) => tab.id == tabId);
  }

  Widget _tabContentFor(String tabId) {
    return switch (tabId) {
      'clinic-setup' => const ClinicSetupSettingsTab(),
      'staff' => const StaffSettingsTab(),
      'staff-roles' => const StaffRolesSettingsTab(),
      _ => const GeneralSettingsTab(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Material(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTabBar(tabs: SettingsTabs.all, selectedTabId: _selectedTabId, onTabSelected: _onTabSelected),
          Expanded(
            child: AnimatedSwitcher(
              duration: _tabTransitionDuration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, if (currentChild != null) currentChild],
                );
              },
              transitionBuilder: (child, animation) {
                final slideAnimation = Tween<Offset>(
                  begin: Offset(0.012 * _tabTransitionDirection, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slideAnimation, child: child),
                );
              },
              child: KeyedSubtree(key: ValueKey<String>(_selectedTabId), child: _tabContentFor(_selectedTabId)),
            ),
          ),
        ],
      ),
    );
  }
}
