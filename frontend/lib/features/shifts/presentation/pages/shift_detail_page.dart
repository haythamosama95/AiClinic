import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_status_badge.dart';

/// Read-only shift detail baseline (V1-7 US2); mutation controls arrive in US3/US4.
class ShiftDetailPage extends ConsumerStatefulWidget {
  const ShiftDetailPage({required this.shiftId, super.key});

  final String? shiftId;

  @override
  ConsumerState<ShiftDetailPage> createState() => _ShiftDetailPageState();
}

class _ShiftDetailPageState extends ConsumerState<ShiftDetailPage> {
  ShiftDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void didUpdateWidget(covariant ShiftDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shiftId != widget.shiftId) {
      _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    final id = widget.shiftId?.trim() ?? '';
    if (id.isEmpty) {
      setState(() {
        _loading = false;
        _detail = null;
        _error = 'A valid shift id is required.';
      });
      return;
    }

    if (!ref.read(permissionServiceProvider).canViewShifts()) {
      setState(() {
        _loading = false;
        _detail = null;
        _error = 'permission_denied';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await ref.read(shiftRepositoryProvider).getShiftDetail(shiftId: id);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } on RpcFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = null;
        _loading = false;
        _error = failure.code;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = null;
        _loading = false;
        _error = 'load_failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(permissionServiceProvider).canManageShifts();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift Detail')),
        body: const Center(key: Key('shift_detail_loading'), child: CircularProgressIndicator()),
      );
    }

    if (_error == 'permission_denied') {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift Detail')),
        body: const Center(
          key: Key('shift_detail_permission_denied'),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You must be assigned to a branch to view shift details.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_error != null || _detail == null) {
      final message = switch (_error) {
        'shift_not_found' => 'This shift was not found or you do not have access.',
        'permission_denied' => 'You do not have permission to view this shift.',
        _ => 'Could not load shift details. Please retry.',
      };

      return Scaffold(
        appBar: AppBar(title: const Text('Shift Detail')),
        body: Center(
          key: const Key('shift_detail_error'),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _loadDetail, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final detail = _detail!;
    final isReadOnly = detail.isReadOnly || !canManage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift Detail'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isReadOnly) _ReadOnlyBanner(detail: detail, canManage: canManage),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          MaterialLocalizations.of(context).formatFullDate(detail.shiftDate),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      ShiftStatusBadge(status: detail.status, isUnassigned: detail.isUnassigned),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${detail.startTime} – ${detail.endTime}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(detail.branch.name, style: Theme.of(context).textTheme.bodyMedium),
                  if (detail.notes != null && detail.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Notes', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(detail.notes!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Assigned staff', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (detail.isUnassigned)
            const ListTile(
              key: Key('shift_detail_unassigned'),
              leading: Icon(Icons.person_off_outlined),
              title: Text('Unassigned'),
              subtitle: Text('No staff are scheduled for this shift yet.'),
            )
          else
            ...detail.assignments.map(
              (assignment) => ListTile(
                key: Key('shift_detail_assignee_${assignment.staffMemberId}'),
                leading: const Icon(Icons.person_outline),
                title: Text(assignment.displayName),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.detail, required this.canManage});

  final ShiftDetail detail;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final message = switch ((detail.status, detail.isPast, canManage)) {
      (ShiftStatus.cancelled, _, _) => 'This shift was cancelled and can no longer be changed.',
      (_, true, _) => 'Past shifts are read-only and cannot be edited.',
      (_, _, false) => 'You can view this shift but do not have permission to edit it.',
      _ => 'This shift is read-only.',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MaterialBanner(
        key: const Key('shift_detail_read_only_banner'),
        content: Text(message),
        leading: const Icon(Icons.lock_outline),
        actions: const [SizedBox.shrink()],
      ),
    );
  }
}
