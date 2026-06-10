import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/router.dart';
import 'package:ai_clinic/app/session_activity_scope.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/settings/application/idle_timeout_settings_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/app/providers/startup_session_provider.dart';
import 'package:ai_clinic/app/providers/theme_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

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
      await ref.read(startupSessionProvider.notifier).bootstrap();
      // Load persisted idle timeout before the first authenticated session.
      await ref.read(idleTimeoutSettingsProvider.future);
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

    unawaited(ref.read(authNotifierProvider.notifier).reloadContext());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final themeVariant = ref.watch(themeVariantProvider);

    return SessionActivityScope(
      child: MaterialApp.router(
        title: 'AiClinic',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(themeVariant),
        darkTheme: AppTheme.dark(themeVariant),
        themeMode: themeMode,
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router,
      ),
    );
  }
}
