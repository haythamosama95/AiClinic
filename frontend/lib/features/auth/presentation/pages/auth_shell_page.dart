import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/core/auth/permission_denied_handler.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_tools.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/dev_tools.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/dev_seed_appointments_button.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/dev_seed_doctors_button.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/no_branch_blocked_panel.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/permission_demo_panel.dart';
import 'package:ai_clinic/app/widgets/shell_status_bar.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:go_router/go_router.dart';

/// Authenticated placeholder shell: identity header, branch selector, RBAC demo (US3).
class AuthShellPage extends ConsumerWidget {
  const AuthShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final auth = session.context;
    final branchesAsync = ref.watch(staffAssignableBranchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AiClinic'),
        actions: [
          TextButton(onPressed: () => ref.read(authNotifierProvider.notifier).signOut(), child: const Text('Sign out')),
        ],
      ),
      body: auth == null
          ? const Center(child: Text('Loading session context…'))
          : !auth.hasBranchAssignment
          ? NoBranchBlockedPanel(staffName: auth.staffProfile.fullName)
          : _ShellHomeBody(auth: auth, branchesAsync: branchesAsync),
      bottomNavigationBar: auth != null ? ShellStatusBar(branchesAsync: branchesAsync) : null,
    );
  }
}

class _ShellHomeBody extends ConsumerWidget {
  const _ShellHomeBody({required this.auth, required this.branchesAsync});

  final AuthSessionContext auth;
  final AsyncValue<List<BranchSummary>> branchesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(permissionServiceProvider);

    final activeBranchLabel = branchesAsync.maybeWhen(
      data: (branches) {
        final activeId = auth.activeBranchId;
        if (activeId == null) {
          return null;
        }
        for (final branch in branches) {
          if (branch.id == activeId) {
            return branch.name;
          }
        }
        return activeId;
      },
      orElse: () => auth.activeBranchId,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome, ${auth.staffProfile.fullName}',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Role: ${auth.staffProfile.role.wireValue}'
                '${activeBranchLabel != null ? ' · Active branch: $activeBranchLabel' : ''}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              if (!auth.setupRequired && permissions.canViewPatients()) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.patients),
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Patients'),
                ),
              ],
              if (!auth.setupRequired && permissions.canCreatePatients()) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.patientsNew),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Register patient'),
                ),
              ],
              if (!auth.setupRequired && permissions.canAccessAppointments()) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('shell_home_appointments'),
                  onPressed: () => context.go(AppRoutes.appointments),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Appointments'),
                ),
              ],
              if (!auth.setupRequired && permissions.canCreateAppointments()) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('shell_home_book_appointment'),
                  onPressed: () => context.push(AppRoutes.appointmentsBook),
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Book appointment'),
                ),
              ],
              if (!auth.setupRequired) ...[const SizedBox(height: 20), const _LandingDevToolsPanel()],
              const SizedBox(height: 24),
              if (kDebugMode) const PermissionDemoPanel(),
              if (!auth.setupRequired) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: () => context.go(AppRoutes.settings), child: const Text('Settings')),
              ],
              if (!auth.setupRequired) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    PermissionDeniedHandler.runIfPermitted(
                      context,
                      permissions: permissions,
                      permissionKey: PermissionKeys.manageStaff,
                      action: () => context.go(AppRoutes.settingsStaff),
                    );
                  },
                  child: const Text('Manage staff'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LandingDevToolsPanel extends StatelessWidget {
  const _LandingDevToolsPanel();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Developer tools'),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DevSeedDoctorsButton(),
                DevSeedPatientsButton(),
                DevSeedAppointmentsButton(),
                DevFillDummyClinicButton(),
                DevResetClinicButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
