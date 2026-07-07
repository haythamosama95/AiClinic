import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Command bar open state and trigger registration (web `CommandBarProvider`).
@immutable
class CommandBarState {
  const CommandBarState({
    this.open = false,
    this.aiMode = false,
    this.triggerKey,
  });

  final bool open;
  final bool aiMode;
  final GlobalKey? triggerKey;

  CommandBarState copyWith({
    bool? open,
    bool? aiMode,
    GlobalKey? triggerKey,
    bool clearTriggerKey = false,
  }) {
    return CommandBarState(
      open: open ?? this.open,
      aiMode: aiMode ?? this.aiMode,
      triggerKey: clearTriggerKey ? null : (triggerKey ?? this.triggerKey),
    );
  }
}

class CommandBarController extends Notifier<CommandBarState> {
  @override
  CommandBarState build() => const CommandBarState();

  void openCommandBar() => state = state.copyWith(open: true);

  void closeCommandBar() => state = state.copyWith(open: false, aiMode: false);

  void toggleCommandBar() => state = state.copyWith(open: !state.open);

  void setAiMode(bool value) => state = state.copyWith(aiMode: value);

  void registerTrigger(GlobalKey? key) {
    if (key == null) {
      state = state.copyWith(clearTriggerKey: true);
    } else {
      state = state.copyWith(triggerKey: key);
    }
  }

  void focusTrigger() {
    final context = state.triggerKey?.currentContext;
    if (context == null) return;
    final focusNode = Focus.maybeOf(context);
    focusNode?.requestFocus();
  }
}

final commandBarProvider = NotifierProvider<CommandBarController, CommandBarState>(
  CommandBarController.new,
);
