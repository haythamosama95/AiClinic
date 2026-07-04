import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/shifts/application/shift_rpc_messages.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';
import 'package:ai_clinic/features/shifts/presentation/utils/shift_presentation_formatting.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_conflict_banner.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_form_fields.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_staff_multi_select.dart';

/// Create a branch shift with optional staff assignments (`/shifts/new`, V1-7 US1).
class ShiftCreatePage extends ConsumerStatefulWidget {
  const ShiftCreatePage({super.key});

  @override
  ConsumerState<ShiftCreatePage> createState() => _ShiftCreatePageState();
}

class _ShiftCreatePageState extends ConsumerState<ShiftCreatePage> {
  final _notesController = TextEditingController();

  DateTime? _shiftDate;
  String? _startTime;
  String? _endTime;
  Set<String> _selectedStaffIds = {};
  bool _isSaving = false;
  String? _formError;
  List<ShiftOverlapConflict> _conflicts = const [];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  bool _isFormReady() {
    if (_shiftDate == null || _startTime == null || _endTime == null) {
      return false;
    }
    return ShiftPresentationFormatting.isEndAfterStart(_startTime, _endTime);
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _submit() async {
    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() => _formError = 'Select an active branch in the shell before creating a shift.');
      return;
    }

    if (!_isFormReady()) {
      setState(() => _formError = 'Select a shift date, start time, and end time.');
      return;
    }

    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    if (_shiftDate!.isBefore(today)) {
      setState(() => _formError = 'Only today and future dates may be scheduled.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
      _conflicts = const [];
    });

    try {
      final shiftId = await ref.read(shiftRepositoryProvider).createShift(
            branchId: branchId,
            shiftDate: _shiftDate!,
            startTime: _startTime!,
            endTime: _endTime!,
            notes: _trimOrNull(_notesController.text),
            staffIds: _selectedStaffIds.toList(growable: false),
          );

      if (!mounted) {
        return;
      }

      ref.showAppToast(message: 'Shift created successfully.', variant: AppToastVariant.success);
      context.go(AppRoutes.shiftDetail(shiftId));
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'shift_overlap') {
        setState(() {
          _isSaving = false;
          _conflicts = ShiftRepository.parseOverlapConflicts(error.message, details: error.details);
        });
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = shiftMessageForRpc(error);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessShiftCreate(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'New shift',
        description: 'You do not have permission to create shifts.',
      );
    }

    return EditorFormPattern(
      title: 'New shift',
      description: 'Schedule branch coverage with optional staff assignments.',
      summaryAlert: _conflicts.isEmpty ? null : ShiftConflictBanner(conflicts: _conflicts),
      staleEditAlert: _formError == null ? null : AppAlert(variant: AppAlertVariant.danger, title: _formError!),
      sections: [
        EditorFormSection(
          title: 'Schedule',
          description: 'Choose the shift date and time range.',
          twoColumn: true,
          fields: [
            ShiftFormFields(
              shiftDate: _shiftDate,
              startTime: _startTime,
              endTime: _endTime,
              notesController: _notesController,
              enabled: !_isSaving,
              onShiftDateChanged: (value) => setState(() {
                _shiftDate = value;
                _formError = null;
                _conflicts = const [];
              }),
              onStartTimeChanged: (value) => setState(() {
                _startTime = value;
                _formError = null;
                _conflicts = const [];
              }),
              onEndTimeChanged: (value) => setState(() {
                _endTime = value;
                _formError = null;
                _conflicts = const [];
              }),
            ),
          ],
        ),
        EditorFormSection(
          title: 'Assignments',
          description: 'Optionally assign staff when creating the shift.',
          fields: [
            ShiftStaffMultiSelect(
              selectedStaffIds: _selectedStaffIds,
              enabled: !_isSaving,
              onChanged: (value) => setState(() {
                _selectedStaffIds = value;
                _conflicts = const [];
              }),
            ),
          ],
        ),
      ],
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: _isSaving ? null : () => context.nav.popOrHome(),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppButton(
            key: const Key('shift_create_submit'),
            label: 'Create shift',
            loading: _isSaving,
            disabled: !_isFormReady(),
            onPressed: _isSaving || !_isFormReady() ? null : _submit,
          ),
        ],
      ),
    );
  }
}
