import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/shifts/application/shift_rpc_messages.dart';
import 'package:ai_clinic/features/shifts/domain/shift_assignment.dart';
import 'package:ai_clinic/features/shifts/domain/shift_detail.dart';
import 'package:ai_clinic/features/shifts/domain/shift_status.dart';
import 'package:ai_clinic/features/shifts/presentation/providers/shift_detail_notifier.dart';
import 'package:ai_clinic/features/shifts/presentation/utils/shift_presentation_formatting.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/cancel_shift_dialog.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_conflict_banner.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_form_fields.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_staff_multi_select.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_status_badge.dart';

/// Shift detail with read-only baseline, assignments, edit, and cancel (`/shifts/:shiftId`).
class ShiftDetailPage extends ConsumerWidget {
  const ShiftDetailPage({required this.shiftId, super.key});

  final String shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessShiftDetail(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Shift detail',
        description: 'You must be assigned to a branch to view shift details.',
      );
    }

    final id = shiftId.trim();
    if (id.isEmpty) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.error,
        title: 'Shift not found',
        description: 'A valid shift id is required.',
      );
    }

    final detailAsync = ref.watch(shiftDetailProvider(id));
    final canManage = ref.watch(permissionServiceProvider).canManageShifts();

    return detailAsync.when(
      loading: () => const RecordDetailPattern(
        title: 'Shift detail',
        body: Center(key: Key('shift_detail_loading'), child: AppSpinner()),
      ),
      error: (error, _) => RecordDetailPattern(
        title: 'Shift detail',
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
      return const AppEmptyState(
        key: Key('shift_detail_permission_denied'),
        variant: AppEmptyStateVariant.noAccess,
        title: 'Shift detail',
        description: 'You must be assigned to a branch to view shift details.',
      );
    }

    final message = switch (error) {
      RpcFailure(:final code) when code == 'shift_not_found' => 'This shift was not found or you do not have access.',
      RpcFailure(:final code) when code == 'permission_denied' => 'You do not have permission to view this shift.',
      RpcFailure failure => shiftMessageForRpc(failure),
      _ => UserErrorMapper.mapToUserMessage(error),
    };

    return AppErrorState(
      key: const Key('shift_detail_error'),
      message: message,
      onRetry: onRetry,
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
  final _notesController = TextEditingController();

  bool _isEditMode = false;
  DateTime? _editShiftDate;
  String? _editStartTime;
  String? _editEndTime;

  ShiftDetailState get state => widget.state;
  ShiftDetail get detail => state.detail;
  bool get canManage => widget.canManage;

  bool get isReadOnly => detail.isReadOnly || !canManage;
  bool get canEdit => canManage && state.canEditShift && detail.status != ShiftStatus.cancelled;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ShiftDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.detail.id != state.detail.id || (!_isEditMode && oldWidget.state.detail != state.detail)) {
      _resetEditFields();
    }
  }

  void _resetEditFields() {
    _editShiftDate = detail.shiftDate;
    _editStartTime = detail.startTime;
    _editEndTime = detail.endTime;
    _notesController.text = detail.notes ?? '';
  }

  bool _isEditFormReady() {
    if (_editShiftDate == null || _editStartTime == null || _editEndTime == null) {
      return false;
    }
    return ShiftPresentationFormatting.isEndAfterStart(_editStartTime, _editEndTime);
  }

  void _enterEditMode() {
    _resetEditFields();
    setState(() => _isEditMode = true);
  }

  void _exitEditMode() {
    setState(() => _isEditMode = false);
  }

  Future<void> _saveEdit() async {
    if (!_isEditFormReady()) {
      return;
    }

    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    if (_editShiftDate!.isBefore(today)) {
      return;
    }

    final success = await ref.read(shiftDetailProvider(detail.id).notifier).updateShift(
          shiftDate: _editShiftDate!,
          startTime: _editStartTime!,
          endTime: _editEndTime!,
          notes: _notesController.text.trim(),
        );

    if (!mounted) {
      return;
    }

    if (success) {
      setState(() => _isEditMode = false);
      ref.showAppToast(message: 'Shift updated successfully.', variant: AppToastVariant.success);
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
      ref.showAppToast(message: 'Shift cancelled.', variant: AppToastVariant.success);
      context.go(AppRoutes.shiftsCalendar);
    }
  }

  Future<void> _confirmRemoveAssignment(String staffMemberId, String displayName) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Remove assignment?',
      message: 'Remove $displayName from this shift?',
      confirmLabel: 'Remove',
      destructive: true,
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    await ref.read(shiftDetailProvider(detail.id).notifier).removeAssignment(staffMemberId: staffMemberId);
  }

  @override
  Widget build(BuildContext context) {
    final canEditAssignments = canManage && state.canMutateAssignments && !_isEditMode;
    final title = _isEditMode ? 'Edit shift' : 'Shift detail';
    final description = _isEditMode
        ? null
        : '${ShiftPresentationFormatting.formatDate(detail.shiftDate)} · '
            '${ShiftPresentationFormatting.formatTimeRange(detail.startTime, detail.endTime)}';

    return RecordDetailPattern(
      title: title,
      description: description,
      statusBadge: _isEditMode
          ? null
          : ShiftStatusBadge(status: detail.status, isUnassigned: detail.isUnassigned),
      actions: canEdit && !_isEditMode
          ? AppButton(
              key: const Key('shift_detail_edit_button'),
              label: 'Edit shift',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.pencil,
              onPressed: state.isSaving ? null : _enterEditMode,
            )
          : null,
      body: AppScrollArea(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isReadOnly) _ReadOnlyBanner(detail: detail, canManage: canManage),
              if (state.mutationStatus == ShiftDetailMutationStatus.stale)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s4),
                  child: AppAlert(
                    key: const Key('shift_detail_stale_banner'),
                    variant: AppAlertVariant.warning,
                    title: state.mutationError ?? 'This shift was updated elsewhere. Reload and try again.',
                    actions: [
                      AppButton(
                        label: 'Reload',
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.sm,
                        onPressed: () => ref.read(shiftDetailProvider(detail.id).notifier).reload(),
                      ),
                    ],
                  ),
                ),
              if (state.overlapConflicts.isNotEmpty) ...[
                ShiftConflictBanner(conflicts: state.overlapConflicts),
                const SizedBox(height: AppSpacing.s4),
              ],
              if (state.mutationError != null &&
                  state.mutationStatus == ShiftDetailMutationStatus.error &&
                  state.overlapConflicts.isEmpty) ...[
                AppAlert(variant: AppAlertVariant.danger, title: state.mutationError!),
                const SizedBox(height: AppSpacing.s4),
              ],
              if (_isEditMode)
                _EditShiftForm(
                  shiftDate: _editShiftDate,
                  startTime: _editStartTime,
                  endTime: _editEndTime,
                  notesController: _notesController,
                  enabled: !state.isSaving,
                  onShiftDateChanged: (value) => setState(() => _editShiftDate = value),
                  onStartTimeChanged: (value) => setState(() => _editStartTime = value),
                  onEndTimeChanged: (value) => setState(() => _editEndTime = value),
                  onDiscard: state.isSaving ? null : _exitEditMode,
                  onSave: state.isSaving || !_isEditFormReady() ? null : _saveEdit,
                  isSaving: state.isSaving,
                )
              else
                _ShiftSummaryCard(detail: detail),
              if (!_isEditMode) ...[
                const SizedBox(height: AppSpacing.s6),
                AppSectionHeader(title: 'Assigned staff'),
                const SizedBox(height: AppSpacing.s3),
                if (detail.isUnassigned)
                  const AppAlert(
                    key: Key('shift_detail_unassigned'),
                    variant: AppAlertVariant.warning,
                    title: 'Unassigned',
                    body: 'No staff are scheduled for this shift yet.',
                  )
                else
                  ...detail.assignments.map(
                    (assignment) => _AssigneeRow(
                      assignment: assignment,
                      canRemove: canEditAssignments,
                      isSaving: state.isSaving,
                      onRemove: () => _confirmRemoveAssignment(assignment.staffMemberId, assignment.displayName),
                    ),
                  ),
                if (canEditAssignments) ...[
                  const SizedBox(height: AppSpacing.s4),
                  _AssignmentPanel(state: state),
                ],
                if (canEdit) ...[
                  const SizedBox(height: AppSpacing.s6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      key: const Key('shift_detail_cancel_shift_button'),
                      label: 'Cancel shift',
                      variant: AppButtonVariant.danger,
                      leadingIcon: LucideIcons.calendarX,
                      onPressed: state.isSaving ? null : _confirmCancelShift,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
    );
  }
}

class _ShiftSummaryCard extends StatelessWidget {
  const _ShiftSummaryCard({required this.detail});

  final ShiftDetail detail;

  @override
  Widget build(BuildContext context) {
    return AppDescriptionList(
      items: [
        AppDescriptionItem(
          label: 'Date',
          value: Text(ShiftPresentationFormatting.formatDate(detail.shiftDate)),
        ),
        AppDescriptionItem(
          label: 'Time',
          value: Text(ShiftPresentationFormatting.formatTimeRange(detail.startTime, detail.endTime)),
        ),
        AppDescriptionItem(label: 'Branch', value: Text(detail.branch.name)),
        if (detail.notes?.trim().isNotEmpty == true)
          AppDescriptionItem(label: 'Notes', value: Text(detail.notes!.trim())),
      ],
    );
  }
}

class _EditShiftForm extends StatelessWidget {
  const _EditShiftForm({
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.notesController,
    required this.enabled,
    required this.onShiftDateChanged,
    required this.onStartTimeChanged,
    required this.onEndTimeChanged,
    required this.onDiscard,
    required this.onSave,
    required this.isSaving,
  });

  final DateTime? shiftDate;
  final String? startTime;
  final String? endTime;
  final TextEditingController notesController;
  final bool enabled;
  final ValueChanged<DateTime?> onShiftDateChanged;
  final ValueChanged<String?> onStartTimeChanged;
  final ValueChanged<String?> onEndTimeChanged;
  final VoidCallback? onDiscard;
  final VoidCallback? onSave;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShiftFormFields(
          shiftDate: shiftDate,
          startTime: startTime,
          endTime: endTime,
          notesController: notesController,
          enabled: enabled,
          onShiftDateChanged: onShiftDateChanged,
          onStartTimeChanged: onStartTimeChanged,
          onEndTimeChanged: onEndTimeChanged,
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            Expanded(
              child: AppButton(
                key: const Key('shift_detail_edit_cancel'),
                label: 'Discard changes',
                variant: AppButtonVariant.secondary,
                onPressed: onDiscard,
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: AppButton(
                key: const Key('shift_detail_edit_save'),
                label: 'Save changes',
                loading: isSaving,
                onPressed: onSave,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssigneeRow extends StatelessWidget {
  const _AssigneeRow({
    required this.assignment,
    required this.canRemove,
    required this.isSaving,
    required this.onRemove,
  });

  final ShiftAssignment assignment;
  final bool canRemove;
  final bool isSaving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Row(
        children: [
          AppIcon(icon: LucideIcons.user, dimension: AppSpacing.s5, color: colors.iconDefault),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Text(
              assignment.displayName,
              key: Key('shift_detail_assignee_${assignment.staffMemberId}'),
              style: typography.body,
            ),
          ),
          if (canRemove)
            AppIconButton(
              key: Key('shift_detail_remove_assignee_${assignment.staffMemberId}'),
              icon: LucideIcons.userMinus,
              semanticLabel: 'Remove ${assignment.displayName}',
              onPressed: isSaving ? null : onRemove,
            ),
        ],
      ),
    );
  }
}

class _AssignmentPanel extends ConsumerWidget {
  const _AssignmentPanel({required this.state});

  final ShiftDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedIds = {for (final assignment in state.detail.assignments) assignment.staffMemberId};
    final notifier = ref.read(shiftDetailProvider(state.detail.id).notifier);

    return AppCard(
      key: const Key('shift_detail_assignment_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(title: 'Add staff'),
          const SizedBox(height: AppSpacing.s3),
          ShiftStaffMultiSelect(
            selectedStaffIds: state.pendingAddStaffIds,
            excludeStaffIds: assignedIds,
            enabled: !state.isSaving,
            onChanged: notifier.setPendingAddStaffIds,
          ),
          const SizedBox(height: AppSpacing.s3),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              key: const Key('shift_detail_add_staff_submit'),
              label: 'Add selected staff',
              loading: state.isSaving,
              disabled: state.pendingAddStaffIds.isEmpty,
              onPressed: state.isSaving || state.pendingAddStaffIds.isEmpty ? null : () => notifier.addPendingStaff(),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: AppAlert(
        key: const Key('shift_detail_read_only_banner'),
        variant: AppAlertVariant.info,
        title: message,
      ),
    );
  }
}
