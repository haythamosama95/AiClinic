import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _ChipCopy {
  const _ChipCopy({
    required this.description,
    required this.defaultLabel,
    required this.defaultHint,
    required this.removableLabel,
    required this.removableHint,
    required this.selectableLabel,
    required this.selectableHint,
    required this.disabledLabel,
    required this.disabledHint,
    required this.insurance,
    required this.walkIn,
    required this.branchA,
    required this.active,
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.inactiveService,
    required this.locked,
  });

  final String description;
  final String defaultLabel;
  final String defaultHint;
  final String removableLabel;
  final String removableHint;
  final String selectableLabel;
  final String selectableHint;
  final String disabledLabel;
  final String disabledHint;
  final String insurance;
  final String walkIn;
  final String branchA;
  final String active;
  final String today;
  final String thisWeek;
  final String thisMonth;
  final String inactiveService;
  final String locked;

  String filterLabel(String key) {
    return switch (key) {
      'Today' => today,
      'This week' => thisWeek,
      'This month' => thisMonth,
      _ => key,
    };
  }

  String removableLabelFor(String key) {
    return switch (key) {
      'Branch A' => branchA,
      'Active' => active,
      _ => key,
    };
  }
}

const _copyEn = _ChipCopy(
  description: 'Compact descriptors for filters and multi-select values.',
  defaultLabel: 'Default',
  defaultHint: 'neutral descriptor',
  removableLabel: 'Removable',
  removableHint: 'removable onRemove',
  selectableLabel: 'Selectable filters',
  selectableHint: 'selectable selected onSelect',
  disabledLabel: 'Disabled',
  disabledHint: 'disabled',
  insurance: 'Insurance',
  walkIn: 'Walk-in',
  branchA: 'Branch A',
  active: 'Active',
  today: 'Today',
  thisWeek: 'This week',
  thisMonth: 'This month',
  inactiveService: 'Inactive service',
  locked: 'Locked',
);

const _copyAr = _ChipCopy(
  description: 'واصفات مدمجة للفلاتر وقيم الاختيار المتعدد.',
  defaultLabel: 'افتراضي',
  defaultHint: 'واصف محايد',
  removableLabel: 'قابل للإزالة',
  removableHint: 'removable onRemove',
  selectableLabel: 'فلاتر قابلة للتحديد',
  selectableHint: 'selectable selected onSelect',
  disabledLabel: 'معطّل',
  disabledHint: 'disabled',
  insurance: 'تأمين',
  walkIn: 'بدون موعد',
  branchA: 'الفرع أ',
  active: 'نشط',
  today: 'اليوم',
  thisWeek: 'هذا الأسبوع',
  thisMonth: 'هذا الشهر',
  inactiveService: 'خدمة غير نشطة',
  locked: 'مقفل',
);

const _filterKeys = ['Today', 'This week', 'This month'];
const _removableKeys = ['Branch A', 'Active'];

_ChipCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Chip showcase (web `ChipShowcase`).
class ChipShowcaseSection extends ConsumerStatefulWidget {
  const ChipShowcaseSection({super.key});

  @override
  ConsumerState<ChipShowcaseSection> createState() => _ChipShowcaseSectionState();
}

class _ChipShowcaseSectionState extends ConsumerState<ChipShowcaseSection> {
  final _selected = <String>{'Today'};
  final _filters = List<String>.from(_removableKeys);

  void _toggleFilter(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  void _removeFilter(String key) {
    setState(() => _filters.remove(key));
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'chip',
      title: 'Chip / Tag',
      description: copy.description,
      componentName: 'Chip',
      child: ShowcaseDemoGrid(
        children: [
          ShowcaseDemo(
            label: copy.defaultLabel,
            propsHint: copy.defaultHint,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChip(child: Text(copy.insurance)),
                AppChip(child: Text(copy.walkIn)),
              ],
            ),
          ),
          ShowcaseDemo(
            label: copy.removableLabel,
            propsHint: copy.removableHint,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in _filters)
                  AppChip(
                    key: ValueKey(key),
                    removable: true,
                    onRemove: () => _removeFilter(key),
                    child: Text(copy.removableLabelFor(key)),
                  ),
              ],
            ),
          ),
          ShowcaseDemo(
            label: copy.selectableLabel,
            propsHint: copy.selectableHint,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in _filterKeys)
                  AppChip(
                    selectable: true,
                    selected: _selected.contains(key),
                    onSelect: () => _toggleFilter(key),
                    child: Text(copy.filterLabel(key)),
                  ),
              ],
            ),
          ),
          ShowcaseDemo(
            label: copy.disabledLabel,
            propsHint: copy.disabledHint,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppChip(disabled: true, child: Text(copy.inactiveService)),
                AppChip(
                  selectable: true,
                  selected: true,
                  disabled: true,
                  child: Text(copy.locked),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
