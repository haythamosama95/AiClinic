import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Structured plan-phase outputs (1:1 with visit, 014 US7).
@immutable
class VisitPlanDetails {
  const VisitPlanDetails({
    this.followUpInterval,
    this.followUpDate,
    this.patientInstructions,
    this.referral,
    this.certificateStartDate,
    this.certificateEndDate,
    this.certificateReason,
    this.updatedAt,
  });

  final String? followUpInterval;
  final DateTime? followUpDate;
  final String? patientInstructions;
  final String? referral;
  final DateTime? certificateStartDate;
  final DateTime? certificateEndDate;
  final String? certificateReason;
  final DateTime? updatedAt;

  bool get isEmpty =>
      (followUpInterval == null || followUpInterval!.trim().isEmpty) &&
      followUpDate == null &&
      (patientInstructions == null || patientInstructions!.trim().isEmpty) &&
      (referral == null || referral!.trim().isEmpty) &&
      certificateStartDate == null &&
      certificateEndDate == null &&
      (certificateReason == null || certificateReason!.trim().isEmpty);

  static VisitPlanDetails? fromRow(Map<String, dynamic>? row) {
    if (row == null || row.isEmpty) {
      return null;
    }
    return VisitPlanDetails(
      followUpInterval: optionalVisitString(row['follow_up_interval']),
      followUpDate: parseVisitDate(row['follow_up_date']),
      patientInstructions: optionalVisitString(row['patient_instructions']),
      referral: optionalVisitString(row['referral']),
      certificateStartDate: parseVisitDate(row['certificate_start_date']),
      certificateEndDate: parseVisitDate(row['certificate_end_date']),
      certificateReason: optionalVisitString(row['certificate_reason']),
      updatedAt: parseVisitDateTime(row['updated_at']),
    );
  }

  VisitPlanDetails copyWith({
    Object? followUpInterval = copyWithSentinel,
    Object? followUpDate = copyWithSentinel,
    Object? patientInstructions = copyWithSentinel,
    Object? referral = copyWithSentinel,
    Object? certificateStartDate = copyWithSentinel,
    Object? certificateEndDate = copyWithSentinel,
    Object? certificateReason = copyWithSentinel,
    Object? updatedAt = copyWithSentinel,
  }) {
    return VisitPlanDetails(
      followUpInterval: identical(followUpInterval, copyWithSentinel)
          ? this.followUpInterval
          : followUpInterval as String?,
      followUpDate: identical(followUpDate, copyWithSentinel) ? this.followUpDate : followUpDate as DateTime?,
      patientInstructions: identical(patientInstructions, copyWithSentinel)
          ? this.patientInstructions
          : patientInstructions as String?,
      referral: identical(referral, copyWithSentinel) ? this.referral : referral as String?,
      certificateStartDate: identical(certificateStartDate, copyWithSentinel)
          ? this.certificateStartDate
          : certificateStartDate as DateTime?,
      certificateEndDate: identical(certificateEndDate, copyWithSentinel)
          ? this.certificateEndDate
          : certificateEndDate as DateTime?,
      certificateReason: identical(certificateReason, copyWithSentinel)
          ? this.certificateReason
          : certificateReason as String?,
      updatedAt: identical(updatedAt, copyWithSentinel) ? this.updatedAt : updatedAt as DateTime?,
    );
  }
}
