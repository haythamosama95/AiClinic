import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/components/app_step_panel.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_booking_slots.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_confirmed_step.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_step1.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_booking_step2.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_picker.dart';

/// Booking form opened from the calendar or the page header action.
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
    this.onPhaseChanged,
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
  final VoidCallback? onPhaseChanged;

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
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context, listen: false),
        child: _AppointmentBookingDialogHost(
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

  int _step = 0;
  DateTime? _selectedDate;
  DateTime? _selectedSlotStart;
  List<AppointmentListItem> _branchAppointments = const [];
  bool _loadingBranchAppointments = false;
  int _branchAppointmentsRequestId = 0;
  DateTime? _loadedAppointmentsDay;

  bool _isSaving = false;
  bool _bookingConfirmed = false;
  String? _formError;
  String? _conflictMessage;
  String? _patientError;
  String? _branchError;
  String? _dateError;
  String? _timeError;

  bool get _isEditMode => widget.existingAppointment != null;

  bool get bookingConfirmed => _bookingConfirmed;

  int get bookingStep => _step;

  bool get isSaving => _isSaving;

  void _notifyPhaseChanged() => widget.onPhaseChanged?.call();

  bool get _isMultiStepBooking => !_isEditMode;

  bool get _canEditSchedule => !_isEditMode || widget.existingAppointment!.status == AppointmentStatus.scheduled;

  @override
  void initState() {
    super.initState();
    _selectedBranchId = widget.branchId;
    _startTime = widget.slotStart.toLocal();
    _endTime = widget.slotEnd.toLocal();
    _selectedDoctorId = widget.initialDoctorId;
    _selectedDate = DateTime(_startTime.year, _startTime.month, _startTime.day);
    _selectedSlotStart = _startTime;

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
      _notifyPhaseChanged();
    });
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

  Future<void> _loadBranchAppointmentsForDay(DateTime day) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    final normalizedDay = DateTime(day.year, day.month, day.day);
    final requestId = ++_branchAppointmentsRequestId;
    final showLoadingSpinner = !_hasCachedAppointmentsForDay(normalizedDay);
    final range = AppointmentBookingSlots.dayFetchRange(normalizedDay);

    if (mounted && showLoadingSpinner) {
      setState(() => _loadingBranchAppointments = true);
    }

    try {
      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: _selectedBranchId, from: range.from, to: range.to);
      if (!mounted || requestId != _branchAppointmentsRequestId) {
        return;
      }
      setState(() {
        _branchAppointments = items;
        _loadedAppointmentsDay = normalizedDay;
        _loadingBranchAppointments = false;
      });
    } catch (_) {
      if (!mounted || requestId != _branchAppointmentsRequestId) {
        return;
      }
      setState(() {
        _branchAppointments = const [];
        _loadedAppointmentsDay = null;
        _loadingBranchAppointments = false;
      });
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _hasCachedAppointmentsForDay(DateTime day) {
    final loadedDay = _loadedAppointmentsDay;
    return loadedDay != null && _isSameDay(loadedDay, day);
  }

  void _onBookingDateSelected(DateTime date) {
    final normalizedDay = DateTime(date.year, date.month, date.day);
    final sameDay = _selectedDate != null && _isSameDay(_selectedDate!, normalizedDay);

    setState(() {
      _selectedDate = normalizedDay;
      if (!sameDay) {
        _selectedSlotStart = null;
      }
      _dateError = null;
      _timeError = null;
    });

    if (!sameDay || !_hasCachedAppointmentsForDay(normalizedDay)) {
      unawaited(_loadBranchAppointmentsForDay(normalizedDay));
    }
  }

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int get _durationMinutes {
    final settings = _settings;
    if (_isMultiStepBooking && settings != null) {
      return settings.defaultDurationMinutes;
    }
    return _endTime.difference(_startTime).inMinutes;
  }

  int get _slotMinutes => AppointmentBookingSlots.defaultSlotMinutes(_settings?.defaultDurationMinutes);

  DateTime get _today => DateTime(clock.now().year, clock.now().month, clock.now().day);

  List<AppointmentBookingTimeSlot> get _slotsForSelectedDay {
    final date = _selectedDate;
    final settings = _settings;
    if (date == null || settings == null) {
      return const [];
    }

    final schedule = _effectiveSchedule(settings);
    return AppointmentBookingSlots.slotsForDay(
      schedule: schedule,
      date: date,
      slotMinutes: _slotMinutes,
      durationMinutes: _durationMinutes,
      branchDoctors: _branchDoctors,
      existingAppointments: _branchAppointments,
      preferredDoctorId: _selectedDoctorId,
    );
  }

  List<StaffListItem> get _branchDoctors {
    return widget.doctors.where((doctor) => doctor.isAssignedToBranch(_selectedBranchId)).toList(growable: false);
  }

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

  void _clearStepErrors() {
    _patientError = null;
    _branchError = null;
    _dateError = null;
    _timeError = null;
    _formError = null;
  }

  bool _validateStep1() {
    var valid = true;
    _patientError = _selectedPatient == null ? 'Select a patient to continue.' : null;
    _branchError = _selectedBranchId.trim().isEmpty ? 'Select a branch to continue.' : null;
    if (_patientError != null || _branchError != null) {
      valid = false;
    }
    setState(() {});
    return valid;
  }

  bool _validateStep2() {
    var valid = true;
    _dateError = _selectedDate == null ? 'Pick a day for the appointment.' : null;
    _timeError = _selectedSlotStart == null ? 'Choose an available time slot.' : null;

    if (_selectedSlotStart != null) {
      final slot = _slotsForSelectedDay.where((item) => item.start == _selectedSlotStart).firstOrNull;
      if (slot == null || slot.status == AppointmentBookingSlotStatus.locked) {
        _timeError = 'This slot is no longer available.';
        valid = false;
      }
    } else {
      valid = false;
    }

    if (_dateError != null) {
      valid = false;
    }

    setState(() {});
    return valid;
  }

  Future<void> _goNext() async {
    if (!_validateStep1()) {
      return;
    }

    _selectedDate ??= DateTime(clock.now().year, clock.now().month, clock.now().day);
    setState(() {
      _step = 1;
      _clearStepErrors();
    });
    _notifyPhaseChanged();
    await _loadBranchAppointmentsForDay(_selectedDate!);
  }

  void _goBack() {
    _branchAppointmentsRequestId++;
    setState(() {
      _step = 0;
      _loadingBranchAppointments = false;
      _clearStepErrors();
    });
    _notifyPhaseChanged();
  }

  void _applySelectedSlot(AppointmentBookingTimeSlot slot) {
    setState(() {
      _selectedSlotStart = slot.start;
      _startTime = slot.start;
      _endTime = slot.start.add(Duration(minutes: _durationMinutes));
      _timeError = null;
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
    if (_isMultiStepBooking) {
      if (_step == 0) {
        await _goNext();
        return;
      }
      if (!_validateStep2()) {
        return;
      }

      final slot = _slotsForSelectedDay.where((item) => item.start == _selectedSlotStart).firstOrNull;
      if (slot != null) {
        final assignedDoctorId = AppointmentBookingSlots.resolveAssignedDoctorId(
          slot: slot,
          preferredDoctorId: _selectedDoctorId,
        );
        _selectedDoctorId = assignedDoctorId;
        _startTime = slot.start;
        _endTime = slot.start.add(Duration(minutes: _durationMinutes));
      }
    } else if (!(_formKey.currentState?.validate() ?? false)) {
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

    if (_isEditMode) {
      Navigator.of(context).pop(true);
      appToast(context, AppToastInput(message: 'Appointment updated successfully.', variant: AppToastVariant.success));
      return;
    }

    setState(() {
      _isSaving = false;
      _bookingConfirmed = true;
    });
    _notifyPhaseChanged();
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
      _selectedDate = null;
      _selectedSlotStart = null;
      _branchAppointments = const [];
      _loadedAppointmentsDay = null;
      _loadingBranchAppointments = false;
      _clearStepErrors();
    });
    _branchAppointmentsRequestId++;
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

  String? _doctorName(String? doctorId) {
    final normalized = doctorId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return widget.doctors.where((doctor) => doctor.id == normalized).firstOrNull?.fullName;
  }

  String _branchLabel(List<BranchListItem> branches) {
    final branch = branches.where((item) => item.id == _selectedBranchId).firstOrNull;
    if (branch != null) {
      return branch.name;
    }
    return widget.branchName?.trim().isNotEmpty == true ? widget.branchName!.trim() : '—';
  }

  Widget _buildBookingStep2(List<BranchListItem>? branches) {
    return AppointmentBookingStep2(
      patientName: _selectedPatient?.fullName ?? '—',
      branchName: branches != null ? _branchLabel(branches) : (widget.branchName ?? '—'),
      preferredDoctorName: _doctorName(_selectedDoctorId),
      hasPreferredDoctor: _selectedDoctorId?.trim().isNotEmpty == true,
      today: _today,
      selectedDate: _selectedDate,
      selectedSlotStart: _selectedSlotStart,
      slots: _slotsForSelectedDay,
      loadingSlots: _loadingBranchAppointments,
      slotMinutes: _slotMinutes,
      dateError: _dateError,
      timeError: _timeError,
      onDateSelected: _onBookingDateSelected,
      onSlotSelected: _applySelectedSlot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settings = _settings;
    final branchesAsync = ref.watch(appointmentCalendarBranchesProvider);
    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    final canEdit = _canEditSchedule && !_isSaving;
    final canChangeBranch = canEdit && !_isEditMode;
    final cachedBranches = branchesAsync.maybeWhen(data: (items) => items, orElse: () => null);

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

    if (_bookingConfirmed) {
      return AppStepPanel(
        stepKey: 'booking_confirmed',
        child: AppointmentBookingConfirmedStep(
          patientName: _selectedPatient?.fullName ?? '—',
          branchName: branchesAsync.maybeWhen(
            data: (branches) => _branchLabel(branches),
            orElse: () => widget.branchName?.trim().isNotEmpty == true ? widget.branchName!.trim() : '—',
          ),
          startTime: _startTime,
          durationMinutes: _durationMinutes,
          doctorName: _doctorName(_selectedDoctorId),
        ),
      );
    }

    if (_isEditMode) {
      return _buildEditForm(context, colors, settings, branchesAsync, today, canEdit, canChangeBranch);
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
          AppStepPanel(
            stepKey: 'booking_step_$_step',
            child: _step == 0
                ? branchesAsync.when(
                    data: (branches) => AppointmentBookingStep1(
                      branchId: _selectedBranchId,
                      branches: branches,
                      branchesLoading: false,
                      branchesError: false,
                      doctors: widget.doctors,
                      selectedPatient: _selectedPatient,
                      selectedDoctorId: _selectedDoctorId,
                      canEdit: canEdit,
                      canChangeBranch: canChangeBranch,
                      fallbackBranchName: widget.branchName,
                      patientError: _patientError,
                      branchError: _branchError,
                      onPatientChanged: (patient) => setState(() {
                        _selectedPatient = patient;
                        _patientError = null;
                        _formError = null;
                      }),
                      onBranchChanged: (branchId) => _onBranchChanged(branchId, branches),
                      onDoctorChanged: (doctorId) => setState(() {
                        _selectedDoctorId = doctorId;
                        _selectedSlotStart = null;
                        _formError = null;
                      }),
                      notesField: AppFormField(
                        id: 'appointment_booking_notes',
                        label: 'Notes (optional)',
                        hint: 'Internal notes for staff. Not visible to the patient.',
                        child: AppTextarea(
                          controller: _notesController,
                          disabled: _isSaving,
                          rows: 3,
                          onChanged: (_) {},
                        ),
                      ),
                    ),
                    loading: () => AppointmentBookingStep1(
                      branchId: _selectedBranchId,
                      branches: const [],
                      branchesLoading: true,
                      branchesError: false,
                      doctors: widget.doctors,
                      selectedPatient: _selectedPatient,
                      selectedDoctorId: _selectedDoctorId,
                      canEdit: canEdit,
                      canChangeBranch: canChangeBranch,
                      fallbackBranchName: widget.branchName,
                      patientError: _patientError,
                      branchError: _branchError,
                      onPatientChanged: (patient) => setState(() {
                        _selectedPatient = patient;
                        _patientError = null;
                      }),
                      onBranchChanged: (_) {},
                      onDoctorChanged: (doctorId) => setState(() => _selectedDoctorId = doctorId),
                    ),
                    error: (_, _) => AppointmentBookingStep1(
                      branchId: _selectedBranchId,
                      branches: [
                        if (_selectedBranchId.isNotEmpty)
                          BranchListItem(
                            id: _selectedBranchId,
                            name: widget.branchName?.trim().isNotEmpty == true
                                ? widget.branchName!.trim()
                                : 'Selected branch',
                            isActive: true,
                          ),
                      ],
                      branchesLoading: false,
                      branchesError: true,
                      doctors: widget.doctors,
                      selectedPatient: _selectedPatient,
                      selectedDoctorId: _selectedDoctorId,
                      canEdit: canEdit,
                      canChangeBranch: false,
                      fallbackBranchName: widget.branchName,
                      patientError: _patientError,
                      branchError: _branchError,
                      onPatientChanged: (patient) => setState(() => _selectedPatient = patient),
                      onBranchChanged: (_) {},
                      onDoctorChanged: (doctorId) => setState(() => _selectedDoctorId = doctorId),
                    ),
                  )
                : branchesAsync.when(
                    data: _buildBookingStep2,
                    loading: () => _buildBookingStep2(cachedBranches),
                    error: (_, _) => _buildBookingStep2(cachedBranches),
                  ),
          ),
        ],
      ),
    );
  }

  Widget buildDialogFooter(BuildContext context) => _buildFooter(context);

  Widget _buildFooter(BuildContext context) {
    if (_bookingConfirmed) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton(
          key: const Key('appointment_booking_done'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Done'),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step > 0)
          AppButton(
            variant: AppButtonVariant.secondary,
            disabled: _isSaving,
            onPressed: _isSaving ? null : _goBack,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back, size: 16),
                SizedBox(width: AppSpacing.space2),
                Text('Back'),
              ],
            ),
          )
        else
          AppButton(
            variant: AppButtonVariant.secondary,
            disabled: _isSaving,
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        const SizedBox(width: AppSpacing.space2),
        if (_step == 0)
          AppButton(
            key: const Key('appointment_booking_choose_time'),
            onPressed: _isSaving ? null : () => unawaited(_goNext()),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Choose time'),
                SizedBox(width: AppSpacing.space2),
                Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          )
        else
          AppButton(
            key: const Key('appointment_booking_submit'),
            loading: _isSaving,
            disabled: _isSaving,
            onPressed: _isSaving ? null : () => unawaited(_submit()),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_available, size: 16),
                SizedBox(width: AppSpacing.space2),
                Text('Confirm booking'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEditForm(
    BuildContext context,
    AppSemanticColors colors,
    AppointmentSettings settings,
    AsyncValue<List<BranchListItem>> branchesAsync,
    DateTime today,
    bool canEdit,
    bool canChangeBranch,
  ) {
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
                        onChanged: (doctorId) => setState(() => _selectedDoctorId = doctorId),
                      )
                    : AppFormField(
                        id: 'appointment_doctor',
                        label: 'Preferred doctor',
                        child: Text(
                          'No active doctors are configured.',
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
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(
              key: const Key('appointment_booking_update'),
              loading: _isSaving,
              disabled: _isSaving,
              onPressed: () => unawaited(_submit()),
              child: const Text('Update appointment'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog host with dynamic title and footer for the multi-step booking flow.
class _AppointmentBookingDialogHost extends StatefulWidget {
  const _AppointmentBookingDialogHost({
    required this.branchId,
    required this.schedule,
    required this.slotStart,
    required this.slotEnd,
    this.initialDoctorId,
    this.doctors = const [],
    this.existingAppointment,
    this.branchName,
  });

  final String branchId;
  final BranchWorkingSchedule schedule;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String? initialDoctorId;
  final List<StaffListItem> doctors;
  final AppointmentDetail? existingAppointment;
  final String? branchName;

  @override
  State<_AppointmentBookingDialogHost> createState() => _AppointmentBookingDialogHostState();
}

class _AppointmentBookingDialogHostState extends State<_AppointmentBookingDialogHost> {
  final _sheetKey = GlobalKey<_AppointmentBookingSheetState>();

  bool get _isEdit => widget.existingAppointment != null;

  _AppointmentBookingSheetState? get _sheet => _sheetKey.currentState;

  String get _title {
    if (_sheet?.bookingConfirmed == true) {
      return 'Appointment booked';
    }
    return _isEdit ? 'Edit appointment' : 'Book appointment';
  }

  String? get _description {
    if (_sheet?.bookingConfirmed == true) {
      return 'The visit is on the schedule.';
    }
    if (_isEdit && widget.existingAppointment!.status != AppointmentStatus.scheduled) {
      return 'Only doctor and notes can be changed after confirmation.';
    }
    if (_isEdit) {
      return null;
    }
    return switch (_sheet?.bookingStep) {
      1 => 'Pick a day and choose an open time slot.',
      _ => 'Patient, branch, and optional doctor preference.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backdropColor = isDark ? AppColorPrimitives.surfaceBackdropDark : AppColorPrimitives.surfaceBackdropLight;
    final confirmed = _sheet?.bookingConfirmed == true;
    final dismissible = !confirmed && !(_sheet?.isSaving ?? false);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismissible ? () => Navigator.of(context).pop() : null,
            child: ColoredBox(color: backdropColor),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Center(
                child: AppDialogPanel(
                  title: _title,
                  description: _description,
                  size: AppDialogSize.lg,
                  showCloseButton: dismissible,
                  showHeader: true,
                  onClose: () => Navigator.of(context).pop(),
                  footer: _isEdit ? null : _sheet?.buildDialogFooter(context),
                  child: AppointmentBookingSheet(
                    key: _sheetKey,
                    branchId: widget.branchId,
                    schedule: widget.schedule,
                    slotStart: widget.slotStart,
                    slotEnd: widget.slotEnd,
                    initialDoctorId: widget.initialDoctorId,
                    doctors: widget.doctors,
                    existingAppointment: widget.existingAppointment,
                    branchName: widget.branchName,
                    onPhaseChanged: () => setState(() {}),
                  ),
                ),
              ),
            ),
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
