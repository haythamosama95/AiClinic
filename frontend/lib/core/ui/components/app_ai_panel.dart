import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_ai_message_bubble.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_signal.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/components/app_thinking_indicator.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const _suggestedPrompts = <String>[
  "Summarize today's appointments",
  'Find patients due for follow-up',
  'Draft a SOAP note template',
];

const _mockAssistantResponse =
    'Based on your clinic data, I found 3 patients with follow-ups due this week. '
    'I can prepare appointment proposals for your review.';

class _AiPanelMessage {
  const _AiPanelMessage({
    required this.id,
    required this.role,
    required this.content,
  });

  final String id;
  final AiMessageRole role;
  final String content;
}

/// AI chat panel with mock thinking flow (web `AiPanel`).
class AppAiPanel extends StatefulWidget {
  const AppAiPanel({
    this.scope = 'Main branch',
    super.key,
  });

  final String scope;

  @override
  State<AppAiPanel> createState() => _AppAiPanelState();
}

class _AppAiPanelState extends State<AppAiPanel> {
  final _messages = <_AiPanelMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  var _thinking = false;
  var _streaming = false;
  Timer? _responseTimer;

  @override
  void dispose() {
    _responseTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _responseTimer?.cancel();

    setState(() {
      _messages.add(
        _AiPanelMessage(
          id: 'u-${DateTime.now().millisecondsSinceEpoch}',
          role: AiMessageRole.user,
          content: trimmed,
        ),
      );
      _inputController.clear();
      _thinking = true;
      _streaming = false;
    });
    _scrollToBottom();

    _responseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _streaming = true;
        _messages.add(
          _AiPanelMessage(
            id: 'a-${DateTime.now().millisecondsSinceEpoch}',
            role: AiMessageRole.assistant,
            content: _mockAssistantResponse,
          ),
        );
        _streaming = false;
      });
      _scrollToBottom();
    });
  }

  void _stopThinking() {
    _responseTimer?.cancel();
    setState(() => _thinking = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderAi),
      ),
      child: Column(
        children: [
          _buildHeader(context, colors),
          Expanded(child: _buildBody(context, colors)),
          _buildComposer(context, colors),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppSemanticColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.space4,
          AppSpacing.space3,
          AppSpacing.space4,
          AppSpacing.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: colors.textAi),
                const SizedBox(width: AppSpacing.space2),
                Text(
                  'AI assistant',
                  style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Scope: ${widget.scope} · Human approval required for all actions',
              style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space2),
            AppSignal(
              variant: AppSignalVariant.ai,
              orientation: Axis.horizontal,
              thinking: _thinking || _streaming,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppSemanticColors colors) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsetsDirectional.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_messages.isEmpty) ...[
            Text(
              'Ask about patients, appointments, or clinic operations.',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space3),
            Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: [
                for (final prompt in _suggestedPrompts)
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    onPressed: () => _send(prompt),
                    child: Text(prompt),
                  ),
              ],
            ),
          ] else ...[
            for (final message in _messages)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.space4),
                child: AppAiMessageBubble(
                  role: message.role,
                  child: Text(message.content),
                ),
              ),
          ],
          if (_thinking) const AppThinkingIndicator(),
        ],
      ),
    );
  }

  Widget _buildComposer(BuildContext context, AppSemanticColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.space4),
        child: Row(
          children: [
            Expanded(
              child: AppTextInput(
                controller: _inputController,
                placeholder: 'Ask AI…',
                id: 'ai-panel-input',
                shellDecoration: appAiInputDecoration,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            if (_thinking)
              AppIconButton(
                icon: const Icon(Icons.stop, size: 16),
                label: 'Stop',
                variant: AppIconButtonVariant.ai,
                size: AppIconButtonSize.sm,
                onPressed: _stopThinking,
              )
            else
              AppIconButton(
                icon: const Icon(Icons.send, size: 16),
                label: 'Send',
                variant: AppIconButtonVariant.ai,
                size: AppIconButtonSize.sm,
                onPressed: () => _send(_inputController.text),
              ),
          ],
        ),
      ),
    );
  }
}
