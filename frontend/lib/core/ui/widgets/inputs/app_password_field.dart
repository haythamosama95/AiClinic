import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';

/// Masked text input with reveal toggle and caps-lock hint.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.autofillHints = const [AutofillHints.password],
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final Iterable<String> autofillHints;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _visible = false;
  bool _capsLock = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PasswordInput(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          readOnly: widget.readOnly,
          hintText: widget.hintText,
          autofillHints: widget.autofillHints,
          obscureText: !_visible,
          visible: _visible,
          onToggleVisibility: widget.disabled
              ? null
              : () => setState(() => _visible = !_visible),
          onCapsLockChange: (value) {
            if (_capsLock != value) {
              setState(() => _capsLock = value);
            }
          },
        ),
        if (_capsLock) ...[
          const SizedBox(height: AppSpacing.s1),
          Semantics(
            liveRegion: true,
            child: Text(
              'Caps Lock is on',
              style: typography.caption.copyWith(color: colors.statusWarningFg),
            ),
          ),
        ],
      ],
    );
  }
}

class _PasswordInput extends StatefulWidget {
  const _PasswordInput({
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    required this.size,
    required this.invalid,
    required this.disabled,
    required this.readOnly,
    this.hintText,
    required this.autofillHints,
    required this.obscureText,
    required this.visible,
    this.onToggleVisibility,
    required this.onCapsLockChange,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final Iterable<String> autofillHints;
  final bool obscureText;
  final bool visible;
  final VoidCallback? onToggleVisibility;
  final ValueChanged<bool> onCapsLockChange;

  @override
  State<_PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<_PasswordInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || event is KeyDownEvent) {
      final capsOn = HardwareKeyboard.instance.lockModesEnabled.contains(
        KeyboardLockMode.capsLock,
      );
      widget.onCapsLockChange(capsOn);
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context)
        ? AppDurations.instant
        : AppDurations.fast;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: AppInputFrame(
        focusNode: _focusNode,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        readOnly: widget.readOnly,
        trailing: AppPressable(
          onTap: widget.onToggleVisibility,
          enabled: widget.onToggleVisibility != null,
          semanticLabel: widget.visible ? 'Hide password' : 'Show password',
          borderRadius: AppRadii.smAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s0_5),
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: AppEasings.out,
              switchOutCurve: AppEasings.inCurve,
              child: AppIcon(
                key: ValueKey(widget.visible),
                icon: widget.visible ? LucideIcons.eyeOff : LucideIcons.eye,
                size: AppIconSize.sm,
                color: context.colors.iconMuted,
              ),
            ),
          ),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: !widget.disabled,
          readOnly: widget.readOnly,
          obscureText: widget.obscureText,
          autofillHints: widget.autofillHints,
          style: appBareInputTextStyle(
            context,
            size: widget.size,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
          ),
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: appBareInputDecoration(
            context: context,
            size: widget.size,
            hintText: widget.hintText,
            disabled: widget.disabled,
            readOnly: widget.readOnly,
          ),
          cursorColor: context.colors.borderFocus,
        ),
      ),
    );
  }
}
