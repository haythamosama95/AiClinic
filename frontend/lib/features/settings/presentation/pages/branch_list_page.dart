import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_filter.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/branch_list_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/last_active_branch_blocked_dialog.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';

/// Branch list with active/inactive filters and lifecycle actions (US2).
class BranchListPage extends ConsumerStatefulWidget {
  const BranchListPage({super.key});

  @override
  ConsumerState<BranchListPage> createState() => _BranchListPageState();
}

class _BranchListPageState extends ConsumerState<BranchListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final current = ref.read(branchListProvider);
      if (current.isLoading) {
        return;
      }
      ref.read(branchListProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    final listAsync = ref.watch(branchListProvider);

    ref.listen<AsyncValue<BranchListUiState>>(branchListProvider, (previous, next) {
      final blockId = next.value?.lastActiveBranchBlockId;
      if (blockId != null && blockId != previous?.value?.lastActiveBranchBlockId) {
        ref.read(branchListProvider.notifier).clearLastActiveBranchBlock();
        showLastActiveBranchBlockedDialog(context, branchId: blockId);
      }

      final actionError = next.value?.actionError;
      if (actionError != null && actionError != previous?.value?.actionError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(actionError)));
        ref.read(branchListProvider.notifier).clearActionError();
      }
    });

    if (!AuthRouteGuard.canAccessBranchManagement(auth)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Branches'),
          leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to manage branches.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches'),
        leading: IconButton(tooltip: 'Go back', icon: const Icon(Icons.arrow_back), onPressed: () => context.go(AppRoutes.settings)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.settingsBranchesNew),
        icon: const Icon(Icons.add),
        label: const Text('New branch'),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load branches: $error')),
        data: (ui) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SegmentedButton<BranchListFilter>(
                segments: const [
                  ButtonSegment(value: BranchListFilter.active, label: Text('Active')),
                  ButtonSegment(value: BranchListFilter.inactive, label: Text('Inactive')),
                  ButtonSegment(value: BranchListFilter.all, label: Text('All')),
                ],
                selected: {ui.filter},
                onSelectionChanged: ui.isTogglingActive
                    ? null
                    : (selection) {
                        ref.read(branchListProvider.notifier).setFilter(selection.first);
                      },
              ),
            ),
            Expanded(
              child: ui.branches.isEmpty
                  ? Center(
                      child: Text(
                        ui.filter == BranchListFilter.active
                            ? 'No active branches.'
                            : ui.filter == BranchListFilter.inactive
                            ? 'No inactive branches.'
                            : 'No branches yet. Create one to get started.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: ui.branches.length,
                      itemBuilder: (context, index) {
                        final branch = ui.branches[index];
                        return _BranchListTile(
                          branch: branch,
                          isBusy: ui.isTogglingActive && ui.togglingBranchId == branch.id,
                          onEdit: () => context.go(AppRoutes.settingsBranchEdit(branch.id)),
                          onToggleActive: () => ref.read(branchListProvider.notifier).toggleBranchActive(branch),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchListTile extends StatelessWidget {
  const _BranchListTile({
    required this.branch,
    required this.isBusy,
    required this.onEdit,
    required this.onToggleActive,
  });

  final BranchListItem branch;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (branch.code != null) 'Code: ${branch.code}',
      branch.isActive ? 'Active' : 'Inactive',
      if (branch.address != null) branch.address!,
    ];

    return ListTile(
      title: Text(branch.name),
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
                PopupMenuItem(value: 'toggle', child: Text(branch.isActive ? 'Deactivate' : 'Reactivate')),
              ],
            ),
      onTap: onEdit,
    );
  }
}
