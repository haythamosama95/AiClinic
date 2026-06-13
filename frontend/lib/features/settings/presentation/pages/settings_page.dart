import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/clinic_setup_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/general_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_tab_bar.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_roles_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_settings_tab.dart';

/// Clinic workstation settings hub with a scrollable section tab header.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({this.initialTabId = SettingsTabs.defaultTabId, super.key});

  final String initialTabId;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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

    final visibleTabs = _visibleTabs;
    final currentIndex = visibleTabs.indexWhere((tab) => tab.id == _selectedTabId);
    final nextIndex = visibleTabs.indexWhere((tab) => tab.id == tabId);

    setState(() {
      _tabTransitionDirection = nextIndex >= currentIndex ? 1 : -1;
      _selectedTabId = tabId;
    });
  }

  List<SettingsTabDefinition> get _visibleTabs {
    return SettingsTabs.visibleFor(ref.read(authSessionProvider));
  }

  String _resolveSelectedTabId(List<SettingsTabDefinition> visibleTabs) {
    if (visibleTabs.any((tab) => tab.id == _selectedTabId)) {
      return _selectedTabId;
    }
    return visibleTabs.first.id;
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
    final visibleTabs = SettingsTabs.visibleFor(ref.watch(authSessionProvider));
    final selectedTabId = _resolveSelectedTabId(visibleTabs);

    if (selectedTabId != _selectedTabId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedTabId = selectedTabId);
        }
      });
    }

    return Material(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTabBar(tabs: visibleTabs, selectedTabId: selectedTabId, onTabSelected: _onTabSelected),
          Expanded(
            child: AnimatedSwitcher(
              duration: _tabTransitionDuration,
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeOut,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.topCenter,
                  children: [...previousChildren, ?currentChild],
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
              child: KeyedSubtree(key: ValueKey<String>(selectedTabId), child: _tabContentFor(selectedTabId)),
            ),
          ),
        ],
      ),
    );
  }
}
