import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PaginationCopy {
  const _PaginationCopy({
    required this.description,
    required this.rows,
    required this.ofLabel,
  });

  final String description;
  final String rows;
  final String ofLabel;
}

const _copyEn = _PaginationCopy(
  description: 'Page controls with tabular range summary and page-size select.',
  rows: 'Rows',
  ofLabel: 'of',
);

const _copyAr = _PaginationCopy(
  description: 'عناصر التحكم بالصفحات مع ملخص النطاق الجدولي ومحدد حجم الصفحة.',
  rows: 'صفوف',
  ofLabel: 'من',
);

_PaginationCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Pagination component showcase (web `PaginationShowcase`).
class PaginationShowcaseSection extends ConsumerStatefulWidget {
  const PaginationShowcaseSection({super.key});

  @override
  ConsumerState<PaginationShowcaseSection> createState() => _PaginationShowcaseSectionState();
}

class _PaginationShowcaseSectionState extends ConsumerState<PaginationShowcaseSection> {
  var _page = 1;
  var _pageSize = 50;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'pagination',
      title: 'Pagination',
      description: copy.description,
      componentName: 'Pagination',
      child: ShowcaseDemo(
        label: 'Default',
        propsHint: 'page + pageSize + total',
        child: SizedBox(
          width: double.infinity,
          child: AppPagination(
            page: _page,
            pageSize: _pageSize,
            total: 2000,
            pageSizeOptions: const [25, 50, 100],
            rowsLabel: copy.rows,
            ofLabel: copy.ofLabel,
            onPageChange: (page) => setState(() => _page = page),
            onPageSizeChange: (size) => setState(() => _pageSize = size),
          ),
        ),
      ),
    );
  }
}
