import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/settings/presentation/components/settings_rail.dart';
import 'package:ai_clinic/features/settings/presentation/models/settings_screen.dart';
import 'package:ai_clinic/features/settings/presentation/screens/appearance_screen.dart';
import 'package:ai_clinic/features/settings/presentation/screens/notifications_screen.dart';
import 'package:ai_clinic/features/settings/presentation/screens/security_screen.dart';

/// Personal workstation settings hub (web `SettingsPage`).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({this.screenId, super.key});

  final String? screenId;

  static const _breakpoint = 768.0;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late String _activeScreenId;

  @override
  void initState() {
    super.initState();
    _activeScreenId = SettingsScreens.resolve(widget.screenId).id;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resolved = SettingsScreens.resolve(widget.screenId).id;
    if (resolved != _activeScreenId) {
      _activeScreenId = resolved;
    }
  }

  void _onNavigate(String route) {
    final screenId = Uri.parse(route).pathSegments.last;
    if (screenId == _activeScreenId) {
      return;
    }
    setState(() => _activeScreenId = screenId);
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final activeScreen = SettingsScreens.resolve(_activeScreenId);
    final isWide = MediaQuery.sizeOf(context).width >= SettingsPage._breakpoint;

    final content = _SettingsScreenTransition(
      screenId: _activeScreenId,
      child: switch (_activeScreenId) {
        'notifications' => const NotificationsScreen(),
        'security' => const SecurityScreen(),
        _ => const AppearanceScreen(),
      },
    );

    final bodyLayout = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsRail(
                activeScreenId: _activeScreenId,
                onNavigate: _onNavigate,
              ),
              Expanded(child: _SettingsContentArea(child: content)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsRail(
                activeScreenId: _activeScreenId,
                onNavigate: _onNavigate,
              ),
              const SizedBox(height: AppSpacing.space6),
              content,
            ],
          );

    return Semantics(
      liveRegion: true,
      label: 'Viewing ${activeScreen.label} settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.space6,
        children: [
          const AppPageHeader(
            title: 'Settings',
            description: 'Personal preferences for this workstation — theme, alerts, and security.',
          ),
          bodyLayout,
        ],
      ),
    );
  }
}

class _SettingsContentArea extends StatelessWidget {
  const _SettingsContentArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.space8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(start: BorderSide(color: colors.borderSubtle)),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpacing.space8),
          child: child,
        ),
      ),
    );
  }
}

class _SettingsScreenTransition extends StatefulWidget {
  const _SettingsScreenTransition({required this.screenId, required this.child});

  final String screenId;
  final Widget child;

  @override
  State<_SettingsScreenTransition> createState() => _SettingsScreenTransitionState();
}

class _SettingsScreenTransitionState extends State<_SettingsScreenTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotionDuration.base);
    _animation = CurvedAnimation(parent: _controller, curve: AppMotionEasing.standard);
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AppMotion.prefersReducedMotion(context) ? AppMotionDuration.fast : AppMotionDuration.base;
  }

  @override
  void didUpdateWidget(covariant _SettingsScreenTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenId != widget.screenId) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppMotion.animatedPreset(
      context: context,
      preset: AppMotionPreset.fadeScale,
      animation: _animation,
      child: widget.child,
    );
  }
}
