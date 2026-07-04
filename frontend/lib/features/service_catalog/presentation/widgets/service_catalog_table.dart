import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/presentation/utils/billing_formatting.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/utils/service_price_preview.dart';

/// Builds [AppTable] columns for the service catalog list.
List<AppTableColumn<ServiceListItem>> buildServiceCatalogTableColumns(BuildContext context) {
  final typography = context.typography;
  final colors = context.colors;

  return [
    AppTableColumn(
      id: 'name',
      header: 'Service',
      sticky: true,
      cellBuilder: (context, item) => Text(
        item.name,
        style: typography.bodyStrong.copyWith(color: colors.textPrimary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    AppTableColumn(
      id: 'default_price',
      header: 'Default price',
      align: AppTableColumnAlign.end,
      cellBuilder: (context, item) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppMoney(amount: Decimal.parse(item.defaultPrice.wireValue), emphasis: AppMoneyEmphasis.normal),
      ),
    ),
    AppTableColumn(
      id: 'global_status',
      header: 'Global status',
      cellBuilder: (context, item) {
        final isActive = item.globalStatus == GlobalStatus.active;
        return AppBadge(
          color: isActive ? AppBadgeColor.success : AppBadgeColor.neutral,
          child: Text(item.globalStatus.name),
        );
      },
    ),
    AppTableColumn(
      id: 'branches',
      header: 'Branches',
      align: AppTableColumnAlign.end,
      cellBuilder: (context, item) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Text(
          '${item.assignedBranchCount}',
          style: typography.tabular(typography.body).copyWith(color: colors.textSecondary),
        ),
      ),
    ),
    AppTableColumn(
      id: 'branch_price',
      header: 'Branch price',
      align: AppTableColumnAlign.end,
      cellBuilder: (context, item) {
        final summary = item.branchSummary;
        if (summary == null) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppMoney(amount: Decimal.parse(summary.effectivePrice.wireValue), emphasis: AppMoneyEmphasis.strong),
              if (summary.onPromotion)
                Text(
                  ServicePricePreview.promotionBadge(onPromotion: true) ?? '',
                  style: typography.caption.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        );
      },
    ),
    AppTableColumn(
      id: 'updated_at',
      header: 'Updated',
      cellBuilder: (context, item) => Text(
        BillingFormatting.formatDate(item.updatedAt),
        style: typography.tabular(typography.bodySm).copyWith(color: colors.textSecondary),
      ),
    ),
  ];
}

/// Narrow-layout card for a catalog row.
Widget buildServiceCatalogRowCard(BuildContext context, ServiceListItem item, {VoidCallback? onTap}) {
  final branchSummary = item.branchSummary;
  final branchLabel = branchSummary == null
      ? '${item.assignedBranchCount} branches'
      : '${ServicePricePreview.formatUnitPrice(branchSummary.effectivePrice)} · ${branchSummary.status}';

  return ServiceCard(
    name: item.name,
    price: item.defaultPrice.asDouble,
    globalStatus: item.globalStatus == GlobalStatus.active
        ? ServiceCardGlobalStatus.active
        : ServiceCardGlobalStatus.inactive,
    branchSummary: branchLabel,
    onViewBranches: onTap,
  );
}
