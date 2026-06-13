import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_query.dart';
import 'package:ai_clinic/features/settings/presentation/providers/staff_list_notifier.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/create_staff_modal.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/animated_filter_cards_grid.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_list_toolbar.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_detail_sheet.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_member_card.dart';

/// Staff list with card layout and lifecycle actions.
class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({this.embedded = false, super.key});

  /// When true, omits the page scaffold (for use inside the settings tab).
  final bool embedded;

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  final _searchController = TextEditingController();
  var _query = const StaffListQuery();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    final canAccess = AuthRouteGuard.canAccessStaffManagement(auth);

    final body = _StaffListBody(
      canAccess: canAccess,
      listAsync: listAsync,
      embedded: widget.embedded,
      query: _query,
      searchController: _searchController,
      onSearchChanged: (value) => setState(() => _query = _query.copyWith(searchText: value)),
      onQueryChanged: (query) => setState(() => _query = query),
      onNewStaff: () => _openCreateStaffModal(context),
      onViewStaff: _openStaffDetailSheet,
    );

    if (widget.embedded) {
      return Material(color: Colors.transparent, child: body);
    }

    if (!canAccess) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Staff'),
          leading: IconButton(
            tooltip: 'Go back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ),
        body: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settings),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateStaffModal(context),
        icon: const Icon(Icons.person_add),
        label: const Text('New staff'),
      ),
      body: body,
    );
  }

  Future<void> _openCreateStaffModal(BuildContext context) async {
    await CreateStaffModal.show(context);
  }

  Future<void> _openStaffDetailSheet(StaffListItem member) async {
    await StaffDetailSheet.show(context, member);
  }
}

class _StaffListBody extends ConsumerWidget {
  const _StaffListBody({
    required this.canAccess,
    required this.listAsync,
    required this.embedded,
    required this.query,
    required this.searchController,
    required this.onSearchChanged,
    required this.onQueryChanged,
    required this.onNewStaff,
    required this.onViewStaff,
  });

  final bool canAccess;
  final AsyncValue<StaffListUiState> listAsync;
  final bool embedded;
  final StaffListQuery query;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<StaffListQuery> onQueryChanged;
  final VoidCallback onNewStaff;
  final Future<void> Function(StaffListItem member) onViewStaff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canAccess) {
      return const _CenteredMessage('You do not have permission to manage staff.');
    }

    return listAsync.when(
      loading: () => const Center(child: AppCircularProgress()),
      error: (error, _) => _CenteredMessage('Failed to load staff: $error'),
      data: (ui) {
        if (ui.staff.isEmpty) {
          return const _CenteredMessage('No staff yet. Create an account to get started.');
        }

        return ListView(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: [
            StaffListToolbar(
              searchController: searchController,
              query: query,
              onSearchChanged: onSearchChanged,
              onQueryChanged: onQueryChanged,
              onNewStaff: embedded && canAccess ? onNewStaff : null,
            ),
            const SizedBox(height: SpacingTokens.lg),
            AnimatedFilterCardsGrid<StaffListItem>(
              items: [...ui.staff]..sort(StaffListItem.compareByFullName),
              isVisible: query.matches,
              itemKey: (member) => member.id,
              columns: 3,
              enforceColumns: true,
              emptyPlaceholder: const _CenteredMessage('No staff match your search or filters.'),
              itemBuilder: (member) => StaffMemberCard(member: member, onOpen: () => onViewStaff(member)),
            ),
          ],
        );
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
