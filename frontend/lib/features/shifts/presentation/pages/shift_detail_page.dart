import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_detail_notifier.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/cancel_shift_dialog.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_conflict_banner.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_form_fields.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_staff_multi_select.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_status_badge.dart';

/// Shift detail with read-only baseline (US2), assignments (US3), edit/cancel (US4).
class ShiftDetailPage extends ConsumerWidget {
  const ShiftDetailPage({required this.shiftId, super.key});

  final String? shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = shiftId?.trim() ?? '';
    if (id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shift Detail')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('A valid shift id is required.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final detailAsync = ref.watch(shiftDetailProvider(id));
    final canManage = ref.watch(permissionServiceProvider).canManageShifts();

    return detailAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Shift Detail')),
        body: const Center(key: Key('shift_detail_loading'), child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Shift Detail')),
        body: _ShiftDetailErrorBody(error: error, onRetry: () => ref.invalidate(shiftDetailProvider(id))),
      ),
      data: (state) => _ShiftDetailBody(state: state, canManage: canManage),
    );
  }
}

class _ShiftDetailErrorBody extends StatelessWidget {
  const _ShiftDetailErrorBody({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is RpcFailure && (error as RpcFailure).code == 'permission_denied') {
      return const Center(
        key: Key('shift_detail_permission_denied'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('You must be assigned to a branch to view shift details.', textAlign: TextAlign.center),
        ),
      );
    }

    final message = switch (error) {
      RpcFailure(:final code) when code == 'shift_not_found' => 'This shift was not found or you do not have access.',
      RpcFailure(:final code) when code == 'permission_denied' => 'You do not have permission to view this shift.',
      _ => UserErrorMapper.mapToUserMessage(error),
    };

    return Center(
      key: const Key('shift_detail_error'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ShiftDetailBody extends ConsumerStatefulWidget {
  const _ShiftDetailBody({required this.state, required this.canManage});

  final ShiftDetailState state;
  final bool canManage;

  @override
  ConsumerState<_ShiftDetailBody> createState() => _ShiftDetailBodyState();
}

class _ShiftDetailBodyState extends ConsumerState<_ShiftDetailBody> {
  final _editFormKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  bool _isEditMode = false;
  DateTime? _editShiftDate;
  TimeOfDay? _editStartTime;
  TimeOfDay? _editEndTime;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  ShiftDetailState get state => widget.state;
  ShiftDetail get detail => state.detail;
  bool get canManage => widget.canManage;

  bool get isReadOnly => detail.isReadOnly || !canManage;
  bool get canEdit => canManage && state.canEditShift && detail.status != ShiftStatus.cancelled;

  @override
  void didUpdateWidget(covariant _ShiftDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.detail.id != state.detail.id || (!_isEditMode && oldWidget.state.detail != state.detail)) {
      _resetEditFields();
    }
  }

  void _resetEditFields() {
    _editShiftDate = detail.shiftDate;
    _editStartTime = _parseTime(detail.startTime);
    _editEndTime = _parseTime(detail.endTime);
    _notesController.text = detail.notes ?? '';
  }

  TimeOfDay? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _isEditFormReady() {
    if (_editShiftDate == null || _editStartTime == null || _editEndTime == null) {
      return false;
    }
    final startMinutes = _editStartTime!.hour * 60 + _editStartTime!.minute;
    final endMinutes = _editEndTime!.hour * 60 + _editEndTime!.minute;
    return endMinutes > startMinutes;
  }

  void _enterEditMode() {
    _resetEditFields();
    setState(() => _isEditMode = true);
  }

  void _exitEditMode() {
    setState(() => _isEditMode = false);
  }

  Future<void> _saveEdit() async {
    if (!(_editFormKey.currentState?.validate() ?? false) || !_isEditFormReady()) {
      return;
    }

    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    if (_editShiftDate!.isBefore(today)) {
      return;
    }

    final success = await ref
        .read(shiftDetailProvider(detail.id).notifier)
        .updateShift(
          shiftDate: _editShiftDate!,
          startTime: _formatTime(_editStartTime!),
          endTime: _formatTime(_editEndTime!),
          notes: _notesController.text.trim(),
        );

    if (!mounted) {
      return;
    }

    if (success) {
      setState(() => _isEditMode = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift updated successfully.')));
    }
  }

  Future<void> _confirmCancelShift() async {
    final confirmed = await showCancelShiftDialog(
      context: context,
      shiftDate: detail.shiftDate,
      startTime: detail.startTime,
      endTime: detail.endTime,
    );

    if (!confirmed || !mounted) {
      return;
    }

    final success = await ref.read(shiftDetailProvider(detail.id).notifier).cancelShift();
    if (!mounted) {
      return;
    }

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift cancelled.')));
      context.go(AppRoutes.shiftsCalendar);
    }
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = this.isReadOnly;
    final canEditAssignments = canManage && state.canMutateAssignments && !_isEditMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Shift' : 'Shift Detail'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: [
          if (canEdit && !_isEditMode)
            IconButton(
              key: const Key('shift_detail_edit_button'),
              tooltip: 'Edit shift',
              icon: const Icon(Icons.edit_outlined),
              onPressed: state.isSaving ? null : _enterEditMode,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isReadOnly) _ReadOnlyBanner(detail: detail, canManage: canManage),
          if (state.mutationStatus == ShiftDetailMutationStatus.stale)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: MaterialBanner(
                key: const Key('shift_detail_stale_banner'),
                content: Text(state.mutationError ?? 'This shift was updated elsewhere. Reload and try again.'),
                leading: const Icon(Icons.refresh),
                actions: [
                  TextButton(
                    onPressed: () => ref.read(shiftDetailProvider(detail.id).notifier).reload(),
                    child: const Text('Reload'),
                  ),
                ],
              ),
            ),
          if (state.overlapConflicts.isNotEmpty) ...[
            ShiftConflictBanner(conflicts: state.overlapConflicts),
            const SizedBox(height: 16),
          ],
          if (state.mutationError != null &&
              state.mutationStatus == ShiftDetailMutationStatus.error &&
              state.overlapConflicts.isEmpty) ...[
            Text(state.mutationError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
          ],
          if (_isEditMode)
            Form(
              key: _editFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ShiftFormFields(
                    shiftDate: _editShiftDate,
                    startTime: _editStartTime,
                    endTime: _editEndTime,
                    notesController: _notesController,
                    enabled: !state.isSaving,
                    onShiftDateChanged: (value) => setState(() => _editShiftDate = value),
                    onStartTimeChanged: (value) => setState(() => _editStartTime = value),
                    onEndTimeChanged: (value) => setState(() => _editEndTime = value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('shift_detail_edit_cancel'),
                          onPressed: state.isSaving ? null : _exitEditMode,
                          child: const Text('Discard changes'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('shift_detail_edit_save'),
                          onPressed: state.isSaving || !_isEditFormReady() ? null : _saveEdit,
                          child: state.isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
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
          if (!_isEditMode) ...[
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
                  trailing: canEditAssignments
                      ? IconButton(
                          key: Key('shift_detail_remove_assignee_${assignment.staffMemberId}'),
                          icon: const Icon(Icons.person_remove_outlined),
                          tooltip: 'Remove assignment',
                          onPressed: state.isSaving
                              ? null
                              : () =>
                                    _confirmRemoveAssignment(context, assignment.staffMemberId, assignment.displayName),
                        )
                      : null,
                ),
              ),
            if (canEditAssignments) ...[const SizedBox(height: 16), _AssignmentPanel(state: state)],
            if (canEdit) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('shift_detail_cancel_shift_button'),
                onPressed: state.isSaving ? null : _confirmCancelShift,
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Cancel shift'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemoveAssignment(BuildContext context, String staffMemberId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove assignment?'),
        content: Text('Remove $displayName from this shift?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('shift_detail_confirm_remove'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await ref.read(shiftDetailProvider(state.detail.id).notifier).removeAssignment(staffMemberId: staffMemberId);
  }
}

class _AssignmentPanel extends ConsumerWidget {
  const _AssignmentPanel({required this.state});

  final ShiftDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedIds = {for (final assignment in state.detail.assignments) assignment.staffMemberId};
    final notifier = ref.read(shiftDetailProvider(state.detail.id).notifier);

    return Card(
      key: const Key('shift_detail_assignment_panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add staff', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ShiftStaffMultiSelect(
              selectedStaffIds: state.pendingAddStaffIds,
              excludeStaffIds: assignedIds,
              enabled: !state.isSaving,
              onChanged: notifier.setPendingAddStaffIds,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('shift_detail_add_staff_submit'),
                onPressed: state.isSaving || state.pendingAddStaffIds.isEmpty ? null : () => notifier.addPendingStaff(),
                child: state.isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add selected staff'),
              ),
            ),
          ],
        ),
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
