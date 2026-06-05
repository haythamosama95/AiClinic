import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/billing/presentation/widgets/billing_access_denied_view.dart';

/// Placeholder insurance provider catalog page (V1-6 foundation).
class InsuranceProvidersPage extends ConsumerWidget {
  const InsuranceProvidersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);
    final canManage = permissions.canManageInsurance();

    if (!canManage) {
      return const BillingAccessDeniedView(
        title: 'Insurance providers',
        message: 'You do not have permission to manage insurance providers.',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insurance providers'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.nav.goHome(),
        ),
      ),
      body: const Center(child: Text('Insurance provider catalog will appear here.')),
    );
  }
}
