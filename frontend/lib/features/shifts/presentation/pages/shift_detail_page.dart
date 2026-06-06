import 'package:flutter/material.dart';

/// Shift detail shell (implemented in US2/US3/US4).
class ShiftDetailPage extends StatelessWidget {
  const ShiftDetailPage({required this.shiftId, super.key});

  final String? shiftId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shift Detail')),
      body: Center(child: Text('Shift detail for ${shiftId ?? 'unknown'} will be implemented in the next phase.')),
    );
  }
}
