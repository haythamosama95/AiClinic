import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/app/session_activity_scope.dart';
import 'package:ai_clinic/app/theme/app_theme.dart';
import 'package:ai_clinic/features/settings/presentation/providers/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/shared/providers/startup_session_provider.dart';
import 'package:ai_clinic/shared/providers/theme_provider.dart';

/// Root widget that wires together startup state, routing, and theming.
class AiClinicApp extends ConsumerStatefulWidget {
  const AiClinicApp({super.key});

  @override
  ConsumerState<AiClinicApp> createState() => _AiClinicAppState();
}

class _AiClinicAppState extends ConsumerState<AiClinicApp> {
  @override
  void initState() {
    super.initState();

    // Delay bootstrap until the widget is mounted and the provider tree exists.
    Future<void>.microtask(() async {
      await ref.read(startupSessionProvider.notifier).bootstrap();
      // Load persisted idle timeout before the first authenticated session.
      await ref.read(idleTimeoutSettingsProvider.future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return SessionActivityScope(
      child: MaterialApp.router(
        title: 'AiClinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: themeMode,
        routerConfig: router,
      ),
    );
  }
}
