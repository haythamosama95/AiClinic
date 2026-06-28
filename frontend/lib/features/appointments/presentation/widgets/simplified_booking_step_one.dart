import 'dart:async';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/simplified_booking_session.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_doctor_selector.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step one of simplified booking: patient, doctor, and optional notes (011).
class SimplifiedBookingStepOne extends ConsumerStatefulWidget {
  const SimplifiedBookingStepOne({
    required this.branchId,
    required this.doctors,
    required this.session,
    required this.onNext,
    this.enabled = true,
    super.key,
  });

  final String branchId;
  final List<StaffListItem> doctors;
  final SimplifiedBookingSession session;
  final ValueChanged<SimplifiedBookingSession> onNext;
  final bool enabled;

  @override
  ConsumerState<SimplifiedBookingStepOne> createState() => _SimplifiedBookingStepOneState();
}

class _SimplifiedBookingStepOneState extends ConsumerState<SimplifiedBookingStepOne> {
  final _patientSearchController = TextEditingController();
  final _notesController = TextEditingController();

  PatientListItem? _selectedPatient;
  String? _selectedDoctorId;
  List<PatientListItem> _patientResults = const [];
  bool _searchingPatients = false;
  String? _patientSearchError;
  String _lastPatientQuery = '';
  Timer? _patientSearchDebounce;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _selectedPatient = widget.session.patient;
    _selectedDoctorId = widget.session.preferredDoctorId;
    if (widget.session.notes?.trim().isNotEmpty == true) {
      _notesController.text = widget.session.notes!.trim();
    }
  }

  @override
  void dispose() {
    _patientSearchDebounce?.cancel();
    _patientSearchController.dispose();
    _notesController.dispose();
    super.dispose();
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

  String? _validateNotes() {
    if (_notesController.text.trim().length > 2000) {
      return 'Notes must be 2000 characters or fewer.';
    }
    return null;
  }

  void _submit() {
    if (_selectedPatient == null) {
      setState(() => _validationError = 'Select a patient.');
      return;
    }
    final notesError = _validateNotes();
    if (notesError != null) {
      setState(() => _validationError = notesError);
      return;
    }

    final notes = _trimOrNull(_notesController.text);
    final clearedDoctor = _selectedDoctorId == null;
    widget.onNext(
      widget.session.copyWith(
        patient: _selectedPatient,
        preferredDoctorId: _selectedDoctorId,
        clearPreferredDoctor: clearedDoctor,
        clearEffectiveDoctor: clearedDoctor,
        notes: notes,
      ),
    );
  }

  String? _trimOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final canNext = widget.enabled && _selectedPatient != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Book appointment', style: theme.textTheme.titleMedium),
        const SizedBox(height: SpacingTokens.md),
        AppTextField(
          key: const Key('simplified_booking_patient_search'),
          label: 'Patient',
          controller: _patientSearchController,
          enabled: widget.enabled && _selectedPatient == null,
          hintText: 'Search by name or phone',
          description: PatientSearchQuery.helperForDraft(_patientSearchController.text),
          onChanged: widget.enabled ? _onPatientSearchChanged : null,
        ),
        if (_searchingPatients) ...[const SizedBox(height: SpacingTokens.sm), const AppLinearProgress()],
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
                if (widget.enabled)
                  AppButton(
                    key: const Key('simplified_booking_patient_clear'),
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
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    key: Key('simplified_booking_patient_result_$index'),
                    title: Text(patient.fullName),
                    subtitle: Text(patient.phone ?? patient.registeringBranchName),
                    onTap: widget.enabled
                        ? () {
                            setState(() {
                              _selectedPatient = patient;
                              _patientResults = const [];
                              _patientSearchController.clear();
                              _lastPatientQuery = '';
                              _validationError = null;
                            });
                          }
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: SpacingTokens.md),
        if (widget.doctors.isNotEmpty)
          AppointmentDoctorSelector(
            key: const Key('simplified_booking_doctor_selector'),
            branchId: widget.branchId,
            doctors: widget.doctors,
            value: _selectedDoctorId,
            enabled: widget.enabled,
            onChanged: (doctorId) => setState(() {
              _selectedDoctorId = doctorId;
              _validationError = null;
            }),
          )
        else
          Text(
            'No active doctors are configured. You can still book without assigning one.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
          ),
        const SizedBox(height: SpacingTokens.md),
        AppTextField(label: 'Notes (optional)', controller: _notesController, enabled: widget.enabled, maxLines: 3),
        if (_validationError != null) ...[
          const SizedBox(height: SpacingTokens.md),
          Text(_validationError!, style: theme.textTheme.bodyMedium?.copyWith(color: colors.destructive)),
        ],
        const SizedBox(height: SpacingTokens.lg),
        AppButton(
          key: const Key('simplified_booking_step_one_next'),
          label: 'Next',
          expand: true,
          onPressed: canNext ? _submit : null,
        ),
      ],
    );
  }
}
