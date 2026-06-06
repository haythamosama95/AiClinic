import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Branch shift calendar shell (implemented in US2).
class ShiftCalendarPage extends ConsumerWidget {
  const ShiftCalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(permissionServiceProvider).canManageShifts();

    return Scaffold(
      appBar: AppBar(title: const Text('Shift Calendar')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('shift_calendar_create_fab'),
              onPressed: () => context.push(AppRoutes.shiftsNew),
              icon: const Icon(Icons.add),
              label: const Text('Create shift'),
            )
          : null,
      body: const Center(child: Text('Shift calendar loading will be implemented in the next phase.')),
    );
  }
}
