import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/bmi.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Vital signs panel for the Findings & Diagnosis phase (014 US2).
class EncounterVitalSignsCard extends ConsumerWidget {
  const EncounterVitalSignsCard({
    required this.visitId,
    required this.vitalSigns,
    required this.predefinedVitalSigns,
    required this.canEdit,
    super.key,
  });

  final String visitId;
  final List<VisitVitalSign> vitalSigns;
  final List<CatalogItem> predefinedVitalSigns;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final bmi = deriveBmiFromVitalSigns(vitalSigns);

    return AppCard(
      padding: AppCardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: 'Vital signs',
            description: 'Current visit',
            actions: canEdit
                ? AppButton(
                    label: 'Add',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.plus,
                    onPressed: () => _showAddDialog(context, ref),
                  )
                : null,
          ),
          if (bmi != null) ...[
            const SizedBox(height: AppSpacing.s2),
            AppBadge(
              color: AppBadgeColor.info,
              child: Text('BMI · ${bmi.displayValue}'),
            ),
          ],
          const SizedBox(height: AppSpacing.s3),
          if (vitalSigns.isEmpty)
            const AppEmptyState(
              variant: AppEmptyStateVariant.noResults,
              title: 'No vital signs',
              description: 'Add measurements recorded during this visit.',
            )
          else
            for (final sign in vitalSigns)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s2),
                child: _VitalSignRow(
                  sign: sign,
                  canEdit: canEdit,
                  onEdit: () => _showEditDialog(context, ref, sign),
                  onArchive: () => ref
                      .read(visitDocumentationProvider(visitId).notifier)
                      .stageArchiveVitalSign(sign.id),
                  typography: typography,
                  colors: colors,
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final result = await showAppDialog<_VitalSignFormData>(
      context,
      size: AppDialogSize.sm,
      semanticLabel: 'Add vital sign',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Add vital sign',
          onClose: () => close(),
          body: _VitalSignForm(
            predefinedVitalSigns: predefinedVitalSigns,
            onSubmit: (data) => close(data),
            onCancel: () => close(),
          ),
        );
      },
    );
    if (result == null) return;
    ref.read(visitDocumentationProvider(visitId).notifier).stageCreateVitalSign(
          name: result.name,
          value: result.value,
          unit: result.unit,
          predefinedVitalSignId: result.predefinedId,
        );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    VisitVitalSign sign,
  ) async {
    final result = await showAppDialog<_VitalSignFormData>(
      context,
      size: AppDialogSize.sm,
      semanticLabel: 'Edit vital sign',
      builder: (dialogContext, close) {
        return AppDialog(
          title: 'Edit vital sign',
          onClose: () => close(),
          body: _VitalSignForm(
            predefinedVitalSigns: predefinedVitalSigns,
            initialName: sign.name,
            initialValue: sign.value,
            initialUnit: sign.unit,
            onSubmit: (data) => close(data),
            onCancel: () => close(),
          ),
        );
      },
    );
    if (result == null) return;
    ref.read(visitDocumentationProvider(visitId).notifier).stageUpdateVitalSign(
          vitalSignId: sign.id,
          name: result.name,
          value: result.value,
          unit: result.unit,
          predefinedVitalSignId: result.predefinedId,
        );
  }
}

class _VitalSignRow extends StatelessWidget {
  const _VitalSignRow({
    required this.sign,
    required this.canEdit,
    required this.onEdit,
    required this.onArchive,
    required this.typography,
    required this.colors,
  });

  final VisitVitalSign sign;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final AppTypography typography;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final unitSuffix = sign.unit != null && sign.unit!.isNotEmpty ? ' ${sign.unit}' : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        borderRadius: AppRadii.mdAll,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sign.name, style: typography.bodyStrong.copyWith(color: colors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    '${sign.value}$unitSuffix',
                    style: typography.tabular(typography.body).copyWith(color: colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (canEdit) ...[
              AppIconButton(
                icon: LucideIcons.pencil,
                semanticLabel: 'Edit ${sign.name}',
                size: AppIconButtonSize.sm,
                variant: AppIconButtonVariant.ghost,
                onPressed: onEdit,
              ),
              AppIconButton(
                icon: LucideIcons.trash2,
                semanticLabel: 'Remove ${sign.name}',
                size: AppIconButtonSize.sm,
                variant: AppIconButtonVariant.ghost,
                onPressed: onArchive,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VitalSignFormData {
  const _VitalSignFormData({
    required this.name,
    required this.value,
    this.unit,
    this.predefinedId,
  });

  final String name;
  final String value;
  final String? unit;
  final String? predefinedId;
}

class _VitalSignForm extends StatefulWidget {
  const _VitalSignForm({
    required this.predefinedVitalSigns,
    required this.onSubmit,
    required this.onCancel,
    this.initialName,
    this.initialValue,
    this.initialUnit,
  });

  final List<CatalogItem> predefinedVitalSigns;
  final ValueChanged<_VitalSignFormData> onSubmit;
  final VoidCallback onCancel;
  final String? initialName;
  final String? initialValue;
  final String? initialUnit;

  @override
  State<_VitalSignForm> createState() => _VitalSignFormState();
}

class _VitalSignFormState extends State<_VitalSignForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late final TextEditingController _unitController;
  String? _predefinedId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _valueController = TextEditingController(text: widget.initialValue ?? '');
    _unitController = TextEditingController(text: widget.initialUnit ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.predefinedVitalSigns.isNotEmpty) ...[
          AppFormField(
            label: 'Predefined',
            child: AppSelect<String?>(
              value: _predefinedId,
              placeholder: 'Custom',
              options: [
                const AppSelectOption<String?>(value: null, label: 'Custom'),
                for (final item in widget.predefinedVitalSigns)
                  AppSelectOption<String?>(
                    value: item.id,
                    label: item.defaultUnit == null
                        ? item.name
                        : '${item.name} (${item.defaultUnit})',
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  _predefinedId = value;
                  if (value != null) {
                    final match = widget.predefinedVitalSigns.firstWhere((i) => i.id == value);
                    _nameController.text = match.name;
                    if (match.defaultUnit != null) {
                      _unitController.text = match.defaultUnit!;
                    }
                  }
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
        AppFormField(
          label: 'Name',
          child: AppTextField(controller: _nameController, hintText: 'Blood pressure'),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Value',
          child: AppTextField(controller: _valueController, hintText: '120/80'),
        ),
        const SizedBox(height: AppSpacing.s3),
        AppFormField(
          label: 'Unit',
          child: AppTextField(controller: _unitController, hintText: 'mmHg'),
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
              label: 'Save',
              size: AppButtonSize.sm,
              onPressed: () {
                final name = _nameController.text.trim();
                final value = _valueController.text.trim();
                if (name.isEmpty || value.isEmpty) return;
                widget.onSubmit(
                  _VitalSignFormData(
                    name: name,
                    value: value,
                    unit: _unitController.text.trim().isEmpty ? null : _unitController.text.trim(),
                    predefinedId: _predefinedId,
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
