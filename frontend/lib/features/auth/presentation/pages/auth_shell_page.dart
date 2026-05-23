import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/core/auth/permission_denied_handler.dart';
import 'package:ai_clinic/core/auth/permission_service.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/providers/staff_assignable_branches_provider.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_fill_dummy_clinic_button.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/dev_reset_clinic_button.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/dev_seed_patients_button.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/no_branch_blocked_panel.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/permission_demo_panel.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/shell_status_bar.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
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
          const DevFillDummyClinicButton(),
          const DevResetClinicButton(),
          const DevSeedPatientsButton(),
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

class _ShellHomeBody extends StatelessWidget {
  const _ShellHomeBody({required this.auth, required this.branchesAsync});

  final AuthSessionContext auth;
  final AsyncValue<List<BranchSummary>> branchesAsync;

  @override
  Widget build(BuildContext context) {
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
              if (!auth.setupRequired) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    PermissionDeniedHandler.runIfPermitted(
                      context,
                      permissions: PermissionService(auth),
                      permissionKey: PermissionKeys.patientsView,
                      action: () => context.go(AppRoutes.patients),
                    );
                  },
                  icon: const Icon(Icons.people_outline),
                  label: const Text('Patients'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    PermissionDeniedHandler.runIfPermitted(
                      context,
                      permissions: PermissionService(auth),
                      permissionKey: PermissionKeys.patientsCreate,
                      action: () => context.go(AppRoutes.patientsNew),
                    );
                  },
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Register patient'),
                ),
              ],
              const SizedBox(height: 24),
              const PermissionDemoPanel(),
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
                      permissions: PermissionService(auth),
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
