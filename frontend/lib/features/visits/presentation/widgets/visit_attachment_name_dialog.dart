import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Prompts for a display name after the user selects a file to upload.
class VisitAttachmentNameDialog extends StatefulWidget {
  const VisitAttachmentNameDialog({required this.filename, required this.onCancel, required this.onConfirm, super.key});

  final String filename;
  final VoidCallback onCancel;
  final ValueChanged<String> onConfirm;

  /// Returns the trimmed name, or `null` if the user cancels.
  static Future<String?> show(BuildContext context, {required String filename}) {
    return AppDialog.show<String>(
      context: context,
      title: 'Name attachment',
      barrierDismissible: false,
      bodyBuilder: (dialogContext) => VisitAttachmentNameDialog(
        key: const Key('visit_attachment_name_dialog'),
        filename: filename,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: (label) => Navigator.of(dialogContext).pop(label),
      ),
    );
  }

  @override
  State<VisitAttachmentNameDialog> createState() => _VisitAttachmentNameDialogState();
}

class _VisitAttachmentNameDialogState extends State<VisitAttachmentNameDialog> {
  static const _maxLabelLength = 200;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _controller.text.trim();
    if (label.isEmpty) {
      setState(() => _errorMessage = 'Enter a name for this attachment.');
      return;
    }
    if (label.length > _maxLabelLength) {
      setState(() => _errorMessage = 'Name must be $_maxLabelLength characters or fewer.');
      return;
    }
    widget.onConfirm(label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Selected file: ${widget.filename}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: SpacingTokens.md),
        AppTextField(
          key: const Key('visit_attachment_name_field'),
          label: 'Name *',
          hintText: 'e.g. Lab results, X-ray report',
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.done,
          onSubmit: (_) => _submit(),
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('visit_attachment_name_error'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: SpacingTokens.lg),
        Row(
          children: [
            Expanded(
              child: AppButton(
                key: const Key('visit_attachment_name_cancel'),
                label: 'Cancel',
                variant: AppButtonVariant.outline,
                onPressed: widget.onCancel,
              ),
            ),
            const SizedBox(width: SpacingTokens.sm),
            Expanded(
              child: AppButton(key: const Key('visit_attachment_name_confirm'), label: 'Upload', onPressed: _submit),
            ),
          ],
        ),
      ],
    );
  }
}
