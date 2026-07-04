import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/spinner.dart';

/// Search field with icon, optional loading state, and clear action.
class AppSearchInput extends StatefulWidget {
  const AppSearchInput({
    super.key,
    this.controller,
    this.focusNode,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hintText,
    this.loading = false,
    this.resultCount,
    this.showShortcutHint = true,
    this.debounceMs = 300,
    this.onChanged,
    this.onValueChange,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String? hintText;
  final bool loading;
  final int? resultCount;
  final bool showShortcutHint;
  final int debounceMs;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onValueChange;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppSearchInput> createState() => _AppSearchInputState();
}

class _AppSearchInputState extends State<AppSearchInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focused = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _ownsController = widget.controller == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_handleFocus);
  }

  void _handleFocus() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_handleFocus);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onValueChange?.call('');
    setState(() {});
  }

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: widget.debounceMs), () {
      widget.onValueChange?.call(value);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final hasValue = _controller.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: Shortcuts(
            shortcuts: {
              LogicalKeySet(LogicalKeyboardKey.escape): const _ClearIntent(),
            },
            child: Actions(
              actions: {
                _ClearIntent: CallbackAction<_ClearIntent>(
                  onInvoke: (_) {
                    if (_focusNode.hasFocus) _clear();
                    return null;
                  },
                ),
              },
              child: Container(
                constraints: BoxConstraints(
                  minHeight: AppInputStyles.height(widget.size),
                ),
                padding: AppInputStyles.padding(widget.size),
                decoration: AppInputStyles.wrapperDecoration(
                  context,
                  size: widget.size,
                  invalid: widget.invalid,
                  disabled: widget.disabled,
                  readOnly: widget.readOnly,
                  focused: _focused,
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: colors.iconMuted),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !widget.disabled,
                        readOnly: widget.readOnly,
                        style: AppInputStyles.textStyle(
                          context,
                          widget.size,
                        ).copyWith(color: colors.textPrimary),
                        cursorColor: colors.borderFocus,
                        decoration:
                            const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: 'Search',
                            ).copyWith(
                              hintText: widget.hintText ?? 'Search',
                              hintStyle: AppInputStyles.textStyle(
                                context,
                                widget.size,
                              ).copyWith(color: colors.textPlaceholder),
                            ),
                        onChanged: _handleChanged,
                        onSubmitted: widget.onSubmitted,
                      ),
                    ),
                    if (widget.loading)
                      const AppSpinner(size: AppSpinnerSize.sm)
                    else if (hasValue)
                      TextButton(
                        onPressed: widget.disabled ? null : _clear,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s1,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Clear',
                          style: typography.caption.copyWith(
                            color: colors.textLink,
                          ),
                        ),
                      )
                    else if (widget.showShortcutHint && !hasValue)
                      _ShortcutHint(
                        reducedMotion: AppMotion.isReducedMotion(context),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.resultCount != null) ...[
          const SizedBox(height: AppSpacing.s1),
          Text(
            '${widget.resultCount} ${widget.resultCount == 1 ? 'result' : 'results'}',
            style: typography.caption.copyWith(
              color: colors.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

class _ClearIntent extends Intent {
  const _ClearIntent();
}

class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint({required this.reducedMotion});

  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s1,
        vertical: AppSpacing.s0_5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(
        '/',
        style: typography.caption.copyWith(color: colors.textTertiary),
      ),
    );
  }
}
