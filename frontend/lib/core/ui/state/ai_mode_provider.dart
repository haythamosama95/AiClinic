import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session-scoped standard ↔ AI accent mode (teal primary vs violet AI tokens).
///
/// Consumers read [aiModeProvider] and branch on accent semantics — for example
/// `colors.actionPrimary` / `colors.textLink` in standard mode versus
/// `colors.actionAi` / `colors.textAi` / `colors.focusRingAi` when AI mode is on.
/// Resets to standard (`false`) on each app launch; not persisted.
class AiModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Enables or disables AI accent mode.
  void setAiMode(bool enabled) => state = enabled;

  /// Flips between standard and AI accent mode.
  void toggleAiMode() => state = !state;
}

/// `true` when AI accent tokens should be used instead of the standard teal set.
final aiModeProvider = NotifierProvider<AiModeNotifier, bool>(AiModeNotifier.new);
