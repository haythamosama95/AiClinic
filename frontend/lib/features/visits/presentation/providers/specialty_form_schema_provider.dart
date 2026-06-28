import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/specialty_form_schema.dart';

/// Org-wide specialty form schema for documentation and visit detail (V1-5 US3).
final specialtyFormSchemaProvider = FutureProvider<SpecialtyFormSchema>((ref) async {
  final schemaJson = await ref.read(visitRepositoryProvider).getSpecialtyFormSchema();
  return SpecialtyFormSchema.parse(schemaJson);
});
