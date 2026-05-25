import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/features/patients/domain/patient_search_query.dart';

/// Debounced search field with min-length guidance for name vs phone (US2).
class PatientSearchField extends StatefulWidget {
  const PatientSearchField({super.key, required this.onSearch, this.enabled = true});

  final ValueChanged<String> onSearch;
  final bool enabled;

  @override
  State<PatientSearchField> createState() => _PatientSearchFieldState();
}

class _PatientSearchFieldState extends State<PatientSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) {
        return;
      }
      widget.onSearch(_controller.text.trim());
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onSearch('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final draft = _controller.text;
    final hint = PatientSearchQuery.validationHint(draft);
    final helper = hint ?? PatientSearchQuery.helperForDraft(draft);

    return TextField(
      key: const Key('patient_search_field'),
      controller: _controller,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: 'Search patients',
        hintText: 'Name or phone prefix',
        helperText: helper,
        helperMaxLines: 2,
        errorText: hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: draft.isEmpty
            ? null
            : IconButton(
                key: const Key('patient_search_clear'),
                tooltip: 'Clear search',
                onPressed: widget.enabled ? _clear : null,
                icon: const Icon(Icons.clear),
              ),
      ),
      onChanged: widget.enabled
          ? (_) {
              setState(() {});
              _scheduleSearch();
            }
          : null,
      onSubmitted: widget.enabled ? (_) => widget.onSearch(_controller.text.trim()) : null,
    );
  }
}
