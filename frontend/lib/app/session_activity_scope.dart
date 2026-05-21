import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Resets the idle-timeout timer on keyboard and pointer input (FR-005a).
class SessionActivityScope extends ConsumerWidget {
  const SessionActivityScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idle = ref.watch(idleTimeoutServiceProvider);
    final trackKeyboard = ref.watch(authSessionProvider.select((session) => session.isAuthenticated));

    final pointerScope = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => idle.recordActivity(),
      onPointerSignal: (_) => idle.recordActivity(),
      child: child,
    );

    if (!trackKeyboard) {
      return pointerScope;
    }

    return Focus(
      autofocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          idle.recordActivity();
        }
        return KeyEventResult.ignored;
      },
      child: pointerScope,
    );
  }
}
