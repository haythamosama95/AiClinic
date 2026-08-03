import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Calendar page chrome with a page header and optional actions.
class AppointmentPageShell extends StatelessWidget {
  const AppointmentPageShell({
    required this.child,
    this.title = 'Calendar',
    this.description = 'View and manage scheduled visits across your branches.',
    this.actions,
    super.key,
  });

  final Widget child;
  final String title;
  final String description;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppPageHeader(
              title: title,
              description: description,
              actions: actions,
            ),
            const SizedBox(height: AppSpacing.space6),
          ],
        );

        final hasBoundedHeight = constraints.maxHeight.isFinite;
        if (!hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [header, child],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
