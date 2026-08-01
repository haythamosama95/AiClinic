import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

/// Bridges [AppointmentDetail] to queue/calendar transition helpers that expect [AppointmentListItem].
extension AppointmentDetailListItem on AppointmentDetail {
  AppointmentListItem toListItem() {
    return AppointmentListItem(
      id: id,
      patientId: patientId,
      patientName: patientName,
      doctorId: doctorId,
      doctorName: doctorName,
      startTime: startTime,
      endTime: endTime,
      type: type,
      status: status,
      updatedAt: updatedAt,
    );
  }
}
