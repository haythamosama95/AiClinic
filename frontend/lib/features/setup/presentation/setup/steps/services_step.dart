import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_money_field.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_field_hints.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_form_layout.dart';
import 'package:ai_clinic/features/setup/presentation/setup/widgets/collapsed_summary_enter_transition.dart';

/// Services step (web `ServicesStep`).
class ServicesStep extends ConsumerWidget {
  const ServicesStep({required this.errors, super.key});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(clinicSetupProvider.select((state) => state.draft));
    final notifier = ref.read(clinicSetupProvider.notifier);
    final colors = context.appColors;
    final currency = draft.organization.currency;

    void updateServiceName(String id, String name) {
      notifier.updateService(id, name: name);
    }

    void updateServicePrice(String id, double? price) {
      if (price == null) {
        notifier.updateService(id, clearPrice: true);
      } else {
        notifier.updateService(id, price: price);
      }
    }

    void removeService(String id) {
      notifier.removeService(id);
      if (ref.read(clinicSetupProvider).draft.services.isEmpty) {
        notifier.addService();
      }
    }

    void addService() {
      notifier.addService();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColorPrimitives.violet50,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.medical_services, size: 22, color: AppColorPrimitives.violet600),
              ),
            ),
            const SizedBox(width: AppSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Service catalog', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
                  const SizedBox(height: AppSpacing.space1),
                  Text(
                    'Define the procedures and treatments you bill for. You can add more services and branch-specific pricing later.',
                    style: AppTypography.body(context).copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space6),
        if (errors['_form'] != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(errors['_form']!, style: AppTypography.body(context).copyWith(color: colors.statusDangerFg)),
          ),
          const SizedBox(height: AppSpacing.space4),
        ],
        AppCard(
          variant: CardVariant.flat,
          padding: CardPadding.lg,
          child: Builder(
            builder: (context) {
              final isWide = setupFormUseTwoColumns(context);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isWide) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.space4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Service name',
                              style: AppTypography.caption(
                                context,
                              ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w500),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: Text(
                              'Price',
                              style: AppTypography.caption(
                                context,
                              ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.space3),
                          SizedBox(width: appInputMetrics(context, AppInputSize.md).height),
                        ],
                      ),
                    ),
                  ],
                  for (var index = 0; index < draft.services.length; index++) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.space3),
                    _ServiceRow(
                      service: draft.services[index],
                      index: index,
                      currency: currency,
                      errors: errors,
                      isWide: isWide,
                      showDivider: index < draft.services.length - 1,
                      onUpdateName: (name) => updateServiceName(draft.services[index].id, name),
                      onUpdatePrice: (price) => updateServicePrice(draft.services[index].id, price),
                      onRemove: () => removeService(draft.services[index].id),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.space4),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      onPressed: addService,
                      leadingIcon: const Icon(Icons.add, size: 16),
                      child: const Text('Add another service'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.index,
    required this.currency,
    required this.errors,
    required this.isWide,
    required this.showDivider,
    required this.onUpdateName,
    required this.onUpdatePrice,
    required this.onRemove,
  });

  final ServiceDraft service;
  final int index;
  final String currency;
  final Map<String, String> errors;
  final bool isWide;
  final bool showDivider;
  final ValueChanged<String> onUpdateName;
  final ValueChanged<double?> onUpdatePrice;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final prefix = 'service-$index';
    final nameField = AppFormField(
      id: '${service.id}-name',
      label: 'Service name',
      requiredMark: !isWide,
      hint: SetupFieldHints.serviceName,
      error: errors['$prefix-name'],
      child: AppTextInput(
        id: '${service.id}-name',
        initialValue: service.name,
        onChanged: onUpdateName,
        placeholder: 'e.g. Dental cleaning',
        invalid: errors['$prefix-name'] != null,
      ),
    );
    final priceField = AppFormField(
      id: '${service.id}-price',
      label: 'Price',
      requiredMark: !isWide,
      hint: SetupFieldHints.servicePrice,
      error: errors['$prefix-price'],
      child: AppMoneyField(
        id: '${service.id}-price',
        currency: currency,
        initialValue: service.price,
        onValueChange: onUpdatePrice,
        invalid: errors['$prefix-price'] != null,
      ),
    );

    final inputHeight = appInputMetrics(context, AppInputSize.md).height;

    final removeButton = AppIconButton(
      icon: const Icon(Icons.delete_outline, size: 16),
      label: 'Remove service',
      variant: AppIconButtonVariant.danger,
      dimension: inputHeight,
      onPressed: onRemove,
    );

    final actionTopInset = isWide ? _formFieldLabelInset(context) : 0.0;

    Widget rowContent;
    if (isWide) {
      rowContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: nameField),
          const SizedBox(width: AppSpacing.space3),
          SizedBox(width: 160, child: priceField),
          const SizedBox(width: AppSpacing.space3),
          Padding(
            padding: EdgeInsets.only(top: actionTopInset),
            child: removeButton,
          ),
        ],
      );
    } else {
      rowContent = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameField,
          const SizedBox(height: AppSpacing.space3),
          priceField,
          const SizedBox(height: AppSpacing.space3),
          Align(alignment: AlignmentDirectional.centerEnd, child: removeButton),
        ],
      );
    }

    return CollapsedSummaryEnterTransition(
      child: DecoratedBox(
        decoration: showDivider && isWide
            ? BoxDecoration(
                border: Border(bottom: BorderSide(color: context.appColors.borderSubtle)),
              )
            : const BoxDecoration(),
        child: Padding(
          padding: EdgeInsets.only(bottom: showDivider ? AppSpacing.space3 : 0),
          child: rowContent,
        ),
      ),
    );
  }
}

/// Top inset that matches [AppFormField]'s label row + gap so action buttons align with the control.
double _formFieldLabelInset(BuildContext context) {
  final labelStyle = AppTypography.bodyStrong(context);
  final textHeight = (TextPainter(
    text: TextSpan(text: 'Ag', style: labelStyle),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout()).height;
  const hintIconHeight = 20.0;
  return math.max(textHeight, hintIconHeight) + AppSpacing.space2;
}
