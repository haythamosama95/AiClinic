import 'package:flutter/material.dart';

/// Single-line label that shrinks to fit instead of wrapping or ellipsizing.
class AppointmentScaleDownText extends StatelessWidget {
  const AppointmentScaleDownText({
    required this.text,
    this.style,
    this.alignment = Alignment.centerLeft,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}
