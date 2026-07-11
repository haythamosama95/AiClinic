import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/components/app_text_input.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';

/// Resolves a user-entered value to a Google Maps URL suitable for opening in a browser.
Uri googleMapsUriFor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return Uri.parse('https://www.google.com/maps/search/?api=1');
  }

  if (trimmed.contains('://')) {
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.isNotEmpty && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri;
    }
  }

  if (trimmed.contains('.') && !trimmed.contains(' ')) {
    final uri = Uri.tryParse('https://$trimmed');
    if (uri != null && uri.host.isNotEmpty) {
      return uri;
    }
  }

  return Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(trimmed)}');
}

/// Opens Google Maps in the default browser for [value] (URL, domain, or address search).
Future<bool> openGoogleMapsLocation(String value) {
  return launchUrl(googleMapsUriFor(value), mode: LaunchMode.externalApplication);
}

/// Location input styled like [AppTextInput] with a Google Maps picker action.
///
/// The field accepts pasted map links or addresses. The trailing map action opens
/// Google Maps in the default browser so the user can search, copy a share link, and
/// paste it back into the field.
class AppLocationInput extends StatefulWidget {
  const AppLocationInput({
    this.controller,
    this.initialValue,
    this.onChanged,
    this.placeholder = 'https://maps.google.com/… or street address',
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.onOpenMaps,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String placeholder;
  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final Future<bool> Function(String value)? onOpenMaps;

  @override
  State<AppLocationInput> createState() => _AppLocationInputState();
}

class _AppLocationInputState extends State<AppLocationInput> {
  TextEditingController? _internalController;

  TextEditingController get _controller => widget.controller ?? _internalController!;

  bool get _canOpenMaps => !widget.disabled && !widget.readOnly;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.initialValue);
    }
  }

  @override
  void didUpdateWidget(covariant AppLocationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (widget.controller == null) {
        _internalController ??= TextEditingController(text: widget.initialValue);
      } else {
        _internalController?.dispose();
        _internalController = null;
      }
    }
    if (widget.initialValue != oldWidget.initialValue &&
        widget.controller == null &&
        _controller.text.isEmpty &&
        widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  Future<void> _handleOpenMaps() async {
    if (!_canOpenMaps) return;
    final open = widget.onOpenMaps ?? openGoogleMapsLocation;
    await open(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = appInputMetrics(context, widget.size);

    return AppTextInput(
      id: widget.id,
      controller: _controller,
      onChanged: widget.onChanged,
      placeholder: widget.placeholder,
      size: widget.size,
      invalid: widget.invalid,
      disabled: widget.disabled,
      readOnly: widget.readOnly,
      keyboardType: TextInputType.url,
      leadingIcon: Icon(Icons.location_on, size: metrics.iconSize, color: colors.iconMuted),
      trailingIcon: Semantics(
        button: true,
        label: 'Open in Google Maps',
        enabled: _canOpenMaps,
        child: AppPressable(
          enabled: _canOpenMaps,
          onPressed: _canOpenMaps ? _handleOpenMaps : null,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.map_outlined, size: metrics.iconSize, color: colors.iconMuted),
          ),
        ),
      ),
    );
  }
}
