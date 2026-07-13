import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_picker.dart';

/// Booking form opened from a calendar slot with pre-filled start and end times.
class AppointmentBookingSheet extends ConsumerStatefulWidget {
  const AppointmentBookingSheet({
    required this.branchId,
    required this.schedule,
    required this.slotStart,
    required this.slotEnd,
    this.initialDoctorId,
    this.doctors = const [],
    this.existingAppointment,
    this.branchName,
    super.key,
  });

  final String branchId;
  final BranchWorkingSchedule schedule;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String? initialDoctorId;
  final List<StaffListItem> doctors;
  final AppointmentDetail? existingAppointment;
  final String? branchName;

  /// Presents the booking form. Returns `true` when an appointment was created or updated.
  static Future<bool?> show(
    BuildContext context, {
    required String branchId,
    required BranchWorkingSchedule schedule,
    required DateTime slotStart,
    required DateTime slotEnd,
    String? initialDoctorId,
    List<StaffListItem> doctors = const [],
    AppointmentDetail? existingAppointment,
    String? branchName,
  }) {
    final isEdit = existingAppointment != null;
    return AppDialog.show<bool>(
      context,
      title: isEdit ? 'Edit appointment' : 'Book appointment',
      description: isEdit && existingAppointment.status != AppointmentStatus.scheduled
          ? 'Only doctor and notes can be changed after confirmation.'
          : null,
      size: AppDialogSize.lg,
      child: UncontrolledProviderScope(
        container: ProviderScope.containerOf(context, listen: false),
        child: AppointmentBookingSheet(
          branchId: branchId,
          schedule: schedule,
          slotStart: slotStart,
          slotEnd: slotEnd,
          initialDoctorId: initialDoctorId,
          doctors: doctors,
          existingAppointment: existingAppointment,
          branchName: branchName,
        ),
      ),
    );
  }

  @override
  ConsumerState<AppointmentBookingSheet> createState() => _AppointmentBookingSheetState();
}

class _AppointmentBookingSheetState extends ConsumerState<AppointmentBookingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  AppointmentSettings? _settings;
  bool _loadingSettings = true;
  String? _settingsError;

  late DateTime _startTime;
  late DateTime _endTime;
  late String _selectedBranchId;
  PatientListItem? _selectedPatient;
  String? _selectedDoctorId;

  bool _isSaving = false;
  String? _formError;
  String? _conflictMessage;

  bool get _isEditMode => widget.existingAppointment != null;

  bool get _canEditSchedule => !_isEditMode || widget.existingAppointment!.status == AppointmentStatus.scheduled;

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.branchId;
    _startTime = widget.slotStart.toLocal();
    _endTime = widget.slotEnd.toLocal();
    _selectedDoctorId = widget.initialDoctorId;

    final existing = widget.existingAppointment;
    if (existing != null) {
      _selectedPatient = PatientListItem(
        id: existing.patientId,
        fullName: existing.patientName,
        registeringBranchId: existing.branchId,
        registeringBranchName: widget.branchName?.trim().isNotEmpty == true ? widget.branchName!.trim() : 'Branch',
      );
      if (existing.notes?.trim().isNotEmpty == true) {
        _notesController.text = existing.notes!.trim();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loadingSettings = true;
      _settingsError = null;
    });

    try {
      final settings = await ref.read(appointmentRepositoryProvider).getSettings(branchId: _selectedBranchId);
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

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int get _durationMinutes => _endTime.difference(_startTime).inMinutes;

  void _setStartTime(DateTime value) {
    setState(() {
      _startTime = value;
      if (!_endTime.isAfter(_startTime)) {
        final fallback = _settings?.defaultDurationMinutes ?? _durationMinutes.clamp(5, 9999);
        _endTime = _startTime.add(Duration(minutes: fallback));
      }
      _formError = null;
      _conflictMessage = null;
    });
  }

  void _setEndTime(DateTime value) {
    setState(() {
      _endTime = value;
      _formError = null;
      _conflictMessage = null;
    });
  }

  String? _validateTimes() {
    if (!_endTime.isAfter(_startTime)) {
      return 'End time must be after start time.';
    }

    final settings = _settings;
    if (settings == null) {
      return null;
    }

    final duration = _durationMinutes;
    if (duration < settings.minDurationMinutes) {
      return 'Duration must be at least ${settings.minDurationMinutes} minutes.';
    }

    final schedule = _effectiveSchedule(settings);
    final hoursMessage = AppointmentBranchWorkingHours.validationMessage(
      schedule: schedule,
      startTime: _startTime,
      durationMinutes: duration,
    );
    if (hoursMessage != null) {
      return hoursMessage;
    }

    if (_startTime.isBefore(clock.now()) && (!_isEditMode || _canEditSchedule)) {
      return 'Start time must be in the future.';
    }

    return null;
  }

  String? _validateNotes() {
    final notes = _notesController.text;
    if (notes.trim().length > 2000) {
      return 'Notes must be 2000 characters or fewer.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_selectedPatient == null) {
      setState(() => _formError = 'Select a patient.');
      return;
    }

    final timeError = _validateTimes();
    if (timeError != null) {
      setState(() => _formError = timeError);
      return;
    }

    final notesError = _validateNotes();
    if (notesError != null) {
      setState(() => _formError = notesError);
      return;
    }

    final settings = _settings;
    if (settings == null) {
      setState(() => _formError = 'Appointment settings are not loaded yet.');
      return;
    }

    final schedule = _effectiveSchedule(settings);
    if (!AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: _startTime, end: _endTime)) {
      setState(() => _formError = 'Appointment must be within branch working hours.');
      return;
    }

    final doctorId = _trimOrNull(_selectedDoctorId ?? '');
    final notes = _trimOrNull(_notesController.text);

    setState(() {
      _isSaving = true;
      _formError = null;
      _conflictMessage = null;
    });

    try {
      if (_isEditMode) {
        await ref
            .read(appointmentRepositoryProvider)
            .updateAppointment(
              appointmentId: widget.existingAppointment!.id,
              patientId: _selectedPatient!.id,
              doctorId: doctorId,
              startTime: _startTime,
              durationMinutes: _durationMinutes,
              notes: notes,
            );
      } else {
        await ref
            .read(appointmentRepositoryProvider)
            .createAppointment(
              branchId: _selectedBranchId,
              patientId: _selectedPatient!.id,
              doctorId: doctorId,
              type: AppointmentType.planned,
              startTime: _startTime,
              durationMinutes: _durationMinutes,
              notes: notes,
            );
      }
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
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _formError = UserErrorMapper.mapToUserMessage(error);
      });
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(true);
    appToast(
      context,
      AppToastInput(
        message: _isEditMode ? 'Appointment updated successfully.' : 'Appointment booked successfully.',
        variant: AppToastVariant.success,
      ),
    );
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  BranchWorkingSchedule _effectiveSchedule(AppointmentSettings settings) {
    final branches = ref
        .read(appointmentCalendarBranchesProvider)
        .maybeWhen(data: (items) => items, orElse: () => const <BranchListItem>[]);
    final branch = branches.where((item) => item.id == _selectedBranchId).firstOrNull;
    return settings.workingSchedule ?? branch?.workingSchedule ?? widget.schedule;
  }

  void _onBranchChanged(String branchId, List<BranchListItem> branches) {
    if (branchId.isEmpty || branchId == _selectedBranchId) {
      return;
    }

    final doctorId = _selectedDoctorId;
    if (doctorId != null && doctorId.isNotEmpty) {
      final doctor = widget.doctors.where((item) => item.id == doctorId).firstOrNull;
      if (doctor != null && !doctor.isAssignedToBranch(branchId)) {
        _selectedDoctorId = null;
      }
    }

    setState(() {
      _selectedBranchId = branchId;
      _formError = null;
      _conflictMessage = null;
    });
    unawaited(_loadSettings());
  }

  TimeOfDay _minutesToTime(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  String _pad(int value) => value.toString().padLeft(2, '0');

  int? _parseTime(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = _settings;
    final branchesAsync = ref.watch(appointmentCalendarBranchesProvider);
    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    final canEdit = _canEditSchedule && !_isSaving;
    final canChangeBranch = canEdit && !_isEditMode;

    if (_loadingSettings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.space12),
        child: Center(child: AppProgress(variant: ProgressVariant.circular, indeterminate: true)),
      );
    }

    if (_settingsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppAlert(title: _settingsError!, variant: AppAlertVariant.danger),
          const SizedBox(height: AppSpacing.space4),
          AppButton(variant: AppButtonVariant.secondary, onPressed: _loadSettings, child: const Text('Retry')),
        ],
      );
    }

    if (settings == null) {
      return const SizedBox.shrink();
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_conflictMessage != null) ...[
            AppAlert(title: _conflictMessage!, variant: AppAlertVariant.danger),
            const SizedBox(height: AppSpacing.space4),
          ],
          if (_formError != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(_formError!, style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg)),
            ),
            const SizedBox(height: AppSpacing.space4),
          ],
          PatientPicker(
            branchId: _selectedBranchId,
            scope: PatientListScope.allBranches,
            hint: 'Search across all branches by name, MRN, email, or phone.',
            value: _selectedPatient,
            enabled: canEdit,
            onChanged: (patient) => setState(() {
              _selectedPatient = patient;
              _formError = null;
            }),
            searchFieldKey: const Key('appointment_booking_patient_search'),
            clearButtonKey: const Key('patient_picker_clear'),
          ),
          const SizedBox(height: AppSpacing.space4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppFormField(
                  id: 'appointment_booking_branch',
                  label: 'Branch',
                  hint: 'The clinic location where this visit takes place.',
                  child: branchesAsync.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return Text(
                          widget.branchName?.trim().isNotEmpty == true ? widget.branchName!.trim() : 'Branch',
                          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                        );
                      }

                      return AppSelect(
                        key: const Key('appointment_booking_branch'),
                        options: [for (final branch in items) AppSelectOption(value: branch.id, label: branch.name)],
                        value: _selectedBranchId,
                        disabled: !canChangeBranch || items.isEmpty,
                        placeholder: 'Select branch',
                        onChanged: canChangeBranch ? (branchId) => _onBranchChanged(branchId, items) : null,
                      );
                    },
                    loading: () => const AppProgress(variant: ProgressVariant.circular, indeterminate: true),
                    error: (_, _) => AppSelect(
                      key: const Key('appointment_booking_branch'),
                      options: [
                        if (_selectedBranchId.isNotEmpty)
                          AppSelectOption(
                            value: _selectedBranchId,
                            label: widget.branchName?.trim().isNotEmpty == true
                                ? widget.branchName!.trim()
                                : 'Selected branch',
                          ),
                      ],
                      value: _selectedBranchId,
                      disabled: true,
                      placeholder: 'Branch unavailable',
                      onChanged: null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: widget.doctors.isNotEmpty
                    ? AppointmentDoctorSelector(
                        key: const Key('doctor_selector'),
                        branchId: _selectedBranchId,
                        doctors: widget.doctors,
                        value: _selectedDoctorId,
                        enabled: !_isSaving,
                        hint:
                            'Assign a doctor when the patient asked for one. Leave unassigned if they have no preference.',
                        onChanged: (doctorId) => setState(() => _selectedDoctorId = doctorId),
                      )
                    : AppFormField(
                        id: 'appointment_doctor',
                        label: 'Preferred doctor',
                        hint:
                            'Assign a doctor when the patient asked for one. Leave unassigned if they have no preference.',
                        child: Text(
                          'No active doctors are configured. You can still book without a preferred doctor.',
                          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 5,
                child: AppFormField(
                  id: 'appointment_booking_pick_date',
                  label: 'Date',
                  hint: 'The day of the visit.',
                  child: AppDatePicker(
                    key: const Key('appointment_booking_pick_date'),
                    value: DateTime(_startTime.year, _startTime.month, _startTime.day),
                    min: today,
                    max: today.add(const Duration(days: 365)),
                    disabled: !canEdit,
                    onChanged: (date) {
                      if (date == null) {
                        return;
                      }
                      _setStartTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_startTime)));
                      _setEndTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_endTime)));
                    },
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                flex: 4,
                child: _BookingTimeField(
                  hint: 'When the visit begins. Must fall within branch working hours.',
                  child: AppTimePicker(
                    key: const Key('appointment_booking_pick_start'),
                    value: '${_pad(_startTime.hour)}:${_pad(_startTime.minute)}',
                    use24Hour: false,
                    disabled: !canEdit,
                    onChanged: (value) {
                      final minutes = _parseTime(value);
                      if (minutes == null) {
                        return;
                      }
                      _setStartTime(_combineDateAndTime(_startTime, _minutesToTime(minutes)));
                    },
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                flex: 4,
                child: _BookingTimeField(
                  hint: 'When the visit ends. Must be after the start time.',
                  child: AppTimePicker(
                    key: const Key('appointment_booking_pick_end'),
                    value: '${_pad(_endTime.hour)}:${_pad(_endTime.minute)}',
                    use24Hour: false,
                    disabled: !canEdit,
                    onChanged: (value) {
                      final minutes = _parseTime(value);
                      if (minutes == null) {
                        return;
                      }
                      _setEndTime(_combineDateAndTime(_endTime, _minutesToTime(minutes)));
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          AppFormField(
            id: 'appointment_booking_notes',
            label: 'Notes (optional)',
            hint: 'Internal notes for staff. Not visible to the patient.',
            child: AppTextarea(controller: _notesController, disabled: _isSaving, rows: 3, onChanged: (_) {}),
          ),
          const SizedBox(height: AppSpacing.space6),
          AppButton(
            key: Key(_isEditMode ? 'appointment_booking_update' : 'appointment_booking_submit'),
            loading: _isSaving,
            disabled: _isSaving,
            onPressed: _submit,
            child: Text(_isEditMode ? 'Update appointment' : 'Book appointment'),
          ),
        ],
      ),
    );
  }
}

/// Time input with a tooltip aligned to labeled fields in the booking row.
class _BookingTimeField extends StatelessWidget {
  const _BookingTimeField({required this.hint, required this.child});

  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppTooltip(
              message: hint,
              preferBelow: false,
              child: Semantics(
                button: true,
                label: 'More information',
                child: IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.help_outline, size: 16, color: colors.iconMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 20, height: 20),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        child,
      ],
    );
  }
}
