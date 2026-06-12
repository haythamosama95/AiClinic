import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/buttons/app_button.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_text_field.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_query.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/staff_list_filter_popover.dart';

/// Search field and filter action for the staff settings list.
class StaffListToolbar extends StatelessWidget {
  const StaffListToolbar({
    required this.searchController,
    required this.query,
    required this.onSearchChanged,
    required this.onQueryChanged,
    this.onNewStaff,
    super.key,
  });

  final TextEditingController searchController;
  final StaffListQuery query;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<StaffListQuery> onQueryChanged;
  final VoidCallback? onNewStaff;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextInput(
            controller: searchController,
            hintText: 'Search by name, username, or mobile number',
            size: AppFieldSize.sm,
            prefixIcon: const Icon(Icons.search, size: 18),
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        StaffListFilterButton(query: query, onQueryChanged: onQueryChanged),
        if (onNewStaff != null) ...[
          const SizedBox(width: SpacingTokens.sm),
          AppButton(
            label: 'New staff',
            expand: false,
            size: AppFieldSize.sm,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            onPressed: onNewStaff,
          ),
        ],
      ],
    );
  }
}
