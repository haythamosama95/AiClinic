import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/no_branch_blocked_panel.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/shared/providers/connectivity_provider.dart';
import 'package:ai_clinic/shared/services/startup_health_service.dart';

/// Persistent shell footer: active branch | signed-in user | clinic connectivity (V1-2 US4).
class ShellStatusBar extends ConsumerWidget {
  const ShellStatusBar({super.key, required this.branchesAsync});

  final AsyncValue<List<BranchSummary>> branchesAsync;

  static const _sectionPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider.select((state) => state.context));
    final connectivity = ref.watch(connectivityStatusProvider);
    final theme = Theme.of(context);

    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _BranchSection(auth: auth, branchesAsync: branchesAsync),
              ),
              _verticalDivider(theme),
              Expanded(child: _UserSection(auth: auth)),
              _verticalDivider(theme),
              Expanded(child: _ConnectionSection(status: connectivity)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verticalDivider(ThemeData theme) {
    return VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor);
  }
}

class _BranchSection extends ConsumerWidget {
  const _BranchSection({required this.auth, required this.branchesAsync});

  final AuthSessionContext? auth;
  final AsyncValue<List<BranchSummary>> branchesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = auth;
    if (session == null) {
      return const _SectionLabel(icon: Icons.store_outlined, label: 'Branch…');
    }

    if (!session.hasBranchAssignment) {
      return _NoAssignmentBranch(staffName: session.staffProfile.fullName);
    }

    return branchesAsync.when(
      loading: () => const Padding(
        padding: ShellStatusBar._sectionPadding,
        child: Row(
          children: [
            Icon(Icons.store_outlined, size: 18),
            SizedBox(width: 8),
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
      error: (_, _) => const _SectionLabel(icon: Icons.store_outlined, label: 'Branch unavailable'),
      data: (branches) => _BranchControl(auth: session, branches: branches),
    );
  }
}

class _BranchControl extends ConsumerWidget {
  const _BranchControl({required this.auth, required this.branches});

  final AuthSessionContext auth;
  final List<BranchSummary> branches;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (branches.isEmpty) {
      return _NoAssignmentBranch(staffName: auth.staffProfile.fullName);
    }

    final activeBranchId = auth.activeBranchId;
    final resolvedId = activeBranchId != null && branches.any((b) => b.id == activeBranchId)
        ? activeBranchId
        : branches.first.id;

    if (branches.length == 1) {
      final branch = branches.first;
      return Padding(
        padding: ShellStatusBar._sectionPadding,
        child: Row(
          children: [
            const Icon(Icons.store_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(branch.name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: resolvedId,
          icon: const Icon(Icons.arrow_drop_down, size: 20),
          items: [
            for (final branch in branches)
              DropdownMenuItem(
                value: branch.id,
                child: Text(branch.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (branchId) {
            if (branchId == null) {
              return;
            }
            ref.read(authNotifierProvider.notifier).setActiveBranch(branchId);
          },
        ),
      ),
    );
  }
}

class _NoAssignmentBranch extends StatelessWidget {
  const _NoAssignmentBranch({required this.staffName});

  final String staffName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ShellStatusBar._sectionPadding,
      child: Tooltip(
        message: 'Contact your clinic administrator to request a branch assignment.',
        child: TextButton.icon(
          onPressed: () => _showBlockedGuidance(context),
          icon: Icon(Icons.location_off_outlined, size: 18, color: Theme.of(context).colorScheme.error),
          label: const Text('No branch'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  void _showBlockedGuidance(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No branch assigned'),
        content: NoBranchBlockedPanel(staffName: staffName),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close'))],
      ),
    );
  }
}

class _UserSection extends StatelessWidget {
  const _UserSection({required this.auth});

  final AuthSessionContext? auth;

  @override
  Widget build(BuildContext context) {
    final session = auth;
    if (session == null) {
      return const _SectionLabel(icon: Icons.person_outline, label: 'User…');
    }

    final profile = session.staffProfile;
    return Padding(
      padding: ShellStatusBar._sectionPadding,
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${profile.fullName} · ${profile.role.wireValue}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.status});

  final StartupConnectivityStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      StartupConnectivityStatus.healthy => (Icons.cloud_done_outlined, Colors.green.shade700),
      StartupConnectivityStatus.degraded => (Icons.cloud_queue_outlined, Colors.orange.shade800),
      StartupConnectivityStatus.unreachable => (Icons.cloud_off_outlined, Theme.of(context).colorScheme.error),
      StartupConnectivityStatus.unknown => (Icons.cloud_outlined, null),
    };

    return Padding(
      padding: ShellStatusBar._sectionPadding,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              connectivityStatusLabel(status),
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: ShellStatusBar._sectionPadding,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
