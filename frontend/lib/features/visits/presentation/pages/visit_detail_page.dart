import 'package:flutter/material.dart';

/// Placeholder read-only visit detail (V1-5 US6 will flesh out).
class VisitDetailPage extends StatelessWidget {
  const VisitDetailPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visit detail')),
      body: Center(
        child: Text(visitId == null || visitId!.isEmpty ? 'Visit not found.' : 'Visit $visitId detail (coming soon).'),
      ),
    );
  }
}
