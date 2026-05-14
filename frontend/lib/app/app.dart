import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/providers/startup_session_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';

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
    Future<void>.microtask(() {
      return ref.read(startupSessionProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final startupSession = ref.watch(startupSessionProvider);

    // Theme mode comes from startup session state so it can be toggled early.
    return MaterialApp.router(
      title: 'AiClinic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: startupSession.themeMode,
      routerConfig: router,
    );
  }
}
