import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Booking form opened from a calendar slot with pre-filled start and end times.
class AppointmentBookingSheet extends ConsumerStatefulWidget {
  const AppointmentBookingSheet({
    required this.branchId,
    required this.schedule,
    required this.slotStart,
    required this.slotEnd,
    this.initialDoctorId,
    this.doctors = const [],
    super.key,
  });

  final String branchId;
  final BranchWorkingSchedule schedule;
  final DateTime slotStart;
  final DateTime slotEnd;
  final String? initialDoctorId;
  final List<StaffListItem> doctors;

  /// Presents the booking sheet. Returns `true` when an appointment was created.
  static Future<bool?> show(
    BuildContext context, {
    required String branchId,
    required BranchWorkingSchedule schedule,
    required DateTime slotStart,
    required DateTime slotEnd,
    String? initialDoctorId,
    List<StaffListItem> doctors = const [],
  }) {
    return AppSheets.showModal<bool>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => AppointmentBookingSheet(
        branchId: branchId,
        schedule: schedule,
        slotStart: slotStart,
        slotEnd: slotEnd,
        initialDoctorId: initialDoctorId,
        doctors: doctors,
      ),
    );
  }

  @override
  ConsumerState<AppointmentBookingSheet> createState() => _AppointmentBookingSheetState();
}

class _AppointmentBookingSheetState extends ConsumerState<AppointmentBookingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _patientSearchController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentSettings? _settings;
  bool _loadingSettings = true;
  String? _settingsError;

  late DateTime _startTime;
  late DateTime _endTime;
  PatientListItem? _selectedPatient;
  String? _selectedDoctorId;

  List<PatientListItem> _patientResults = const [];
  bool _searchingPatients = false;
  String? _patientSearchError;
  String _lastPatientQuery = '';
  Timer? _patientSearchDebounce;

  bool _isSaving = false;
  String? _formError;
  String? _conflictMessage;

  @override
  void initState() {
    super.initState();
    _startTime = widget.slotStart.toLocal();
    _endTime = widget.slotEnd.toLocal();
    _selectedDoctorId = widget.initialDoctorId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _patientSearchDebounce?.cancel();
    _patientSearchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loadingSettings = true;
      _settingsError = null;
    });

    try {
      final settings = await ref.read(appointmentRepositoryProvider).getSettings(branchId: widget.branchId);
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

  void _onPatientSearchChanged(String query) {
    _lastPatientQuery = query;
    _patientSearchDebounce?.cancel();
    _patientSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      unawaited(_searchPatients(query));
    });
  }

  Future<void> _searchPatients(String query) async {
    if (!PatientSearchQuery.canInvokeRpc(query.isEmpty ? null : query)) {
      setState(() {
        _patientResults = const [];
        _patientSearchError = null;
        _searchingPatients = false;
      });
      return;
    }

    setState(() {
      _searchingPatients = true;
      _patientSearchError = null;
    });

    try {
      final page = await ref.read(searchPatientsUseCaseProvider)(
        query: query.isEmpty ? null : query,
        scope: PatientListScope.thisBranch,
        branchId: widget.branchId,
        limit: 10,
      );
      if (!mounted || _lastPatientQuery != query) {
        return;
      }
      setState(() {
        _searchingPatients = false;
        _patientResults = page.items;
      });
    } catch (_) {
      if (!mounted || _lastPatientQuery != query) {
        return;
      }
      setState(() {
        _searchingPatients = false;
        _patientResults = const [];
        _patientSearchError = 'Could not search patients.';
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

    final schedule = settings.workingSchedule ?? widget.schedule;
    final hoursMessage = AppointmentBranchWorkingHours.validationMessage(
      schedule: schedule,
      startTime: _startTime,
      durationMinutes: duration,
    );
    if (hoursMessage != null) {
      return hoursMessage;
    }

    if (_startTime.isBefore(clock.now())) {
      return 'Start time must be in the future.';
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

    final settings = _settings;
    if (settings == null) {
      setState(() => _formError = 'Appointment settings are not loaded yet.');
      return;
    }

    final schedule = settings.workingSchedule ?? widget.schedule;
    if (!AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: _startTime, end: _endTime)) {
      setState(() => _formError = 'Appointment must be within branch working hours.');
      return;
    }

    final doctorId = _trimOrNull(_selectedDoctorId ?? '');

    setState(() {
      _isSaving = true;
      _formError = null;
      _conflictMessage = null;
    });

    try {
      await ref
          .read(appointmentRepositoryProvider)
          .createAppointment(
            branchId: widget.branchId,
            patientId: _selectedPatient!.id,
            doctorId: doctorId,
            type: AppointmentType.planned,
            startTime: _startTime,
            durationMinutes: _durationMinutes,
            notes: _trimOrNull(_notesController.text),
          );
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
    AppToast.success(context, message: 'Appointment booked successfully.');
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Map<String, String> get _doctorItems {
    return {'No doctor assigned': '', for (final doctor in widget.doctors) doctor.fullName: doctor.id};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final settings = _settings;
    final today = DateTime(clock.now().year, clock.now().month, clock.now().day);
    final hoursLabel = AppointmentBranchWorkingHours.hoursLabelForDate(widget.schedule, _startTime);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SpacingTokens.lg, SpacingTokens.md, SpacingTokens.lg, SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Book appointment', style: theme.textTheme.titleMedium)),
                AppIconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.md),
            if (_loadingSettings)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: SpacingTokens.xl),
                child: Center(child: AppCircularProgress()),
              )
            else if (_settingsError != null) ...[
              AppAlert(title: _settingsError!, variant: AppAlertVariant.destructive),
              const SizedBox(height: SpacingTokens.sm),
              AppButton(label: 'Retry', variant: AppButtonVariant.secondary, onPressed: _loadSettings),
            ] else if (settings != null)
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_conflictMessage != null) ...[
                          AppAlert(title: _conflictMessage!, variant: AppAlertVariant.destructive),
                          const SizedBox(height: SpacingTokens.md),
                        ],
                        if (_formError != null) ...[
                          Text(_formError!, style: theme.textTheme.bodyMedium?.copyWith(color: colors.destructive)),
                          const SizedBox(height: SpacingTokens.md),
                        ],
                        AppTextField(
                          key: const Key('appointment_booking_patient_search'),
                          label: 'Patient',
                          controller: _patientSearchController,
                          enabled: !_isSaving && _selectedPatient == null,
                          hintText: 'Search by name or phone',
                          description: PatientSearchQuery.helperForDraft(_patientSearchController.text),
                          onChanged: _onPatientSearchChanged,
                        ),
                        if (_searchingPatients) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          const AppLinearProgress(),
                        ],
                        if (_patientSearchError != null) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          Text(_patientSearchError!, style: TextStyle(color: colors.destructive)),
                        ],
                        if (_selectedPatient != null) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          AppCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_selectedPatient!.fullName}${_selectedPatient!.phone != null ? ' · ${_selectedPatient!.phone}' : ''}',
                                  ),
                                ),
                                if (!_isSaving)
                                  AppButton(
                                    key: const Key('patient_picker_clear'),
                                    label: 'Clear',
                                    variant: AppButtonVariant.ghost,
                                    onPressed: () => setState(() => _selectedPatient = null),
                                  ),
                              ],
                            ),
                          ),
                        ] else if (_patientResults.isNotEmpty) ...[
                          const SizedBox(height: SpacingTokens.sm),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _patientResults.length,
                              separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
                              itemBuilder: (context, index) {
                                final patient = _patientResults[index];
                                return ListTile(
                                  key: Key('patient_picker_result_$index'),
                                  title: Text(patient.fullName),
                                  subtitle: Text(patient.phone ?? patient.registeringBranchName),
                                  onTap: _isSaving
                                      ? null
                                      : () {
                                          setState(() {
                                            _selectedPatient = patient;
                                            _patientResults = const [];
                                            _patientSearchController.clear();
                                            _lastPatientQuery = '';
                                            _formError = null;
                                          });
                                        },
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: SpacingTokens.md),
                        if (widget.doctors.isNotEmpty)
                          AppSelect<String>(
                            key: const Key('doctor_selector'),
                            label: 'Doctor (optional)',
                            items: _doctorItems,
                            value: _selectedDoctorId ?? '',
                            enabled: !_isSaving,
                            onChanged: (doctorId) => setState(() {
                              _selectedDoctorId = doctorId == null || doctorId.isEmpty ? null : doctorId;
                            }),
                          )
                        else
                          Text(
                            'No active doctors are configured. You can still book without assigning one.',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                          ),
                        const SizedBox(height: SpacingTokens.md),
                        AppDateField(
                          key: const Key('appointment_booking_pick_date'),
                          label: 'Date',
                          value: DateTime(_startTime.year, _startTime.month, _startTime.day),
                          firstDate: today,
                          lastDate: today.add(const Duration(days: 365)),
                          enabled: !_isSaving,
                          onChanged: (date) {
                            if (date == null) {
                              return;
                            }
                            _setStartTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_startTime)));
                            _setEndTime(_combineDateAndTime(date, TimeOfDay.fromDateTime(_endTime)));
                          },
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: AppClockTimeField(
                                key: const Key('appointment_booking_pick_start'),
                                label: 'Start time',
                                value: TimeOfDay.fromDateTime(_startTime),
                                enabled: !_isSaving,
                                description: hoursLabel == null ? null : 'Branch hours: $hoursLabel',
                                onChanged: (time) {
                                  if (time == null) {
                                    return;
                                  }
                                  _setStartTime(_combineDateAndTime(_startTime, time));
                                },
                              ),
                            ),
                            const SizedBox(width: SpacingTokens.sm),
                            Expanded(
                              child: AppClockTimeField(
                                key: const Key('appointment_booking_pick_end'),
                                label: 'End time',
                                value: TimeOfDay.fromDateTime(_endTime),
                                enabled: !_isSaving,
                                onChanged: (time) {
                                  if (time == null) {
                                    return;
                                  }
                                  _setEndTime(_combineDateAndTime(_endTime, time));
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SpacingTokens.xs),
                        Text(
                          'Duration: $_durationMinutes min',
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                        ),
                        const SizedBox(height: SpacingTokens.md),
                        AppTextField(
                          label: 'Notes (optional)',
                          controller: _notesController,
                          enabled: !_isSaving,
                          maxLines: 3,
                        ),
                        const SizedBox(height: SpacingTokens.lg),
                        AppButton(
                          key: const Key('appointment_booking_submit'),
                          label: 'Book appointment',
                          onPressed: _isSaving ? null : _submit,
                          isLoading: _isSaving,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
