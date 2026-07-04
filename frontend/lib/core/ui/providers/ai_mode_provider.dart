import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global AI-assist mode toggle — mirrors web `AiModeProvider`.
class AiModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setAiMode(bool enabled) => state = enabled;

  void toggleAiMode() => state = !state;
}

final aiModeProvider = NotifierProvider<AiModeNotifier, bool>(
  AiModeNotifier.new,
);
