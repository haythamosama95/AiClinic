import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Stable marker for provisional AI prose (Clarification Q3; FR-001).
const kAiProvisionalProseKey = Key('ai_provisional_prose');
const kAiProvisionalProseSemanticsLabel = 'AI draft content';

/// Live provisional prose with draft styling tokens (§6.4; FR-003).
class ProvisionalProseView extends StatelessWidget {
  const ProvisionalProseView({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      label: kAiProvisionalProseSemanticsLabel,
      child: Container(
        key: kAiProvisionalProseKey,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAi,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderAi),
        ),
        child: Text(text, style: AppTypography.body(context).copyWith(color: colors.textAi)),
      ),
    );
  }
}

/// Extracts displayable prose from a terminal validated payload (§6.4 inv. 1).
String? terminalProseText(Object? result) {
  if (result is! Map) {
    return null;
  }
  final map = Map<String, dynamic>.from(result);
  final finalContent = map['final content'];
  if (finalContent is Map) {
    final text = finalContent['text'];
    if (text is String) {
      return text;
    }
  }
  final direct = map['text'];
  if (direct is String) {
    return direct;
  }
  return null;
}

/// Extracts provisional text from a streamed content chunk.
String? provisionalChunkText(Object? payload) {
  if (payload is Map) {
    final text = payload['text'];
    if (text is String) {
      return text;
    }
  }
  if (payload is String) {
    return payload;
  }
  return null;
}
