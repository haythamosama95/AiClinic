import 'package:flutter/material.dart';

import 'package:ai_clinic/features/visits/domain/specialty_form_schema.dart';

/// Read-only specialty field values on visit detail (V1-5 US3).
class SpecialtyFormReadOnlySection extends StatelessWidget {
  const SpecialtyFormReadOnlySection({required this.values, required this.schema, super.key});

  final Map<String, dynamic> values;
  final SpecialtyFormSchema schema;

  @override
  Widget build(BuildContext context) {
    final rows = schema.readOnlyRows(values);
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Column(
      key: const Key('visit_detail_specialty_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Specialty fields', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(row.value, key: Key('visit_detail_specialty_${row.label}')),
              ],
            ),
          ),
      ],
    );
  }
}
