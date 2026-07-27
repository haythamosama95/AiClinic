import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Badge label and color for visit status chips across patient and visit surfaces.
abstract final class VisitStatusPresentation {
  static String badgeLabel(VisitStatus status) => status.label;

  static BadgeColor badgeColor(VisitStatus status) {
    return switch (status) {
      VisitStatus.inProgress => BadgeColor.info,
      VisitStatus.completed => BadgeColor.success,
    };
  }
}
