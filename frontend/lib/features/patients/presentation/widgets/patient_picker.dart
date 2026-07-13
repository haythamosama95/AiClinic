import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_combobox.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';

/// Searchable patient selector using [AppCombobox] with async RPC search.
class PatientPicker extends ConsumerStatefulWidget {
  const PatientPicker({
    required this.branchId,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.scope = PatientListScope.thisBranch,
    this.hint,
    this.searchFieldKey,
    this.clearButtonKey,
    super.key,
  });

  final String branchId;
  final PatientListItem? value;
  final ValueChanged<PatientListItem?> onChanged;
  final bool enabled;
  final PatientListScope scope;
  final String? hint;
  final Key? searchFieldKey;
  final Key? clearButtonKey;

  @override
  ConsumerState<PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<PatientPicker> {
  var _draftQuery = '';
  String? _searchError;
  final _patientsById = <String, PatientListItem>{};

  String? get _validationHint => PatientSearchQuery.validationHint(_draftQuery.isEmpty ? null : _draftQuery);

  @override
  void didUpdateWidget(covariant PatientPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final patient = widget.value;
    if (patient != null) {
      _patientsById[patient.id] = patient;
    }
  }

  Future<List<AppComboboxItem>> _searchPatients(String query) async {
    final normalized = query.trim();
    if (mounted) {
      setState(() {
        _draftQuery = normalized;
        _searchError = null;
      });
    }

    if (!PatientSearchQuery.canInvokeRpc(normalized.isEmpty ? null : normalized)) {
      return [];
    }

    try {
      final page = await ref.read(searchPatientsUseCaseProvider)(
        query: normalized.isEmpty ? null : normalized,
        scope: widget.scope,
        branchId: widget.branchId,
        limit: 10,
      );
      for (final patient in page.items) {
        _patientsById[patient.id] = patient;
      }
      return page.items.map(_toComboboxItem).toList();
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = 'Could not search patients.');
      }
      return [];
    }
  }

  void _handleValueChange(AppComboboxItem? item) {
    if (item == null) {
      return;
    }

    final patient = _patientsById[item.id];
    if (patient != null) {
      widget.onChanged(patient);
      return;
    }

    final current = widget.value;
    if (current != null && current.id == item.id) {
      widget.onChanged(current);
    }
  }

  void _clearSelection() {
    setState(() {
      _draftQuery = '';
      _searchError = null;
    });
    widget.onChanged(null);
  }

  AppComboboxItem _toComboboxItem(PatientListItem patient) {
    return AppComboboxItem(
      id: patient.id,
      label: patient.fullName,
      meta: _patientSubtitle(patient),
      initials: _initials(patient.fullName),
    );
  }

  String _patientSubtitle(PatientListItem patient) {
    final parts = <String>[];
    if (patient.phone != null && patient.phone!.trim().isNotEmpty) {
      parts.add(patient.phone!.trim());
    }
    if (patient.dateOfBirth != null) {
      parts.add(PatientPresentationFormatting.dateOfBirthLabel(patient.dateOfBirth));
    }
    if (widget.scope == PatientListScope.allBranches) {
      parts.add(patient.registeringBranchName);
    } else if (parts.isEmpty) {
      parts.add(patient.registeringBranchName);
    }
    return parts.join(' · ');
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts[1].substring(0, 1)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.value;

    if (selected != null) {
      return _SelectedPatientCard(
        patient: selected,
        hint: widget.hint,
        clearButtonKey: widget.clearButtonKey,
        onClear: widget.enabled ? _clearSelection : null,
      );
    }

    final helperText = _searchError == null
        ? (_validationHint ?? PatientSearchQuery.helperForDraft(_draftQuery))
        : null;

    return AppFormField(
      id: 'patient_picker_search',
      label: 'Patient',
      hint: widget.hint ?? 'Search by name, MRN, email, or phone.',
      helperText: helperText,
      error: _searchError,
      child: AppCombobox(
        key: widget.searchFieldKey ?? const Key('patient_picker_search'),
        id: 'patient_picker_search',
        placeholder: 'Search patients by name, MRN, email, or phone…',
        disabled: !widget.enabled,
        onValueChange: _handleValueChange,
        onSearch: _searchPatients,
      ),
    );
  }
}

class _SelectedPatientCard extends StatelessWidget {
  const _SelectedPatientCard({required this.patient, this.hint, this.clearButtonKey, this.onClear});

  final PatientListItem patient;
  final String? hint;
  final Key? clearButtonKey;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppFormField(
      id: 'patient_picker_selected',
      label: 'Patient',
      hint: hint ?? 'Search by name, MRN, email, or phone.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderSubtle),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.surfaceMuted.withValues(alpha: 0.75), colors.surfaceDefault],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
          child: Row(
            children: [
              AppAvatar(name: patient.fullName, size: AvatarSize.md),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.space05),
                    Text(
                      _subtitle(patient),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              if (onClear != null) ...[
                const SizedBox(width: AppSpacing.space2),
                AppIconButton(
                  key: clearButtonKey ?? const Key('patient_picker_clear'),
                  variant: AppIconButtonVariant.ghost,
                  size: AppIconButtonSize.sm,
                  icon: const Icon(Icons.close, size: 16),
                  label: 'Clear patient',
                  onPressed: onClear,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(PatientListItem patient) {
    final parts = <String>[];
    if (patient.phone != null && patient.phone!.trim().isNotEmpty) {
      parts.add(patient.phone!.trim());
    }
    if (patient.dateOfBirth != null) {
      parts.add(PatientPresentationFormatting.dateOfBirthLabel(patient.dateOfBirth));
    }
    if (parts.isEmpty) {
      return patient.registeringBranchName;
    }
    return parts.join(' · ');
  }
}
