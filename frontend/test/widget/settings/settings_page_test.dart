import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/variants/app_theme_variant.dart';
import 'package:ai_clinic/app/shell/authenticated_shell.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/pages/settings_page.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_tab_bar.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/data/staff_admin_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/domain/organization_profile.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';
import 'package:ai_clinic/features/setup/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../shell/shell_test_support.dart';
import '../../helpers/auth_test_support.dart';
import '../../support/settings_table_test_client.dart';

class _SettingsAdminAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        role: StaffRole.administrator,
        permissions: {'settings.manage_staff', 'settings.manage_branches'},
      ),
    );
  }
}

class _SettingsDoctorAuthNotifier extends TestAuthSessionNotifier {
  @override
  AuthSessionState build() {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(role: StaffRole.doctor, permissions: {'patients.view'}),
    );
  }
}

class _TestIdleTimeoutSettingsNotifier extends IdleTimeoutSettingsNotifier {
  @override
  Future<IdleTimeoutSettingsState> build() async => const IdleTimeoutSettingsState(duration: Duration(minutes: 15));
}

void main() {
  group('SettingsPage', () {
    Future<void> pumpSettingsPage(
      WidgetTester tester, {
      Size size = shellSurfaceSize,
      bool withStaffAndRoles = false,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final overrides = [
        authSessionProvider.overrideWith(_SettingsAdminAuthNotifier.new),
        idleTimeoutSettingsProvider.overrideWith(_TestIdleTimeoutSettingsNotifier.new),
        clinicSetupOrganizationProvider.overrideWith(
          (ref) async => const OrganizationProfile(
            id: 'org-1',
            name: 'Demo Clinic',
            currencyCode: 'EGP',
            timezone: 'Africa/Cairo',
          ),
        ),
        clinicSetupBranchesProvider.overrideWith(
          (ref) async => const [BranchListItem(id: 'branch-1', name: 'Main Branch', isActive: true, code: 'MAIN')],
        ),
      ];

      if (withStaffAndRoles) {
        overrides.addAll([
          rolePermissionsRepositoryProvider.overrideWithValue(
            RolePermissionsRepositoryImpl(
              SettingsTableTestClient({
                'roles_permissions': [
                  {
                    'role': 'administrator',
                    'permission_key': 'settings.manage_branches',
                    'is_granted': true,
                    'is_deleted': false,
                  },
                  {
                    'role': 'doctor',
                    'permission_key': 'settings.manage_branches',
                    'is_granted': false,
                    'is_deleted': false,
                  },
                ],
              }),
            ),
          ),
          staffAdminRepositoryProvider.overrideWithValue(
            StaffAdminRepositoryImpl(
              SettingsTableTestClient({
                'staff_members': [
                  {
                    'id': '00000000-0000-4000-8000-000000000101',
                    'full_name': 'Dr. Smith',
                    'role': 'doctor',
                    'is_active': true,
                    'is_deleted': false,
                  },
                  {
                    'id': '00000000-0000-4000-8000-000000000102',
                    'full_name': 'Former Receptionist',
                    'role': 'receptionist',
                    'is_active': false,
                    'is_deleted': false,
                  },
                ],
              }),
            ),
          ),
          staffAssignableBranchesProvider.overrideWith(
            (ref) async => const [BranchSummary(id: 'branch-1', name: 'Main Branch')],
          ),
        ]);
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('doctor does not see clinic setup tab', (tester) async {
      await tester.binding.setSurfaceSize(shellSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_SettingsDoctorAuthNotifier.new),
            idleTimeoutSettingsProvider.overrideWith(_TestIdleTimeoutSettingsNotifier.new),
            clinicSetupOrganizationProvider.overrideWith(
              (ref) async => const OrganizationProfile(id: 'org-1', name: 'Demo Clinic'),
            ),
            clinicSetupBranchesProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Clinic Setup'), findsNothing);
      expect(find.text('Staff Management'), findsOneWidget);
      expect(find.text('Staff Roles'), findsOneWidget);
    });

    testWidgets('renders all settings tabs for administrator', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.byType(SettingsTabBar), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Clinic Setup'), findsOneWidget);
      expect(find.text('Staff Management'), findsOneWidget);
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

      expect(find.byType(SettingsSectionCard), findsNWidgets(2));
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Idle sign-out'), findsOneWidget);
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
      final cardBoxes = tester.renderObjectList<RenderBox>(find.byType(SettingsSectionCard));
      final expectedHalfWidth = (gridBox.size.width - SpacingTokens.lg) / 2;

      for (final cardBox in cardBoxes) {
        expect(cardBox.size.width, closeTo(expectedHalfWidth, 1));
      }
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

    testWidgets('tab content uses AnimatedSwitcher with 220ms duration', (tester) async {
      await pumpSettingsPage(tester);

      final switcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, const Duration(milliseconds: 220));
    });

    testWidgets('switching tabs updates visible content', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsNothing);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Clinic Setup')));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsNothing);
      expect(find.text('Demo Clinic'), findsOneWidget);
    });

    testWidgets('re-tapping active tab does not change content', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.text('Appearance'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('General')));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsNothing);
    });

    testWidgets('tab switch uses slide and fade transition', (tester) async {
      await pumpSettingsPage(tester);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Clinic Setup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SlideTransition), findsWidgets);
      expect(find.byType(FadeTransition), findsWidgets);
    });

    testWidgets('invalid initialTabId falls back to General', (tester) async {
      await tester.binding.setSurfaceSize(shellSurfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(_SettingsAdminAuthNotifier.new),
            idleTimeoutSettingsProvider.overrideWith(_TestIdleTimeoutSettingsNotifier.new),
            clinicSetupOrganizationProvider.overrideWith(
              (ref) async => const OrganizationProfile(id: 'org-1', name: 'Demo Clinic'),
            ),
            clinicSetupBranchesProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: const Scaffold(body: SettingsPage(initialTabId: 'bogus')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsNothing);
    });

    testWidgets('theme variant selection updates provider', (tester) async {
      await pumpSettingsPage(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
      expect(container.read(themeVariantProvider), AppThemeVariant.parchment);

      await tester.tap(find.text('Astro Vista'));
      await tester.pumpAndSettle();

      expect(container.read(themeVariantProvider), AppThemeVariant.clinic);
    });

    testWidgets('single card on narrow viewport stacks full width', (tester) async {
      await pumpSettingsPage(tester, size: const Size(400, 800));

      final gridBox = tester.renderObject<RenderBox>(find.byType(SettingsCardsGrid));
      final cardBoxes = tester.renderObjectList<RenderBox>(find.byType(SettingsSectionCard));

      for (final cardBox in cardBoxes) {
        expect(cardBox.size.width, closeTo(gridBox.size.width, 1));
      }
    });

    testWidgets('stupid usage: rapid theme toggling', (tester) async {
      await pumpSettingsPage(tester);

      final container = ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.text(i.isEven ? 'Dark' : 'Light'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(container.read(themeModeProvider), ThemeMode.light);
    });

    testWidgets('tab icons render for each definition', (tester) async {
      await pumpSettingsPage(tester);

      expect(find.byIcon(Icons.tune_outlined), findsOneWidget);
      expect(find.byIcon(Icons.apartment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.people_outlined), findsOneWidget);
      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);
    });

    testWidgets('forward tab switch uses positive slide direction', (tester) async {
      await pumpSettingsPage(tester);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Clinic Setup')));
      await tester.pump();

      final slide = tester.widget<SlideTransition>(find.byType(SlideTransition).last);
      expect(slide.position.value.dx, greaterThan(0));
    });

    testWidgets('backward tab switch uses negative slide direction', (tester) async {
      await pumpSettingsPage(tester);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Staff Roles')));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('General')));
      await tester.pump();

      final slide = tester.widget<SlideTransition>(find.byType(SlideTransition).last);
      expect(slide.position.value.dx, lessThan(0));
    });

    testWidgets('stack layout keeps outgoing child during transition', (tester) async {
      await pumpSettingsPage(tester);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Clinic Setup')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Demo Clinic'), findsOneWidget);
    });

    testWidgets('rapid tab switching queues cleanly', (tester) async {
      await pumpSettingsPage(tester);

      final tabs = ['Clinic Setup', 'Staff Management', 'Staff Roles', 'General', 'Staff Management'];
      for (final tab in tabs) {
        await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text(tab)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Staff Management'), findsOneWidget);
      expect(find.text('Appearance'), findsNothing);
    });

    testWidgets('administrator can open permissions via staff-roles tab', (tester) async {
      await pumpSettingsPage(tester, withStaffAndRoles: true);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Staff Roles')));
      await tester.pumpAndSettle();

      expect(find.text('Manage Branches'), findsOneWidget);
      expect(find.textContaining('administrators'), findsNothing);
    });

    testWidgets('screen reader settings tabs announce selection', (tester) async {
      await pumpSettingsPage(tester);

      final generalSemantics = tester.getSemantics(find.text('General'));
      final clinicSemantics = tester.getSemantics(find.text('Clinic Setup'));

      expect(generalSemantics.flagsCollection.isSelected, isTrue);
      expect(clinicSemantics.flagsCollection.isSelected, isFalse);
    });

    testWidgets('filter popover dismissed when switching settings tab', (tester) async {
      await pumpSettingsPage(tester, withStaffAndRoles: true);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('Staff Management')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(SettingsTabBar), matching: find.text('General')));
      await tester.pumpAndSettle();

      expect(find.text('Filters'), findsNothing);
      expect(find.text('Appearance'), findsOneWidget);
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
          overrides: [idleTimeoutSettingsProvider.overrideWith(_TestIdleTimeoutSettingsNotifier.new)],
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
