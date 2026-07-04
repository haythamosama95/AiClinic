import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/features/appointments/application/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_branch_working_hours.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_calendar_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_queue_provider.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';

/// Booking form composed inside [EditorFormPattern] for `/appointments/book`.
class AppointmentBookingForm extends ConsumerStatefulWidget {
  const AppointmentBookingForm({
    this.presentation = EditorFormPresentation.page,
    super.key,
  });

  final EditorFormPresentation presentation;

  @override
  ConsumerState<AppointmentBookingForm> createState() => _AppointmentBookingFormState();
}

class _AppointmentBookingFormState extends ConsumerState<AppointmentBookingForm> {
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();
  final _patientSearchController = TextEditingController();

  AppointmentSettings? _settings;
  var _loadingSettings = true;
  String? _settingsError;
  DateTime? _startTime;
  DateTime? _endTime;
  PatientListItem? _selectedPatient;
  String? _selectedDoctorId;
  List<PatientListItem> _patientResults = const [];
  String? _patientSearchError;
  Timer? _patientSearchDebounce;
  var _isSaving = false;
  var _submitted = false;
  String? _summaryError;
  String? _conflictMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _patientSearchDebounce?.cancel();
    _durationController.dispose();
    _notesController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  String? get _branchId {
    final id = ref.read(authSessionProvider).context?.activeBranchId?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _loadSettings() async {
    final branchId = _branchId;
    if (branchId == null) {
      setState(() {
        _loadingSettings = false;
        _settingsError = 'Select an active branch before booking.';
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
        _durationController.text = settings.defaultDurationMinutes.toString();
        final now = clock.now();
        _startTime ??= DateTime(now.year, now.month, now.day, now.hour, now.minute);
        _endTime ??= _startTime!.add(Duration(minutes: settings.defaultDurationMinutes));
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

  void _onPatientQueryChanged(String query) {
    _patientSearchDebounce?.cancel();
    final hint = PatientSearchQuery.validationHint(query.trim().isEmpty ? null : query.trim());
    if (hint != null) {
      setState(() {
        _patientSearchError = hint;
        _patientResults = const [];
      });
      return;
    }

    _patientSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) {
        return;
      }
      setState(() {
        _patientSearchError = null;
      });
      try {
        final page = await ref.read(searchPatientsUseCaseProvider)(
          query: query.trim().isEmpty ? null : query.trim(),
          scope: PatientListScope.thisBranch,
          branchId: _branchId,
          limit: 8,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _patientResults = page.items;
        });
      } catch (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _patientSearchError = 'Unable to search patients. Try again.';
        });
      }
    });
  }

  Future<List<AppAutocompleteOption<PatientListItem>>> _searchPatients(String query) async {
    _onPatientQueryChanged(query);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) {
      return const [];
    }
    return [
      for (final patient in _patientResults)
        AppAutocompleteOption(
          value: patient,
          label: patient.fullName,
          meta: patient.registeringBranchName,
        ),
    ];
  }

  bool _validate() {
    final patientError = _selectedPatient == null ? 'Select a patient.' : null;
    final startError = _startTime == null ? 'Start time is required.' : null;
    final duration = int.tryParse(_durationController.text.trim());
    final durationError = duration == null || duration < 5 ? 'Duration must be at least 5 minutes.' : null;
    setState(() {
      _summaryError = patientError ?? startError ?? durationError;
    });
    return _summaryError == null;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (!_validate()) {
      return;
    }

    final branchId = _branchId;
    final patient = _selectedPatient;
    final startTime = _startTime;
    final duration = int.tryParse(_durationController.text.trim());
    if (branchId == null || patient == null || startTime == null || duration == null) {
      return;
    }

    final schedule = _settings?.workingSchedule;
    if (schedule != null) {
      final hoursMessage = AppointmentBranchWorkingHours.validationMessage(
        schedule: schedule,
        startTime: startTime,
        durationMinutes: duration,
      );
      if (hoursMessage != null) {
        setState(() => _summaryError = hoursMessage);
        return;
      }
      final endTime = startTime.add(Duration(minutes: duration));
      if (!AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: startTime, end: endTime)) {
        setState(() => _summaryError = 'Appointment must be within branch working hours.');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _summaryError = null;
      _conflictMessage = null;
    });

    try {
      await ref.read(appointmentRepositoryProvider).createAppointment(
        branchId: branchId,
        patientId: patient.id,
        doctorId: _selectedDoctorId,
        type: AppointmentType.planned,
        startTime: startTime,
        durationMinutes: duration,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(appointmentQueueProvider);
      ref.invalidate(appointmentCalendarProvider);
      ref.showAppToast(message: 'Appointment booked.', variant: AppToastVariant.success);
      context.nav.popOrHome();
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      final message = appointmentMessageForRpc(error);
      setState(() {
        _isSaving = false;
        if (error.code == 'SCHEDULE_CONFLICT' || error.code == 'PATIENT_ALREADY_BOOKED_SAME_DAY') {
          _conflictMessage = message;
        } else {
          _summaryError = message;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _summaryError = UserErrorMapper.mapToUserMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentBooking(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Book appointment',
        description: 'You do not have permission to book appointments.',
      );
    }

    if (_loadingSettings) {
      return const Center(child: AppSpinner());
    }

    if (_settingsError != null) {
      return AppErrorState(message: _settingsError!, onRetry: _loadSettings);
    }

    final doctors = ref.watch(appointmentCalendarDoctorsProvider).maybeWhen(
      data: (items) => items,
      orElse: () => const <StaffListItem>[],
    );

    return EditorFormPattern(
      presentation: widget.presentation,
      title: 'Book appointment',
      description: 'Schedule a planned appointment at your active branch.',
      summaryAlert: _conflictMessage == null
          ? null
          : AppAlert(variant: AppAlertVariant.danger, title: _conflictMessage!),
      staleEditAlert: _summaryError == null && !_submitted
          ? null
          : _summaryError == null
          ? null
          : AppAlert(variant: AppAlertVariant.danger, title: _summaryError!),
      sections: [
        EditorFormSection(
          title: 'Patient',
          description: 'Search for an existing patient to book.',
          fields: [
            AppFormField(
              label: 'Patient',
              requiredMark: true,
              error: _submitted && _selectedPatient == null ? 'Select a patient.' : _patientSearchError,
              child: AppAutocomplete<PatientListItem>(
                controller: _patientSearchController,
                placeholder: 'Search by name or phone',
                onSearch: _searchPatients,
                value: _selectedPatient == null
                    ? null
                    : AppAutocompleteOption(
                        value: _selectedPatient!,
                        label: _selectedPatient!.fullName,
                      ),
                onSelected: (option) => setState(() {
                  _selectedPatient = option?.value;
                  _summaryError = null;
                }),
              ),
            ),
          ],
        ),
        EditorFormSection(
          title: 'Schedule',
          description: 'Choose when the appointment takes place.',
          twoColumn: true,
          fields: [
            AppFormField(
              label: 'Date',
              requiredMark: true,
              child: AppDatePicker(
                key: const Key('appointment_booking_pick_date'),
                value: _startTime == null ? null : DateTime(_startTime!.year, _startTime!.month, _startTime!.day),
                min: DateTime(clock.now().year, clock.now().month, clock.now().day),
                onChanged: (date) {
                  if (date == null || _startTime == null) {
                    return;
                  }
                  setState(() {
                    _startTime = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      _startTime!.hour,
                      _startTime!.minute,
                    );
                    final duration = int.tryParse(_durationController.text.trim()) ?? _settings!.defaultDurationMinutes;
                    _endTime = _startTime!.add(Duration(minutes: duration));
                  });
                },
              ),
            ),
            AppFormField(
              label: 'Start time',
              requiredMark: true,
              child: AppTimePicker(
                key: const Key('appointment_booking_pick_start'),
                value: _startTime == null ? null : AppointmentPresentationFormatting.formatTime(_startTime!),
                onChanged: (time) {
                  if (_startTime == null) {
                    return;
                  }
                  final parts = time.split(':');
                  setState(() {
                    _startTime = DateTime(
                      _startTime!.year,
                      _startTime!.month,
                      _startTime!.day,
                      int.parse(parts[0]),
                      int.parse(parts[1]),
                    );
                  });
                },
              ),
            ),
            AppFormField(
              label: 'Duration (minutes)',
              requiredMark: true,
              child: AppTextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                hintText: '${_settings?.defaultDurationMinutes ?? 30}',
              ),
            ),
            AppFormField(
              label: 'Doctor (optional)',
              child: AppSelect<String?>(
                options: [
                  const AppSelectOption<String?>(value: null, label: 'Unassigned'),
                  for (final doctor in doctors)
                    AppSelectOption(value: doctor.id, label: doctor.fullName),
                ],
                value: _selectedDoctorId,
                onChanged: (doctorId) => setState(() => _selectedDoctorId = doctorId),
              ),
            ),
          ],
        ),
        EditorFormSection(
          title: 'Notes',
          fields: [
            AppFormField(
              label: 'Internal notes',
              child: AppTextField(
                controller: _notesController,
                hintText: 'Optional notes for staff',
                maxLines: 3,
              ),
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
          const SizedBox(width: AppSpacing.s2),
          AppButton(
            key: const Key('appointment_booking_submit'),
            label: 'Book appointment',
            loading: _isSaving,
            onPressed: _isSaving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
