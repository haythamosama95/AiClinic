import 'package:flutter/material.dart';

/// Placeholder forgot-password route (implemented in US7).
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Password recovery is administrator-mediated. Contact your clinic administrator.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
