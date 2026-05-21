import 'package:flutter/material.dart';

/// Placeholder until US6 implements full staff provisioning UI.
class StaffProvisioningPlaceholderPage extends StatelessWidget {
  const StaffProvisioningPlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Staff provisioning screens are implemented in the staff-accounts user story.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
