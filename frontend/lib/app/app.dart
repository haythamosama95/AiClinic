import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/app/session_activity_scope.dart';
import 'package:ai_clinic/core/ui/providers/locale_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/app/shell/dev/shell_dev_design_system_launcher.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Root widget that wires together startup state, routing, and theming.
class AiClinicApp extends ConsumerStatefulWidget {
  const AiClinicApp({super.key});

  @override
  ConsumerState<AiClinicApp> createState() => _AiClinicAppState();
}

class _AiClinicAppState extends ConsumerState<AiClinicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Delay bootstrap until the widget is mounted and the provider tree exists.
    Future<void>.microtask(() async {
      // Load persisted idle timeout before bootstrap can restore an authenticated session.
      await ref.read(idleTimeoutSettingsProvider.future);
      await ref.read(startupSessionProvider.notifier).bootstrap();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    final auth = ref.read(authSessionProvider);
    if (!auth.isAuthenticated || auth.context!.setupRequired) {
      return;
    }

    unawaited(ref.read(authSessionProvider.notifier).reloadContext());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final localeState = ref.watch(appLocaleProvider);

    return SessionActivityScope(
      child: MaterialApp.router(
        title: 'AiClinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(locale: localeState.flutterLocale),
        darkTheme: AppTheme.dark(locale: localeState.flutterLocale),
        themeMode: themeMode,
        locale: localeState.flutterLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          return Directionality(
            textDirection: localeState.textDirection,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                const ShellDevDesignSystemLauncher(),
              ],
            ),
          );
        },
        routerConfig: router,
      ),
    );
  }
}
