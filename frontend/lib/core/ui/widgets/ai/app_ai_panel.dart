import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// A single message in [AppAiPanel] history.
class AppAiPanelMessage {
  const AppAiPanelMessage({
    required this.id,
    required this.role,
    required this.content,
    this.timestamp,
    this.streaming = false,
  });

  final String id;
  final AppAiMessageRole role;
  final String content;
  final String? timestamp;

  /// Fade-in content updates while the assistant response streams.
  final bool streaming;
}

/// Controlled AI chat panel with message history, input, and scope indicator.
class AppAiPanel extends StatefulWidget {
  const AppAiPanel({
    required this.messages,
    this.thinking = false,
    this.streaming = false,
    this.scope,
    this.scopeIndicator,
    this.suggestedPrompts = _defaultSuggestedPrompts,
    this.inputController,
    this.inputValue,
    this.onInputChanged,
    this.onSend,
    this.onStop,
    this.onRegenerate,
    this.onCopyMessage,
    this.emptyHint =
        'Ask about patients, appointments, or clinic operations.',
    super.key,
  });

  final List<AppAiPanelMessage> messages;
  final bool thinking;
  final bool streaming;
  final String? scope;
  final Widget? scopeIndicator;
  final List<String> suggestedPrompts;
  final TextEditingController? inputController;
  final String? inputValue;
  final ValueChanged<String>? onInputChanged;
  final ValueChanged<String>? onSend;
  final VoidCallback? onStop;
  final VoidCallback? onRegenerate;
  final ValueChanged<AppAiPanelMessage>? onCopyMessage;
  final String emptyHint;

  static const List<String> _defaultSuggestedPrompts = [
    "Summarize today's appointments",
    'Find patients due for follow-up',
    'Draft a SOAP note template',
  ];

  @override
  State<AppAiPanel> createState() => _AppAiPanelState();
}

class _AppAiPanelState extends State<AppAiPanel> {
  late TextEditingController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    if (widget.inputController != null) {
      _controller = widget.inputController!;
    } else {
      _controller = TextEditingController(text: widget.inputValue);
      _ownsController = true;
    }
  }

  @override
  void didUpdateWidget(covariant AppAiPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inputController != oldWidget.inputController) {
      if (_ownsController) _controller.dispose();
      _initController();
      _ownsController = widget.inputController == null;
    } else if (widget.inputValue != oldWidget.inputValue &&
        widget.inputController == null &&
        widget.inputValue != _controller.text) {
      _controller.text = widget.inputValue ?? '';
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _handleSend([String? value]) {
    final text = (value ?? _controller.text).trim();
    if (text.isEmpty) return;
    widget.onSend?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final scopeLabel = widget.scope ?? 'Main branch';
    final signalActive = widget.thinking || widget.streaming;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        border: Border.all(color: colors.borderAi),
        borderRadius: AppRadii.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.borderSubtle),
              ),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      AppIcon(
                        icon: LucideIcons.sparkles,
                        size: AppIconSize.lg,
                        color: colors.textAi,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          'AI assistant',
                          style: typography.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.onRegenerate != null &&
                          widget.messages.isNotEmpty &&
                          !widget.thinking)
                        AppIconButton(
                          icon: LucideIcons.refreshCw,
                          semanticLabel: 'Regenerate response',
                          variant: AppIconButtonVariant.ghost,
                          size: AppIconButtonSize.sm,
                          onPressed: widget.onRegenerate,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  widget.scopeIndicator ??
                      Text(
                        'Scope: $scopeLabel · Human approval required for all actions',
                        style: typography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  const SizedBox(height: AppSpacing.s2),
                  AppSignalLine(
                    ai: true,
                    orientation: AppSignalOrientation.horizontal,
                    thinking: signalActive,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
              children: [
                if (widget.messages.isEmpty)
                  _EmptyPrompts(
                    hint: widget.emptyHint,
                    prompts: widget.suggestedPrompts,
                    onPrompt: _handleSend,
                  )
                else
                  ...widget.messages.map(
                    (message) => Padding(
                      padding: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.s4,
                      ),
                      child: AppAiMessageBubble(
                        role: message.role,
                        content: message.content,
                        timestamp: message.timestamp,
                        streaming: message.streaming,
                        onCopy: widget.onCopyMessage == null
                            ? null
                            : () => widget.onCopyMessage!(message),
                      ),
                    ),
                  ),
                if (widget.thinking) const AppAiThinkingIndicator(),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colors.borderSubtle),
              ),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _controller,
                      hintText: 'Ask AI…',
                      disabled: widget.thinking,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleSend,
                      onChanged: widget.onInputChanged,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  if (widget.thinking)
                    AppIconButton(
                      icon: LucideIcons.square,
                      semanticLabel: 'Stop',
                      variant: AppIconButtonVariant.ai,
                      onPressed: widget.onStop,
                    )
                  else
                    _SendButton(onPressed: () => _handleSend()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = AppIconButton(
      icon: LucideIcons.send,
      semanticLabel: 'Send',
      variant: AppIconButtonVariant.ai,
      onPressed: onPressed,
    );
    if (Directionality.of(context) == TextDirection.rtl) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: button,
      );
    }
    return button;
  }
}

class _EmptyPrompts extends StatelessWidget {
  const _EmptyPrompts({
    required this.hint,
    required this.prompts,
    required this.onPrompt,
  });

  final String hint;
  final List<String> prompts;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          hint,
          style: typography.bodySm.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s3),
        Wrap(
          spacing: AppSpacing.s2,
          runSpacing: AppSpacing.s2,
          children: [
            for (final prompt in prompts)
              AppChip(
                onTap: () => onPrompt(prompt),
                child: Text(
                  prompt,
                  style: typography.bodySm.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
