import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/layout/shell_page_transition.dart';

/// Cross-screen page transition wrapper (web `ScreenPanel` motion aligned with shell pages).
///
/// Fade + vertical slide, keyed on [screenKey]. Respects reduced motion.
class SettingsScreenPanel extends StatelessWidget {
  const SettingsScreenPanel({required this.screenKey, required this.child, super.key});

  final String screenKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShellPageTransition(pageKey: screenKey, child: child, builder: (context, content, _) => content);
  }
}
