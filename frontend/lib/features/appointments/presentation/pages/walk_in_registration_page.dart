import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/utils/user_error_mapper.dart';
import 'package:ai_clinic/core/widgets/app_form_field.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_settings.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/domain/create_appointment_result.dart';
import 'package:ai_clinic/features/appointments/presentation/appointment_rpc_messages.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/doctor_selector.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/duration_field.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_picker.dart';

/// Register walk-in appointments with backend auto-slot assignment (V1-4 US2).
class WalkInRegistrationPage extends ConsumerStatefulWidget {
  const WalkInRegistrationPage({super.key});

  @override
  ConsumerState<WalkInRegistrationPage> createState() => _WalkInRegistrationPageState();
}

class _WalkInRegistrationPageState extends ConsumerState<WalkInRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  AppointmentSettings? _settings;
  bool _loadingSettings = true;
  String? _settingsError;
  PatientListItem? _selectedPatient;
  String? _selectedDoctorId;
  bool _isSaving = false;
  String? _formError;
  CreateAppointmentResult? _assignedSlot;

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
        _settingsError = 'Select an active branch in the shell before registering walk-ins.';
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final branchId = ref.read(authSessionProvider).context?.activeBranchId;
    if (branchId == null || branchId.isEmpty) {
      setState(() => _formError = 'Select an active branch in the shell before registering walk-ins.');
      return;
    }

    if (_selectedPatient == null) {
      setState(() => _formError = 'Select a patient.');
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
      _assignedSlot = null;
    });

    try {
      final assigned = await ref
          .read(appointmentRepositoryProvider)
          .createAppointment(
            branchId: branchId,
            patientId: _selectedPatient!.id,
            doctorId: doctorId,
            type: AppointmentType.walkIn,
            durationMinutes: duration,
            notes: _trimOrNull(_notesController.text),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _assignedSlot = assigned;
      });
    } on RpcFailure catch (error) {
      if (!mounted) {
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

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
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
          title: const Text('Register walk-in'),
          leading: IconButton(
            tooltip: 'Go back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.nav.popOrHome(),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You do not have permission to register walk-ins.', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    if (_loadingSettings) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Register walk-in'),
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
        title: const Text('Register walk-in'),
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
                const Text('Select an active branch in the shell before registering walk-ins.'),
              ] else if (settings != null) ...[
                if (_formError != null) ...[
                  Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 16),
                ],
                if (_assignedSlot != null) ...[
                  Container(
                    key: const Key('walk_in_assigned_slot_card'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).colorScheme.primary),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assigned slot', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text('Start: ${_formatDateTime(_assignedSlot!.startTime)}'),
                        Text('End: ${_formatDateTime(_assignedSlot!.endTime)}'),
                        const SizedBox(height: 4),
                        const Text('Status: Checked in'),
                      ],
                    ),
                  ),
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
                DurationField(
                  controller: _durationController,
                  startTime: null,
                  minMinutes: settings.minDurationMinutes,
                  maxMinutes: settings.maxDurationMinutes,
                  enabled: !_isSaving,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                AppFormField(label: 'Notes (optional)', controller: _notesController, enabled: !_isSaving),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('walk_in_registration_submit'),
                  onPressed: _isSaving ? null : _submit,
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Register walk-in'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
