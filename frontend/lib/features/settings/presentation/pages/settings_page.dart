import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/settings/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_nav_rail.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_screen_panel.dart';

const _lgBreakpoint = 1024.0;
const _navRailWidth = 224.0;

/// Settings page shell with a fixed nav rail and animated screen content (web `SettingsPage`).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the full URI path: inside [ShellRoute], [GoRouterState.matchedLocation] is
    // only the leaf segment (e.g. `setup`), not `/settings/setup`.
    final location = GoRouterState.of(context).uri.path;
    final setupLocked = ref.watch(authSessionProvider).context?.needsClinicSetup ?? false;
    final activeScreen = AppRoutes.settingsScreenFromPath(location);
    final activeMeta = settingsScreens.firstWhere(
      (screen) => screen.id == activeScreen,
      orElse: () => settingsScreens.first,
    );

    final mainPanel = SettingsScreenPanel(screenKey: location, child: child);

    final header = const AppPageHeader(
      title: 'Settings',
      description: 'Configure your clinic, team, and operational defaults.',
    );

    final liveRegion = Semantics(
      liveRegion: true,
      label: 'Viewing ${activeMeta.label} settings',
      child: const SizedBox.shrink(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final body = _SettingsBody(mainPanel: mainPanel, activeScreen: activeScreen, setupLocked: setupLocked);

        if (constraints.hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: AppSpacing.space8),
              Expanded(child: body),
              liveRegion,
            ],
          );
        }

        final viewportHeight =
            MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).vertical -
            AppShellTokens.topBarHeight -
            (AppSpacing.space6 * 2);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: AppSpacing.space8),
            SizedBox(height: viewportHeight.clamp(320, double.infinity), child: body),
            liveRegion,
          ],
        );
      },
    );
  }
}

/// Nav rail and screen content with independent scroll regions on large screens.
class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.mainPanel, required this.activeScreen, required this.setupLocked});

  final Widget mainPanel;
  final String activeScreen;
  final bool setupLocked;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth >= _lgBreakpoint;
        final navRail = SettingsNavRail(
          active: activeScreen,
          isItemEnabled: setupLocked ? (id) => id == 'setup' : null,
          onNavigate: (id) {
            if (setupLocked && id != 'setup') {
              return;
            }
            context.go(AppRoutes.settingsScreenPath(id));
          },
        );

        final scrollablePanel = SingleChildScrollView(primary: true, child: mainPanel);

        if (isLarge) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _navRailWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.space2),
                  child: navRail,
                ),
              ),
              const SizedBox(width: AppSpacing.space12),
              Expanded(child: scrollablePanel),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            navRail,
            const SizedBox(height: AppSpacing.space8),
            Expanded(child: scrollablePanel),
          ],
        );
      },
    );
  }
}
