import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/actions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/inputs.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_dialog.dart';

/// Presents a consequence-first confirmation dialog for destructive or financial
/// actions.
///
/// Returns `true` when the user confirms, `false` when cancelled or dismissed.
Future<bool> showAppConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = true,
  String? typedConfirmation,
  bool loading = false,
}) {
  return showAppDialog(
    context,
    size: AppDialogSize.sm,
    barrierDismissible: true,
    semanticLabel: title,
    builder: (dialogContext, AppDialogCloseCallback<bool> close) {
      return _AppConfirmationDialogContent(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
        typedConfirmation: typedConfirmation,
        loading: loading,
        onClose: () => close(false),
        onConfirm: () => close(true),
      );
    },
  ).then((value) => value ?? false);
}

class _AppConfirmationDialogContent extends StatefulWidget {
  const _AppConfirmationDialogContent({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.onClose,
    required this.onConfirm,
    this.typedConfirmation,
    this.loading = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final String? typedConfirmation;
  final bool loading;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  @override
  State<_AppConfirmationDialogContent> createState() =>
      _AppConfirmationDialogContentState();
}

class _AppConfirmationDialogContentState
    extends State<_AppConfirmationDialogContent> {
  late final TextEditingController _typedController;

  @override
  void initState() {
    super.initState();
    _typedController = TextEditingController();
    _typedController.addListener(_handleTypedChanged);
  }

  @override
  void dispose() {
    _typedController
      ..removeListener(_handleTypedChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTypedChanged() => setState(() {});

  bool get _canConfirm {
    final token = widget.typedConfirmation;
    if (token == null) return true;
    return _typedController.text == token;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final token = widget.typedConfirmation;

    return AppDialog(
      title: widget.title,
      size: AppDialogSize.sm,
      onClose: widget.onClose,
      semanticLabel: widget.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.message,
            style: typography.body.copyWith(color: colors.textSecondary),
          ),
          if (token != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Type $token to confirm',
              style: typography.bodySm.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s2),
            AppTextField(
              controller: _typedController,
              hintText: token,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_canConfirm && !widget.loading) {
                  widget.onConfirm();
                }
              },
            ),
          ],
        ],
      ),
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: widget.cancelLabel,
            variant: AppButtonVariant.secondary,
            onPressed: widget.loading ? null : widget.onClose,
          ),
          AppButton(
            label: widget.confirmLabel,
            variant: widget.destructive
                ? AppButtonVariant.danger
                : AppButtonVariant.primary,
            loading: widget.loading,
            disabled: !_canConfirm,
            onPressed: _canConfirm && !widget.loading ? widget.onConfirm : null,
          ),
        ],
      ),
    );
  }
}
