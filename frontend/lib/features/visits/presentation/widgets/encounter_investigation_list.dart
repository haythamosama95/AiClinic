import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_catalog_field.dart';

/// Investigation orders with catalog autocomplete (013 US4).
class EncounterInvestigationList extends ConsumerWidget {
  const EncounterInvestigationList({
    required this.visitId,
    required this.investigations,
    required this.canEdit,
    super.key,
  });

  final String visitId;
  final List<VisitInvestigation> investigations;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;

    return AppCard(
      padding: AppCardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: 'Investigations',
            description: 'Labs and imaging ordered for this visit',
            actions: canEdit
                ? AppButton(
                    label: 'Add investigation',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.plus,
                    onPressed: () => _showAddDialog(context, ref),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.s3),
          if (investigations.isEmpty)
            const AppEmptyState(
              variant: AppEmptyStateVariant.noResults,
              title: 'No investigations',
              description: 'Order labs or imaging for this visit.',
            )
          else
            for (final investigation in investigations)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: AppRadii.mdAll,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                investigation.name,
                                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (investigation.note != null && investigation.note!.trim().isNotEmpty)
                                Text(
                                  investigation.note!,
                                  style: typography.bodySm.copyWith(color: colors.textSecondary),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (investigation.hasResult)
                                Text(
                                  'Result: ${investigation.result}',
                                  style: typography.caption.copyWith(color: colors.statusSuccessFg),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (canEdit)
                          AppIconButton(
                            icon: LucideIcons.trash2,
                            semanticLabel: 'Remove ${investigation.name}',
                            size: AppIconButtonSize.sm,
                            variant: AppIconButtonVariant.ghost,
                            onPressed: () => ref
                                .read(visitDocumentationProvider(visitId).notifier)
                                .stageArchiveInvestigation(investigation.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    await showAppDialog<void>(
      context,
      size: AppDialogSize.md,
      semanticLabel: 'Add investigation',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Add investigation',
          onClose: () => close(),
          body: _InvestigationForm(
            onCancel: () => close(),
            onSubmit: (data) {
              ref.read(visitDocumentationProvider(visitId).notifier).stageCreateInvestigation(
                    name: data.name,
                    note: data.note,
                    investigationId: data.investigationId,
                  );
              close();
            },
          ),
        );
      },
    );
  }
}

class _InvestigationFormData {
  const _InvestigationFormData({
    required this.name,
    this.note,
    this.investigationId,
  });

  final String name;
  final String? note;
  final String? investigationId;
}

class _InvestigationForm extends ConsumerStatefulWidget {
  const _InvestigationForm({
    required this.onSubmit,
    required this.onCancel,
  });

  final ValueChanged<_InvestigationFormData> onSubmit;
  final VoidCallback onCancel;

  @override
  ConsumerState<_InvestigationForm> createState() => _InvestigationFormState();
}

class _InvestigationFormState extends ConsumerState<_InvestigationForm> {
  CatalogFieldSelection _investigation = const CatalogFieldSelection(name: '');
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EncounterCatalogField(
          label: 'Investigation',
          onSearch: (query) => searchInvestigationCatalog(ref, query),
          onSelectionChanged: (selection) => setState(() => _investigation = selection),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Note',
          child: AppTextArea(controller: _noteController, hintText: 'Optional'),
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: widget.onCancel,
            ),
            const SizedBox(width: AppSpacing.s2),
            AppButton(
              label: 'Add',
              size: AppButtonSize.sm,
              onPressed: () {
                final name = CatalogNameNormalizer.normalize(_investigation.name);
                if (name.isEmpty) return;
                widget.onSubmit(
                  _InvestigationFormData(
                    name: name,
                    investigationId: _investigation.catalogId,
                    note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
