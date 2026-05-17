import 'package:flutter/material.dart';

/// Placeholder login route for Phase 2 router scaffolding (full UI in US1).
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Staff sign-in will be implemented in the login user story. '
            'Use this route to verify auth-aware navigation from startup.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
