import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _SearchInputCopy {
  const _SearchInputCopy({
    required this.searchPatients,
    required this.filterServices,
    required this.disabled,
    required this.description,
  });

  final String searchPatients;
  final String filterServices;
  final String disabled;
  final String description;
}

const _copyEn = _SearchInputCopy(
  searchPatients: 'Search patients',
  filterServices: 'Filter services',
  disabled: 'Disabled',
  description: 'Debounced search, loading spinner, result count, Esc to clear.',
);

const _copyAr = _SearchInputCopy(
  searchPatients: 'البحث عن المرضى',
  filterServices: 'تصفية الخدمات',
  disabled: 'معطّل',
  description: 'بحث مؤجل، مؤشر تحميل، عدد النتائج، Esc للمسح.',
);

_SearchInputCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Search input showcase (web `SearchInputShowcase`).
class SearchInputShowcaseSection extends ConsumerStatefulWidget {
  const SearchInputShowcaseSection({super.key});

  @override
  ConsumerState<SearchInputShowcaseSection> createState() => _SearchInputShowcaseSectionState();
}

class _SearchInputShowcaseSectionState extends ConsumerState<SearchInputShowcaseSection> {
  var _loading = false;
  int? _count;

  void _simulateSearch(String query) {
    setState(() => _loading = true);
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _count = query.isEmpty ? null : Random().nextInt(20) + 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'search-input',
      title: 'Search input',
      componentName: 'SearchInput',
      description: copy.description,
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: 'Interactive',
            propsHint: 'debounceMs=300',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AppSearchInput(
                placeholder: copy.searchPatients,
                loading: _loading,
                resultCount: _count,
                onValueChange: _simulateSearch,
              ),
            ),
          ),
          ShowcaseDemo(
            label: 'States',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSearchInput(placeholder: copy.filterServices),
                  const SizedBox(height: 12),
                  AppSearchInput(disabled: true, placeholder: copy.disabled),
                  const SizedBox(height: 12),
                  const AppSearchInput(invalid: true, initialValue: '???'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
