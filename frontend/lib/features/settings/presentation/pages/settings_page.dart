import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/pages/role_permissions_page.dart';
import 'package:ai_clinic/features/settings/presentation/pages/staff_list_page.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_clinic_setup_tab_content.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_general_tab_content.dart';

/// Clinic workstation settings hub with section tabs.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({this.initialTabId = SettingsTabs.defaultTabId, super.key});

  final String initialTabId;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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

    final visibleTabs = SettingsTabs.visibleFor(ref.read(authSessionProvider));
    final currentIndex = visibleTabs.indexWhere((tab) => tab.id == _selectedTabId);
    final nextIndex = visibleTabs.indexWhere((tab) => tab.id == tabId);

    setState(() {
      _tabTransitionDirection = nextIndex >= currentIndex ? 1 : -1;
      _selectedTabId = tabId;
    });
  }

  String _resolveSelectedTabId(List<SettingsTabDefinition> visibleTabs) {
    if (visibleTabs.any((tab) => tab.id == _selectedTabId)) {
      return _selectedTabId;
    }
    return visibleTabs.first.id;
  }

  Widget _tabContentFor(String tabId) {
    return switch (tabId) {
      'clinic-setup' => const SettingsClinicSetupTabContent(),
      'staff' => const StaffListPage(embedded: true),
      'staff-roles' => const RolePermissionsPage(embedded: true),
      _ => const SettingsGeneralTabContent(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final visibleTabs = SettingsTabs.visibleFor(ref.watch(authSessionProvider));
    final selectedTabId = _resolveSelectedTabId(visibleTabs);
    final reduced = AppMotion.reduced(context);
    final duration = AppMotion.resolvePreset(AppMotionPreset.tab, reduced: reduced).duration;

    if (selectedTabId != _selectedTabId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedTabId = selectedTabId);
        }
      });
    }

    return ColoredBox(
      color: context.colors.surfaceCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.s6,
              AppSpacing.s6,
              AppSpacing.s6,
              AppSpacing.s4,
            ),
            child: AppPageHeader(
              title: 'Settings',
              description: 'Clinic preferences, integrations, and account configuration.',
              tabs: AppTabs(
                items: [
                  for (final tab in visibleTabs)
                    AppTabItem(id: tab.id, label: tab.label),
                ],
                selectedId: selectedTabId,
                onChanged: _onTabSelected,
                semanticLabel: 'Settings sections',
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: AppEasings.standard,
              switchOutCurve: AppEasings.standard,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  alignment: AlignmentDirectional.topCenter,
                  children: [...previousChildren, ?currentChild],
                );
              },
              transitionBuilder: (child, animation) {
                if (reduced) {
                  return FadeTransition(opacity: animation, child: child);
                }
                final slideAnimation = Tween<Offset>(
                  begin: Offset(0.012 * _tabTransitionDirection, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: AppEasings.standard));
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slideAnimation, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>(selectedTabId),
                child: _tabContentFor(selectedTabId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
