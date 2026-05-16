import 'package:flutter/material.dart';

/// Placeholder protected page that should only be reachable after future auth work.
class ProtectedPlaceholderPage extends StatelessWidget {
  const ProtectedPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('This route should never render before authentication.')));
  }
}
