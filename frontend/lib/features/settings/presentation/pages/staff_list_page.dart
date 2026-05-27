import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Staff list with active/inactive filters and lifecycle actions (US3).
class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({super.key});

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final current = ref.read(staffListProvider);
      if (current.isLoading) {
        return;
      }
      ref.read(staffListProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final listAsync = ref.watch(staffListProvider);

    ref.listen<AsyncValue<StaffListUiState>>(staffListProvider, (previous, next) {
      final actionError = next.value?.actionError;
      if (actionError != null && actionError != previous?.value?.actionError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(actionError)));
        ref.read(staffListProvider.notifier).clearActionError();
      }
    });

    if (!AuthRouteGuard.canAccessStaffManagement(auth)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Staff'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to manage staff.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.settingsStaffNew),
        icon: const Icon(Icons.person_add),
        label: const Text('New staff'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load staff: $error')),
        data: (ui) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SegmentedButton<StaffListFilter>(
                segments: const [
                  ButtonSegment(value: StaffListFilter.active, label: Text('Active')),
                  ButtonSegment(value: StaffListFilter.inactive, label: Text('Inactive')),
                  ButtonSegment(value: StaffListFilter.all, label: Text('All')),
                ],
                selected: {ui.filter},
                onSelectionChanged: ui.isTogglingActive
                    ? null
                    : (selection) {
                        ref.read(staffListProvider.notifier).setFilter(selection.first);
                      },
              ),
            ),
            Expanded(
              child: ui.staff.isEmpty
                  ? Center(
                      child: Text(
                        ui.filter == StaffListFilter.active
                            ? 'No active staff members.'
                            : ui.filter == StaffListFilter.inactive
                            ? 'No inactive staff members.'
                            : 'No staff yet. Create an account to get started.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: ui.staff.length,
                      itemBuilder: (context, index) {
                        final member = ui.staff[index];
                        return _StaffListTile(
                          member: member,
                          isBusy: ui.isTogglingActive && ui.togglingStaffId == member.id,
                          onEdit: () => context.go(AppRoutes.settingsStaffDetail(member.id)),
                          onToggleActive: () => _confirmToggleActive(context, member),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmToggleActive(BuildContext context, StaffListItem member) async {
    final targetActive = !member.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(targetActive ? 'Reactivate staff member?' : 'Deactivate staff member?'),
        content: Text(
          targetActive
              ? '${member.fullName} will be able to sign in again when assigned to active branches.'
              : '${member.fullName} will not be able to sign in until reactivated.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(targetActive ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(staffListProvider.notifier).toggleStaffActive(member);
    }
  }
}

class _StaffListTile extends StatelessWidget {
  const _StaffListTile({
    required this.member,
    required this.isBusy,
    required this.onEdit,
    required this.onToggleActive,
  });

  final StaffListItem member;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      _roleLabel(member.role),
      member.isActive ? 'Active' : 'Inactive',
      member.branchNamesLabel,
      if (member.phone != null) member.phone!,
    ];

    return ListTile(
      title: Text(member.fullName),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: isBusy
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                  case 'toggle':
                    onToggleActive();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'toggle', child: Text(member.isActive ? 'Deactivate' : 'Reactivate')),
              ],
            ),
      onTap: onEdit,
    );
  }

  static String _roleLabel(StaffRole role) => switch (role) {
    StaffRole.owner => 'Owner',
    StaffRole.administrator => 'Administrator',
    StaffRole.doctor => 'Doctor',
    StaffRole.receptionist => 'Receptionist',
    StaffRole.labStaff => 'Lab staff',
  };
}
