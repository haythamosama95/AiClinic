import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:flutter/foundation.dart';

/// Visit attachment surfaced on the patient detail documents panel.
@immutable
class PatientVisitDocument {
  const PatientVisitDocument({required this.visitId, required this.visitDate, required this.attachment});

  final String visitId;
  final DateTime visitDate;
  final VisitAttachmentItem attachment;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PatientVisitDocument &&
            runtimeType == other.runtimeType &&
            visitId == other.visitId &&
            visitDate == other.visitDate &&
            attachment == other.attachment;
  }

  @override
  int get hashCode => Object.hash(visitId, visitDate, attachment);
}
