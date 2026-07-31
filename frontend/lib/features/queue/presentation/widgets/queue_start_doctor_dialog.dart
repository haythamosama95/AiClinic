import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/queue/domain/queue_start_doctor.dart';

/// Doctor picker shown before starting a checked-in appointment.
class QueueStartDoctorDialog extends StatefulWidget {
  const QueueStartDoctorDialog({required this.options, super.key});

  final List<QueueStartDoctorOption> options;

  static QueueStartDoctorOption? preferredOption(List<QueueStartDoctorOption> options) {
    return options.where((option) => option.isPreferred).firstOrNull;
  }

  static String? _descriptionFor(List<QueueStartDoctorOption> options) {
    if (preferredOption(options) != null) {
      return null;
    }
    return 'Choose the doctor taking this visit before you start.';
  }

  static Future<String?> show(BuildContext context, {required List<QueueStartDoctorOption> options}) {
    return AppDialog.show<String?>(
      context,
      title: 'Who will see this patient?',
      description: _descriptionFor(options),
      size: AppDialogSize.md,
      barrierDismissible: false,
      child: QueueStartDoctorDialog(options: options),
    );
  }

  @override
  State<QueueStartDoctorDialog> createState() => _QueueStartDoctorDialogState();
}

class _QueueStartDoctorDialogState extends State<QueueStartDoctorDialog> {
  String? _selectedDoctorId;

  @override
  void initState() {
    super.initState();
    final available = _availableOptions;
    final preferred = available.where((option) => option.isPreferred).firstOrNull;
    _selectedDoctorId = preferred?.id ?? available.firstOrNull?.id;
  }

  List<QueueStartDoctorOption> get _availableOptions =>
      widget.options.where((option) => !option.isBusy).toList(growable: false);

  QueueStartDoctorOption? get _preferredOption => QueueStartDoctorDialog.preferredOption(widget.options);

  void _confirm() {
    Navigator.of(context).pop(_selectedDoctorId);
  }

  @override
  Widget build(BuildContext context) {
    final availableOptions = _availableOptions;
    final preferredOption = _preferredOption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (availableOptions.isEmpty)
          const AppEmptyState(
            variant: AppEmptyStateVariant.error,
            title: 'No doctors available',
            description: 'Every doctor on shift already has a patient in progress.',
          )
        else ...[
          if (preferredOption != null) _PreferredProviderCallout(option: preferredOption),
          Semantics(
            container: true,
            inMutuallyExclusiveGroup: true,
            label: 'Doctors on shift',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < widget.options.length; index++) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.space2),
                  _DoctorPickerOptionTile(
                    option: widget.options[index],
                    selected: widget.options[index].id == _selectedDoctorId,
                    enabled: !widget.options[index].isBusy,
                    onSelected: widget.options[index].isBusy
                        ? null
                        : () => setState(() => _selectedDoctorId = widget.options[index].id),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.space4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.space2),
            AppButton(
              disabled: _selectedDoctorId == null || availableOptions.isEmpty,
              onPressed: _confirm,
              child: const Text('Start visit'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreferredProviderCallout extends StatelessWidget {
  const _PreferredProviderCallout({required this.option});

  final QueueStartDoctorOption option;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isBusy = option.isBusy;

    final backgroundColor = isBusy
        ? colors.statusWarningSurface.withValues(alpha: 0.65)
        : colors.statusInfoSurface.withValues(alpha: 0.55);
    final borderColor = isBusy
        ? colors.statusWarningBorder.withValues(alpha: 0.5)
        : colors.statusInfoBorder.withValues(alpha: 0.45);
    final accentColor = isBusy ? colors.statusWarningFg : colors.statusInfoFg;
    final icon = isBusy ? Icons.schedule_outlined : Icons.verified_outlined;
    final title = isBusy ? 'Preferred provider — busy now' : 'Preferred provider';
    final detail = isBusy
        ? '${option.name} is with${option.currentPatientName != null ? ' ${option.currentPatientName}' : ' a patient'} right now. Wait for them to finish or choose another doctor below.'
        : 'Assigned to this visit. Confirm ${option.name} or choose another doctor below.';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.caption(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2, color: accentColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(fontWeight: FontWeight.w500, color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorPickerOptionTile extends StatefulWidget {
  const _DoctorPickerOptionTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final QueueStartDoctorOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback? onSelected;

  @override
  State<_DoctorPickerOptionTile> createState() => _DoctorPickerOptionTileState();
}

class _DoctorPickerOptionTileState extends State<_DoctorPickerOptionTile> {
  static const _outerSize = 20.0;
  static const _innerSize = 10.0;

  var _focused = false;
  late final FocusNode _focusNode = FocusNode()..addListener(_handleFocusChange);

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focusRing = appInputFocusRingColor(context);
    final option = widget.option;
    final isAvailable = option.availability == QueueStartDoctorAvailability.available;
    final statusLabel = isAvailable ? 'Available' : 'With patient';
    final statusColor = isAvailable ? BadgeColor.success : BadgeColor.info;

    final semanticsLabel = [
      option.name,
      if (option.isPreferred) 'preferred provider',
      statusLabel.toLowerCase(),
      if (option.currentPatientName != null) 'with ${option.currentPatientName}',
    ].join(', ');

    return Semantics(
      checked: widget.selected,
      enabled: widget.enabled,
      inMutuallyExclusiveGroup: true,
      label: semanticsLabel,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.72,
        child: Material(
          color: widget.selected ? colors.actionPrimary.withValues(alpha: 0.08) : colors.surfaceDefault,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(
              color: widget.selected
                  ? colors.actionPrimary
                  : (option.isBusy ? colors.borderSubtle : colors.borderDefault),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onSelected,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.space3,
                vertical: AppSpacing.space2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Focus(
                    focusNode: _focusNode,
                    canRequestFocus: widget.enabled,
                    skipTraversal: !widget.selected,
                    onKeyEvent: (node, event) {
                      if (!widget.enabled || event is! KeyDownEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.space ||
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        widget.onSelected?.call();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      curve: AppMotion.standardCurve,
                      width: _outerSize,
                      height: _outerSize,
                      decoration: BoxDecoration(
                        color: colors.surfaceDefault,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.selected
                              ? colors.actionPrimary
                              : (widget.enabled ? colors.borderDefault : colors.borderSubtle),
                        ),
                        boxShadow: _focused ? [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)] : null,
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: AppMotion.fast,
                          curve: AppMotion.standardCurve,
                          width: widget.selected ? _innerSize : 0,
                          height: widget.selected ? _innerSize : 0,
                          decoration: BoxDecoration(color: colors.actionPrimary, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.name,
                          style: AppTypography.body(context).copyWith(
                            fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                            color: widget.enabled ? colors.textPrimary : colors.textSecondary,
                          ),
                        ),
                        if (option.currentPatientName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'With ${option.currentPatientName}',
                            style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space1,
                    runSpacing: AppSpacing.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (option.isPreferred)
                        const AppBadge(label: 'Preferred', color: BadgeColor.info, size: BadgeSize.sm),
                      AppBadge(label: statusLabel, color: statusColor, size: BadgeSize.sm),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
