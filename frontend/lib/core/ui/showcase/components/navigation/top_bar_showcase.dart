import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class TopBarShowcase extends ConsumerStatefulWidget {
  const TopBarShowcase({super.key});

  @override
  ConsumerState<TopBarShowcase> createState() => _TopBarShowcaseState();
}

class _TopBarShowcaseState extends ConsumerState<TopBarShowcase> {
  String _branchId = mockBranches.first.id;

  bool get _isDark {
    final mode = ref.watch(themeModeProvider);
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final localeState = ref.watch(appLocaleProvider);

    return ShowcaseSection(
      title: 'App top bar',
      description:
          'Sticky chrome with command trigger, branch switcher, notification badge, theme toggle, and user menu.',
      child: ShowcaseDemo(
        label: 'Default composition',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: colors.borderDefault),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: AppTopBar(
              pageContext: const AppBreadcrumb(
                items: [
                  BreadcrumbItem(label: 'Patients', href: '#'),
                  BreadcrumbItem(label: 'Layla Hassan'),
                ],
              ),
              branches: mockBranches,
              currentBranchId: _branchId,
              onBranchChange: (id) => setState(() => _branchId = id),
              user: mockUser,
              notificationCount: mockNotificationCount,
              isDark: _isDark,
              onToggleTheme: () =>
                  setAppThemeMode(ref, _isDark ? ThemeMode.light : ThemeMode.dark),
              locale: localeState.locale,
              onLocaleChange: (locale) =>
                  ref.read(appLocaleProvider.notifier).setLocale(locale),
            ),
          ),
        ),
      ),
    );
  }
}
