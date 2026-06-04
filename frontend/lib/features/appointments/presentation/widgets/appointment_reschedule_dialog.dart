import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/conflict_error_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/duration_field.dart';

/// Reschedule a `scheduled` planned appointment to a new slot (V1-4 US6).
class AppointmentRescheduleDialog extends ConsumerStatefulWidget {
  const AppointmentRescheduleDialog({required this.item, super.key});

  final AppointmentListItem item;

  static Future<CreateAppointmentResult?> show(BuildContext context, {required AppointmentListItem item}) {
    return showDialog<CreateAppointmentResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppointmentRescheduleDialog(item: item),
    );
  }

  @override
  ConsumerState<AppointmentRescheduleDialog> createState() => _AppointmentRescheduleDialogState();
}

class _AppointmentRescheduleDialogState extends ConsumerState<AppointmentRescheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _durationController = TextEditingController();

  AppointmentSettings? _settings;
  bool _loadingSettings = true;
  String? _settingsError;
  late DateTime _startTime;
  bool _isSaving = false;
  String? _formError;
  String? _conflictMessage;

  AppointmentListItem get _item => widget.item;

  int get _currentDurationMinutes {
    final minutes = _item.endTime.difference(_item.startTime).inMinutes;
    return minutes.clamp(5, 240);
  }

  @override
  void initState() {
    super.initState();
    _startTime = _item.startTime.toLocal();
    _durationController.text = _currentDurationMinutes.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _loadingSettings = false;
        _settingsError = 'Select an active branch before rescheduling.';
      });
      return;
    }

    try {
      final settings = await ref.read(appointmentRepositoryProvider).getSettings(branchId: branchId);
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = settings;
        _loadingSettings = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingSettings = false;
        _settingsError = error is RpcFailure
            ? appointmentMessageForRpc(error)
            : UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  Future<void> _pickStartTime() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final schedule = _settings?.workingSchedule;

    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: today,
      lastDate: now.add(const Duration(days: 365)),
      selectableDayPredicate: schedule == null
          ? null
          : (day) => AppointmentBranchWorkingHours.isWorkingDay(schedule, day),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_startTime));
    if (time == null || !mounted) {
      return;
    }

    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isBefore(now)) {
      setState(() => _formError = 'Start time must be in the future.');
      return;
    }

    final duration = int.tryParse(_durationController.text.trim());
    if (schedule != null && duration != null) {
      final hoursMessage = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: picked,
        durationMinutes: duration,
      );
      if (hoursMessage != null) {
        setState(() {
          _formError = hoursMessage;
          _conflictMessage = null;
        });
        return;
      }
    }

    setState(() {
      _startTime = picked;
      _conflictMessage = null;
      _formError = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null) {
      setState(() => _formError = 'Enter a valid duration in minutes.');
      return;
    }

    if (_startTime.isBefore(DateTime.now())) {
      setState(() => _formError = 'Start time must be in the future.');
      return;
    }

    final schedule = _settings?.workingSchedule;
    if (schedule != null) {
      final hoursMessage = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: _startTime,
        durationMinutes: duration,
      );
      if (hoursMessage != null) {
        setState(() => _formError = hoursMessage);
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _formError = null;
      _conflictMessage = null;
    });

    try {
      final result = await ref
          .read(appointmentRepositoryProvider)
          .rescheduleAppointment(appointmentId: _item.id, startTime: _startTime, durationMinutes: duration);

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'SCHEDULE_CONFLICT') {
        setState(() {
          _isSaving = false;
          _conflictMessage = appointmentMessageForRpc(error);
        });
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = appointmentMessageForRpc(error);
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

  String _startTimeLabel() {
    final local = _startTime;
    return '${MaterialLocalizations.of(context).formatMediumDate(local)} '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final minMinutes = settings?.minDurationMinutes ?? 5;
    final maxMinutes = settings?.maxDurationMinutes ?? 240;

    return AlertDialog(
      key: const Key('appointment_reschedule_dialog'),
      title: const Text('Reschedule appointment'),
      content: SizedBox(
        width: 420,
        child: _loadingSettings
            ? const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            : _settingsError != null
            ? Text(_settingsError!, style: TextStyle(color: Theme.of(context).colorScheme.error))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${_item.patientName} · ${_item.doctorDisplayName}'),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        key: const Key('appointment_reschedule_pick_time'),
                        onPressed: _isSaving ? null : _pickStartTime,
                        child: Align(alignment: Alignment.centerLeft, child: Text('Start: ${_startTimeLabel()}')),
                      ),
                      const SizedBox(height: 12),
                      DurationField(
                        controller: _durationController,
                        startTime: _startTime,
                        minMinutes: minMinutes,
                        maxMinutes: maxMinutes,
                        workingSchedule: settings?.workingSchedule,
                        enabled: !_isSaving,
                      ),
                      if (_conflictMessage != null) ...[
                        const SizedBox(height: 12),
                        ConflictErrorBanner(message: _conflictMessage!),
                      ],
                      if (_formError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _formError!,
                          key: const Key('appointment_reschedule_error'),
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const Key('appointment_reschedule_cancel'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('appointment_reschedule_confirm'),
          onPressed: _isSaving || _loadingSettings || _settingsError != null ? null : _submit,
          child: _isSaving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
