import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';
import 'package:ai_clinic/core/widgets/app_field_label.dart';

/// Type-to-filter dropdown using one [TextEditingController] for reliable form validation.
class AppSearchableDropdownField extends StatefulWidget {
  const AppSearchableDropdownField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.options,
    required this.filterOptions,
    required this.controller,
    this.infoTooltip,
    this.hint,
    this.enabled = true,
    this.validator,
  });

  final Key? fieldKey;
  final String label;
  final String? infoTooltip;
  final String? hint;
  final List<String> options;
  final List<String> Function(String query) filterOptions;
  final TextEditingController controller;
  final bool enabled;
  final String? Function(String?)? validator;

  @override
  State<AppSearchableDropdownField> createState() => _AppSearchableDropdownFieldState();
}

class _AppSearchableDropdownFieldState extends State<AppSearchableDropdownField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _anchorKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    _removeOverlay();
    _focusNode.removeListener(_handleFocusChange);
    widget.controller.removeListener(_handleControllerChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (_showSuggestions) {
      _scheduleOverlaySync();
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      // Defer so pointer-down on a suggestion can select before the overlay closes.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _focusNode.hasFocus) return;
        _closeSuggestions();
      });
    }
  }

  List<String> get _filtered => widget.filterOptions(widget.controller.text);

  void _openSuggestions() {
    if (!widget.enabled) return;
    setState(() => _showSuggestions = true);
    _scheduleOverlaySync();
  }

  void _closeSuggestions() {
    if (!_showSuggestions && _overlayEntry == null) return;
    setState(() => _showSuggestions = false);
    _removeOverlay();
  }

  void _scheduleOverlaySync() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showSuggestions) {
        _syncOverlay();
      } else {
        _removeOverlay();
      }
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _syncOverlay() {
    _removeOverlay();
    if (!_showSuggestions || !widget.enabled || _filtered.isEmpty) return;

    final fieldBox = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (fieldBox == null || !fieldBox.hasSize) return;

    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    final fieldWidth = fieldBox.size.width;
    final fieldHeight = fieldBox.size.height;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, fieldHeight),
          child: SizedBox(
            width: fieldWidth,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(AppSpacing.sm),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: _SuggestionsList(options: _filtered, onSelect: _selectOption),
              ),
            ),
          ),
        );
      },
    );
    overlayState.insert(_overlayEntry!);
  }

  void _selectOption(String option) {
    widget.controller.value = TextEditingValue(
      text: option,
      selection: TextSelection.collapsed(offset: option.length),
    );
    _closeSuggestions();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(label: widget.label, infoTooltip: widget.infoTooltip),
        const SizedBox(height: AppSpacing.sm),
        CompositedTransformTarget(
          key: _anchorKey,
          link: _layerLink,
          child: TextFormField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            validator: widget.validator,
            onChanged: (_) => _openSuggestions(),
            onTap: _openSuggestions,
            decoration: InputDecoration(hintText: widget.hint, suffixIcon: const Icon(Icons.arrow_drop_down)),
          ),
        ),
      ],
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({required this.options, required this.onSelect});

  final List<String> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: options.length,
      itemBuilder: (context, index) {
        final option = options[index];
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => onSelect(option),
          child: ListTile(dense: true, title: Text(option)),
        );
      },
    );
  }
}
