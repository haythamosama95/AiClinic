import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/app/session_activity_scope.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/state/locale_direction_provider.dart';

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
    final locale = ref.watch(localeDirectionProvider).locale;

    return SessionActivityScope(
      child: MaterialApp.router(
        title: 'AiClinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleDirectionState.supportedLocales,
        routerConfig: router,
        // Text outside a [Material] ancestor inherits MaterialApp's debug
        // fallback style (double yellow underline). Transparent [Material]
        // applies the theme text style app-wide.
        builder: (context, child) {
          if (child == null) {
            return const SizedBox.shrink();
          }
          return Material(type: MaterialType.transparency, child: child);
        },
      ),
    );
  }
}
