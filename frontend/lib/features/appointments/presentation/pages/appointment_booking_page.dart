import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_working_hours.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_branch_providers.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/conflict_error_banner.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/doctor_selector.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/duration_field.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_picker.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Book a planned appointment at the active branch (V1-4 US1).
class AppointmentBookingPage extends ConsumerStatefulWidget {
  const AppointmentBookingPage({super.key});

  @override
  ConsumerState<AppointmentBookingPage> createState() => _AppointmentBookingPageState();
}

class _AppointmentBookingPageState extends ConsumerState<AppointmentBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentSettings? _settings;
  bool _loadingSettings = true;
  String? _settingsError;
  DateTime? _startTime;
  PatientListItem? _selectedPatient;
  String? _selectedDoctorId;
  bool _isSaving = false;
  String? _formError;
  String? _conflictMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
  }

  @override
  void dispose() {
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() {
        _loadingSettings = false;
        _settingsError = 'Select an active branch in the shell before booking.';
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
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) {
      return;
    }

    setState(() {
      _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _conflictMessage = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() => _formError = 'Select an active branch in the shell before booking.');
      return;
    }

    if (_selectedPatient == null) {
      setState(() => _formError = 'Select a patient.');
      return;
    }

    if (_startTime == null) {
      setState(() => _formError = 'Select a start date and time.');
      return;
    }

    final doctorId = _trimOrNull(_selectedDoctorId ?? '');

    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null) {
      setState(() => _formError = 'Enter a valid duration in minutes.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
      _conflictMessage = null;
    });

    try {
      final schedule = await loadBranchWorkingSchedule(ref, branchId: branchId);
      final endTime = _startTime!.add(Duration(minutes: duration));
      if (schedule != null &&
          !AppointmentWorkingHours.isWithinSchedule(schedule: schedule, start: _startTime!, end: endTime)) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isSaving = false;
          _formError = 'Appointment must be within branch working hours.';
        });
        return;
      }

      await ref
          .read(appointmentRepositoryProvider)
          .createAppointment(
            branchId: branchId,
            patientId: _selectedPatient!.id,
            doctorId: doctorId,
            type: AppointmentType.planned,
            startTime: _startTime,
            durationMinutes: duration,
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

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appointment booked successfully.')));
    context.nav.popOrHome();
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _startTimeLabel() {
    final start = _startTime;
    if (start == null) {
      return 'Not selected';
    }
    final local = start.toLocal();
    return '${MaterialLocalizations.of(context).formatMediumDate(local)} '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(permissionServiceProvider);
    final canCreate = permissions.canCreateAppointments();
    final branchId = ref.watch(authSessionProvider).context?.activeBranchId;

    if (!canCreate) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Book appointment'),
          leading: IconButton(
            tooltip: 'Go back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.nav.popOrHome(),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to book appointments.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_loadingSettings) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Book appointment'),
          leading: IconButton(
            tooltip: 'Go back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.nav.popOrHome(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book appointment'),
        leading: IconButton(
          tooltip: 'Go back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _isSaving ? null : () => context.nav.popOrHome(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_settingsError != null) ...[
                Text(_settingsError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _loadSettings, child: const Text('Retry loading settings')),
              ] else if (branchId == null || branchId.isEmpty) ...[
                const Text('Select an active branch in the shell before booking.'),
              ] else if (settings != null) ...[
                if (_conflictMessage != null) ...[
                  ConflictErrorBanner(message: _conflictMessage!),
                  const SizedBox(height: 16),
                ],
                if (_formError != null) ...[
                  Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 16),
                ],
                PatientPicker(
                  branchId: branchId,
                  selectedPatient: _selectedPatient,
                  enabled: !_isSaving,
                  onSelected: (patient) => setState(() {
                    _selectedPatient = patient;
                    _formError = null;
                  }),
                ),
                const SizedBox(height: 16),
                DoctorSelector(
                  selectedDoctorId: _selectedDoctorId,
                  enabled: !_isSaving,
                  onChanged: (id) => setState(() => _selectedDoctorId = id),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Start date and time'),
                        child: Text(_startTimeLabel()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      key: const Key('appointment_booking_pick_start'),
                      onPressed: _isSaving ? null : _pickStartTime,
                      child: const Text('Pick'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DurationField(
                  controller: _durationController,
                  startTime: _startTime,
                  minMinutes: settings.minDurationMinutes,
                  maxMinutes: settings.maxDurationMinutes,
                  enabled: !_isSaving,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                AppFormField(label: 'Notes (optional)', controller: _notesController, enabled: !_isSaving),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('appointment_booking_submit'),
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Book appointment'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
