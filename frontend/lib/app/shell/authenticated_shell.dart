import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/widgets/shell_header_placeholder.dart';
import 'package:ai_clinic/app/shell/widgets/shell_nav_placeholder.dart';

/// Authenticated route shell: header, left nav, and feature content regions.
///
/// Navigation contracts and route definitions remain in [AppRoutes] and
/// [appRouterProvider]. Nav and header are placeholders until implemented.
class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ShellHeaderPlaceholder(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShellNavPlaceholder(),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}
