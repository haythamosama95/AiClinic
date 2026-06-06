import 'package:flutter/material.dart';

/// Shift creation shell (implemented in US1).
class ShiftCreatePage extends StatelessWidget {
  const ShiftCreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Shift')),
      body: const Center(child: Text('Shift creation will be implemented in the next phase.')),
    );
  }
}
