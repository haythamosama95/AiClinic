import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/showcase/showcase_primitives.dart';
import 'package:ai_clinic/core/ui/ui.dart';

class PaginationShowcase extends StatefulWidget {
  const PaginationShowcase({super.key});

  @override
  State<PaginationShowcase> createState() => _PaginationShowcaseState();
}

class _PaginationShowcaseState extends State<PaginationShowcase> {
  int _page = 1;
  int _pageSize = 50;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection(
      title: 'Pagination',
      description: 'Page controls with tabular range summary and page-size select.',
      child: ShowcaseDemo(
        label: 'Default',
        child: AppPagination(
          page: _page,
          pageSize: _pageSize,
          total: 2000,
          onPageChange: (page) => setState(() => _page = page),
          onPageSizeChange: (size) => setState(() {
            _pageSize = size;
            _page = 1;
          }),
        ),
      ),
    );
  }
}
