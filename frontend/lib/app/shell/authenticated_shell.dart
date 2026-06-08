import 'package:flutter/material.dart';

/// Minimal authenticated route shell while UI is being rebuilt.
///
/// Previously wrapped child routes in a [NavigationRail]. Navigation contracts
/// and route definitions remain in [AppRoutes] and [appRouterProvider].
class AuthenticatedShell extends StatelessWidget {
  const AuthenticatedShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
