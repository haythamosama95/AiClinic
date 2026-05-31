import 'package:flutter/material.dart';

/// Placeholder visit documentation shell (V1-5 US1+ will flesh out).
class VisitDocumentationPage extends StatelessWidget {
  const VisitDocumentationPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visit documentation')),
      body: Center(
        child: Text(
          visitId == null || visitId!.isEmpty ? 'Visit not found.' : 'Documentation for visit $visitId (coming soon).',
        ),
      ),
    );
  }
}
