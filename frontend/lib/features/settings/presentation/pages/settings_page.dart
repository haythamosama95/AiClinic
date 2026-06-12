import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/clinic_setup_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/general_settings_tab.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_tab_bar.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_roles_settings_tab.dart';

/// Clinic workstation settings hub with a scrollable section tab header.
class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialTabId = SettingsTabs.defaultTabId, super.key});

  final String initialTabId;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _selectedTabId;

  @override
  void initState() {
    super.initState();
    _selectedTabId = SettingsTabs.byId(widget.initialTabId)?.id ?? SettingsTabs.defaultTabId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    return Material(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTabBar(
            tabs: SettingsTabs.all,
            selectedTabId: _selectedTabId,
            onTabSelected: (tabId) => setState(() => _selectedTabId = tabId),
          ),
          Expanded(child: _SettingsTabBody(selectedTabId: _selectedTabId)),
        ],
      ),
    );
  }
}

class _SettingsTabBody extends StatelessWidget {
  const _SettingsTabBody({required this.selectedTabId});

  final String selectedTabId;

  @override
  Widget build(BuildContext context) {
    return switch (selectedTabId) {
      'clinic-setup' => const ClinicSetupSettingsTab(),
      'staff-roles' => const StaffRolesSettingsTab(),
      _ => const GeneralSettingsTab(),
    };
  }
}
