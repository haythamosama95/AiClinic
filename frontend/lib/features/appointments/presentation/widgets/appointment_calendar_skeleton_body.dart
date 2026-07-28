import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Skeleton placeholder shown while the calendar loads.
class AppointmentCalendarSkeletonBody extends StatelessWidget {
  const AppointmentCalendarSkeletonBody({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonizerZone(
      child: SizedBox.expand(
        child: Bone(borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl))),
      ),
    );
  }
}
