import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';
import 'package:ai_clinic/features/patients/domain/usecases/patient_use_case_providers.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_search_field.dart';

/// Search-and-select patient field for appointment booking forms (V1-4).
class PatientPicker extends ConsumerStatefulWidget {
  const PatientPicker({
    required this.branchId,
    required this.selectedPatient,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String branchId;
  final PatientListItem? selectedPatient;
  final ValueChanged<PatientListItem?> onSelected;
  final bool enabled;

  @override
  ConsumerState<PatientPicker> createState() => _PatientPickerState();
}

class _PatientPickerState extends ConsumerState<PatientPicker> {
  List<PatientListItem> _results = const [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectedPatient;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PatientSearchField(enabled: widget.enabled, onSearch: _onSearch),
        if (selected != null) ...[
          const SizedBox(height: 8),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Selected patient'),
            child: Row(
              children: [
                Expanded(child: Text('${selected.fullName}${selected.phone != null ? ' · ${selected.phone}' : ''}')),
                if (widget.enabled)
                  TextButton(
                    key: const Key('patient_picker_clear'),
                    onPressed: () => widget.onSelected(null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ],
        if (_loading) ...[const SizedBox(height: 8), const LinearProgressIndicator()],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_results.isNotEmpty && selected == null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final patient = _results[index];
                return ListTile(
                  key: Key('patient_picker_result_$index'),
                  title: Text(patient.fullName),
                  subtitle: Text(patient.phone ?? patient.registeringBranchName),
                  onTap: widget.enabled
                      ? () {
                          widget.onSelected(patient);
                          setState(() {
                            _results = const [];
                            _lastQuery = '';
                          });
                        }
                      : null,
                );
              },
            ),
          ),
        ] else if (!PatientSearchQuery.canInvokeRpc(_lastQuery.isEmpty ? null : _lastQuery) &&
            _lastQuery.isNotEmpty &&
            selected == null &&
            !_loading) ...[
          const SizedBox(height: 8),
          Text(
            PatientSearchQuery.validationHint(_lastQuery) ?? 'Keep typing to search patients.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _onSearch(String query) async {
    _lastQuery = query;
    if (!PatientSearchQuery.canInvokeRpc(query.isEmpty ? null : query)) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await ref.read(searchPatientsUseCaseProvider)(
        query: query.isEmpty ? null : query,
        scope: PatientListScope.thisBranch,
        branchId: widget.branchId,
        limit: 10,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _results = page.items;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _results = const [];
        _error = 'Could not search patients.';
      });
    }
  }
}
