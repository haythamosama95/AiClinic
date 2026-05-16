import 'package:flutter/material.dart';

/// Shared page frame for the pre-auth startup shell screens.
class StartupScaffold extends StatelessWidget {
  const StartupScaffold({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 24),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
