import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_diagnosis_code.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/catalog_autocomplete_field.dart';

/// Thin wrapper over [CatalogAutocompleteField] for org diagnosis catalog search (014 US7).
class DiagnosisAutocompleteField extends CatalogAutocompleteField {
  DiagnosisAutocompleteField({
    required Future<List<DiagnosisCatalogItem>> Function(String query) onSearchDiagnosisCodes,
    required super.onSelectionChanged,
    super.label = 'Diagnosis',
    super.initialName,
    super.initialCatalogId,
    super.hintText,
    super.enabled = true,
    super.validator,
    super.searchDebounce,
    super.key,
  }) : super(
         onSearch: (query) async {
           final items = await onSearchDiagnosisCodes(query);
           return [for (final item in items) CatalogItem(id: item.id, name: item.displayLabel)];
         },
       );
}
