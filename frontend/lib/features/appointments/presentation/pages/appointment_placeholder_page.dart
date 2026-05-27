import 'package:flutter/material.dart';

/// Placeholder until user-story phases implement appointment screens (V1-4 Phase 2).
class AppointmentPlaceholderPage extends StatelessWidget {
  const AppointmentPlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$title will be available in the next implementation phase.', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
