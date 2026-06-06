import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/shifts/data/shift_repository.dart';
import 'package:ai_clinic/features/shifts/domain/shift_overlap_conflict.dart';
import 'package:ai_clinic/features/shifts/presentation/shift_rpc_messages.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_conflict_banner.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_form_fields.dart';
import 'package:ai_clinic/features/shifts/presentation/widgets/shift_staff_multi_select.dart';

/// Create a branch shift with optional staff assignments (V1-7 US1).
class ShiftCreatePage extends ConsumerStatefulWidget {
  const ShiftCreatePage({super.key});

  @override
  ConsumerState<ShiftCreatePage> createState() => _ShiftCreatePageState();
}

class _ShiftCreatePageState extends ConsumerState<ShiftCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  DateTime? _shiftDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  Set<String> _selectedStaffIds = {};
  bool _isSaving = false;
  String? _formError;
  List<ShiftOverlapConflict> _conflicts = const [];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  bool _isFormReady() {
    if (_shiftDate == null || _startTime == null || _endTime == null) {
      return false;
    }
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    return endMinutes > startMinutes;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

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
      final shiftId = await ref
          .read(shiftRepositoryProvider)
          .createShift(
            branchId: branchId,
            shiftDate: _shiftDate!,
            startTime: _formatTime(_startTime!),
            endTime: _formatTime(_endTime!),
            notes: _trimOrNull(_notesController.text),
            staffIds: _selectedStaffIds.toList(growable: false),
          );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift created successfully.')));
      context.go(AppRoutes.shiftDetail(shiftId));
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'shift_overlap') {
        setState(() {
          _isSaving = false;
          _conflicts = ShiftRepository.parseOverlapConflicts(error.message);
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

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(permissionServiceProvider).canManageShifts();

    if (!canManage) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('New Shift'),
          leading: IconButton(
            tooltip: 'Go back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.nav.popOrHome(),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to create shifts.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Shift'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSaving ? null : () => context.nav.popOrHome(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
            const SizedBox(height: 24),
            ShiftStaffMultiSelect(
              selectedStaffIds: _selectedStaffIds,
              enabled: !_isSaving,
              onChanged: (value) => setState(() {
                _selectedStaffIds = value;
                _conflicts = const [];
              }),
            ),
            if (_conflicts.isNotEmpty) ...[const SizedBox(height: 16), ShiftConflictBanner(conflicts: _conflicts)],
            if (_formError != null) ...[
              const SizedBox(height: 16),
              Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('shift_create_submit'),
              onPressed: _isSaving || !_isFormReady() ? null : _submit,
              child: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create shift'),
            ),
          ],
        ),
      ),
    );
  }
}
