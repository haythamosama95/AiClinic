import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';

/// User selection from a catalog autocomplete field.
@immutable
class CatalogFieldSelection {
  const CatalogFieldSelection({required this.name, this.catalogId});

  final String name;
  final String? catalogId;

  bool get isCustom => catalogId == null;
}

/// Debounced catalog search via [AppAutocomplete].
class EncounterCatalogField extends ConsumerStatefulWidget {
  const EncounterCatalogField({
    required this.label,
    required this.onSearch,
    required this.onSelectionChanged,
    this.initialName,
    this.initialCatalogId,
    this.enabled = true,
    this.allowCreate = true,
    super.key,
  });

  final String label;
  final Future<List<CatalogItem>> Function(String query) onSearch;
  final ValueChanged<CatalogFieldSelection> onSelectionChanged;
  final String? initialName;
  final String? initialCatalogId;
  final bool enabled;
  final bool allowCreate;

  @override
  ConsumerState<EncounterCatalogField> createState() => _EncounterCatalogFieldState();
}

class _EncounterCatalogFieldState extends ConsumerState<EncounterCatalogField> {
  CatalogFieldSelection? _value;

  @override
  void initState() {
    super.initState();
    final name = widget.initialName?.trim();
    if (name != null && name.isNotEmpty) {
      _value = CatalogFieldSelection(name: name, catalogId: widget.initialCatalogId);
    }
  }

  Future<List<AppAutocompleteOption<String>>> _search(String query) async {
    final items = await widget.onSearch(query);
    return [
      for (final item in items)
        AppAutocompleteOption<String>(
          value: item.id,
          label: item.name,
          meta: item.defaultUnit,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selected = _value == null
        ? null
        : AppAutocompleteOption<String>(
            value: _value!.catalogId ?? _value!.name,
            label: _value!.name,
          );

    return AppFormField(
      label: widget.label,
      child: AppAutocomplete<String>(
        disabled: !widget.enabled,
        placeholder: 'Search…',
        allowCreate: widget.allowCreate,
        createLabel: (query) => 'Use "$query"',
        onCreate: (query) {
          final selection = CatalogFieldSelection(name: query.trim());
          setState(() => _value = selection);
          widget.onSelectionChanged(selection);
        },
        value: selected,
        onSearch: _search,
        onSelected: (option) {
          if (option == null) {
            setState(() => _value = null);
            widget.onSelectionChanged(const CatalogFieldSelection(name: ''));
            return;
          }
          final selection = CatalogFieldSelection(
            name: option.label,
            catalogId: option.value == option.label ? null : option.value,
          );
          setState(() => _value = selection);
          widget.onSelectionChanged(selection);
        },
        onChanged: (option) {
          if (option == null) {
            setState(() => _value = null);
            widget.onSelectionChanged(const CatalogFieldSelection(name: ''));
          }
        },
      ),
    );
  }
}

/// Medication catalog search bound to [VisitRepository.searchMedications].
Future<List<CatalogItem>> searchMedicationCatalog(
  WidgetRef ref,
  String query,
) {
  return ref.read(visitRepositoryProvider).searchMedications(query: query);
}

/// Investigation catalog search bound to [VisitRepository.searchInvestigations].
Future<List<CatalogItem>> searchInvestigationCatalog(
  WidgetRef ref,
  String query,
) {
  return ref.read(visitRepositoryProvider).searchInvestigations(query: query);
}
