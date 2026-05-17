import 'package:flutter/material.dart';

/// Placeholder bootstrap wizard route (implemented in US5).
class ClinicBootstrapPage extends StatelessWidget {
  const ClinicBootstrapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clinic setup')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Organization and first-branch setup will be implemented in the bootstrap user story.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
