import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../shell/shell_test_support.dart';

void main() {
  group('SettingsPage', () {
    Future<void> pumpSettingsPage(WidgetTester tester, {Size size = shellSurfaceSize}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders all settings tabs', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.byType(SettingsTabBar), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Clinic Setup'), findsOneWidget);
      expect(find.text('Staff Roles'), findsOneWidget);
    });

    testWidgets('selecting a tab switches content and primary color', (tester) async {
      await pumpSettingsPage(tester);

      final colors = tester.element(find.byType(SettingsPage)).semanticColors;

      final tabBar = find.byType(SettingsTabBar);
      final generalText = tester.widget<Text>(find.descendant(of: tabBar, matching: find.text('General')));
      expect(generalText.style?.color, colors.primary);

      await tester.tap(find.descendant(of: tabBar, matching: find.text('Clinic Setup')));
      await tester.pumpAndSettle();

      final clinicSetupText = tester.widget<Text>(find.descendant(of: tabBar, matching: find.text('Clinic Setup')));
      expect(clinicSetupText.style?.color, colors.primary);

      final generalTextAfter = tester.widget<Text>(find.descendant(of: tabBar, matching: find.text('General')));
      expect(generalTextAfter.style?.color, colors.mutedForeground);
    });

    testWidgets('general tab shows appearance settings card', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.byType(SettingsSectionCard), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Color mode'), findsOneWidget);
      expect(find.text('Astro Vista'), findsOneWidget);
      expect(find.text('Claude+'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
    });

    testWidgets('settings cards use half page width in two-column grid', (tester) async {
      await pumpSettingsPage(tester, size: const Size(1000, 800));

      final gridBox = tester.renderObject<RenderBox>(find.byType(SettingsCardsGrid));
      final cardBox = tester.renderObject<RenderBox>(find.byType(SettingsSectionCard));
      final expectedHalfWidth = (gridBox.size.width - SpacingTokens.lg) / 2;

      expect(cardBox.size.width, closeTo(expectedHalfWidth, 1));
    });

    testWidgets('appearance card updates color mode selection', (tester) async {
      await pumpSettingsPage(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
      expect(container.read(themeModeProvider), ThemeMode.light);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.dark);
    });

    testWidgets('tab bar is horizontally scrollable when tabs overflow', (tester) async {
      await pumpSettingsPage(tester, size: const Size(240, 600));

      final scrollable = find.descendant(of: find.byType(SettingsTabBar), matching: find.byType(Scrollable));
      expect(scrollable, findsOneWidget);

      final scrollableState = tester.state<ScrollableState>(scrollable);
      expect(scrollableState.position.maxScrollExtent, greaterThan(0));
    });
  });

  group('Settings navigation', () {
    GoRouter settingsShellRouter() {
      return GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          ShellRoute(
            builder: (context, state, child) => AuthenticatedShell(child: child),
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const Scaffold(body: Text('Home content')),
              ),
              GoRoute(path: AppRoutes.settings, builder: (_, _) => const SettingsPage()),
            ],
          ),
        ],
      );
    }

    testWidgets('settings header button navigates to settings page', (tester) async {
      await tester.binding.setSurfaceSize(shellSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            routerConfig: settingsShellRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home content'), findsOneWidget);
      expect(find.text('General'), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Home content'), findsNothing);
      expect(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('General')), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
