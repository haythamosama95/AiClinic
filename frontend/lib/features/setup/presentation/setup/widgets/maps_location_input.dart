import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_form_field.dart';
import 'package:ai_clinic/core/ui/components/app_location_input.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_field_hints.dart';

/// Google Maps location field for clinic setup (web `MapsLocationInput`).
class MapsLocationInput extends StatefulWidget {
  const MapsLocationInput({
    required this.id,
    required this.value,
    required this.onChange,
    this.error,
    this.invalid = false,
    super.key,
  });

  final String id;
  final String value;
  final ValueChanged<String> onChange;
  final String? error;
  final bool invalid;

  @override
  State<MapsLocationInput> createState() => _MapsLocationInputState();
}

class _MapsLocationInputState extends State<MapsLocationInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant MapsLocationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppFormField(
      id: widget.id,
      label: 'Google Maps location',
      requiredMark: true,
      hint: SetupFieldHints.branchMapLocation,
      error: widget.error,
      child: AppLocationInput(
        id: widget.id,
        controller: _controller,
        onChanged: widget.onChange,
        invalid: widget.invalid,
      ),
    );
  }
}
