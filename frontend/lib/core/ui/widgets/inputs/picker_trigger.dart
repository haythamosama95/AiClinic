import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';

/// Builds a bordered input shell for picker triggers (date, time, range).
Widget appPickerTriggerShell({
  required BuildContext context,
  required AppInputSize size,
  required Widget child,
  bool invalid = false,
  bool disabled = false,
  bool readOnly = false,
  bool focused = false,
}) {
  return Container(
    constraints: BoxConstraints(minHeight: AppInputStyles.height(size)),
    padding: EdgeInsetsDirectional.only(
      start: AppSpacing.s3,
      end: AppSpacing.s10,
      top: AppSpacing.s2,
      bottom: AppSpacing.s2,
    ),
    decoration: AppInputStyles.wrapperDecoration(
      context,
      size: size,
      invalid: invalid,
      disabled: disabled,
      readOnly: readOnly,
      focused: focused,
    ),
    child: child,
  );
}
