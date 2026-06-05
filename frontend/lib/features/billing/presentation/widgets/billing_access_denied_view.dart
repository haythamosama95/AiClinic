import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';

/// Standard 403 scaffold for billing routes (V1-6 foundation).
class BillingAccessDeniedView extends StatelessWidget {
  const BillingAccessDeniedView({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
