import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/permission_denied_handler.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Placeholder until US2 list page is implemented (Phase 4).
class PatientListPage extends ConsumerWidget {
  const PatientListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = PermissionService(ref.watch(authSessionProvider).context);
    final canView = permissions.canViewPatients();

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Patients'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.home)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.home)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          PermissionDeniedHandler.runIfPermitted(
            context,
            permissions: permissions,
            permissionKey: PermissionKeys.patientsCreate,
            action: () => context.go(AppRoutes.patientsNew),
          );
        },
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Register patient'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Patient search and list — coming in Phase 4.', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Placeholder until US3 detail page is implemented (Phase 5).
class PatientDetailPage extends ConsumerWidget {
  const PatientDetailPage({required this.patientId, super.key});

  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = PermissionService(ref.watch(authSessionProvider).context).canViewPatients();

    if (!canView) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Patient'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.patients)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to view patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(body: Center(child: Text('Patient detail ($patientId) — coming in Phase 5')));
  }
}

/// Placeholder until US4 edit page is implemented (Phase 6).
class PatientEditPage extends ConsumerWidget {
  const PatientEditPage({required this.patientId, super.key});

  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = PermissionService(ref.watch(authSessionProvider).context);

    if (!permissions.canEditPatients()) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit patient'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.patients)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to edit patients.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(body: Center(child: Text('Patient edit ($patientId) — coming in Phase 6')));
  }
}
