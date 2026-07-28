import 'package:ai_clinic/core/money/money.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_avatar.dart';
import 'package:ai_clinic/core/ui/components/app_list.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/features/design_system/presentation/components/showcase_primitives.dart';
import 'package:ai_clinic/features/design_system/presentation/providers/dev_preview_provider.dart';

class _PatientRow {
  const _PatientRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
  });

  final String id;
  final String name;
  final String phone;
  final double balance;
}

const _mockPatients = <_PatientRow>[
  _PatientRow(id: '1', name: 'Layla Hassan', phone: '+20 100 234 5678', balance: 1250),
  _PatientRow(id: '2', name: 'Omar Farouk', phone: '+20 101 345 6789', balance: 0),
  _PatientRow(id: '3', name: 'Nadia El-Sayed', phone: '+20 102 456 7890', balance: -320),
];

class _ListCopy {
  const _ListCopy({
    required this.sectionDescription,
    required this.recentPatients,
  });

  final String sectionDescription;
  final String recentPatients;
}

const _copyEn = _ListCopy(
  sectionDescription: 'Vertical list of rows with leading, primary, secondary, and trailing slots.',
  recentPatients: 'Recent patients',
);

const _copyAr = _ListCopy(
  sectionDescription: 'قائمة عمودية من الصفوف مع خانات البداية والنص الأساسي والثانوي والنهاية.',
  recentPatients: 'المرضى الأخيرون',
);

_ListCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// List showcase (web `ListShowcase`).
class ListShowcaseSection extends ConsumerWidget {
  const ListShowcaseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copy = _copyFor(ref.watch(devPreviewProvider).locale);

    return ShowcaseSection(
      id: 'list',
      title: 'List',
      description: copy.sectionDescription,
      componentName: 'List / ListItem',
      child: AppList(
        ariaLabel: copy.recentPatients,
        children: [
          for (final patient in _mockPatients)
            AppListItem(
              key: ValueKey(patient.id),
              leading: AppAvatar(name: patient.name, size: AvatarSize.sm),
              primary: Text(patient.name),
              secondary: Text(patient.phone),
              trailing: AppMoneyDisplay(amount: Money.parse(patient.balance.toStringAsFixed(2)), currency: 'EGP'),
            ),
        ],
      ),
    );
  }
}
