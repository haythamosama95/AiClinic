import 'package:ai_clinic/core/utils/copy_with_sentinel.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';
import 'package:ai_clinic/features/visits/domain/visit_row_parsing.dart';
import 'package:flutter/foundation.dart';

/// Visit attachment metadata row (`visit_attachments`, V1-5).
@immutable
class VisitAttachmentItem {
  const VisitAttachmentItem({
    required this.id,
    required this.fileType,
    this.label,
    required this.uploadedBy,
    this.uploadedByName,
    required this.sizeBytes,
    required this.createdAt,
    required this.canDownload,
  });

  final String id;
  final VisitAttachmentFileType fileType;
  final String? label;
  final String uploadedBy;
  final String? uploadedByName;
  final int sizeBytes;
  final DateTime createdAt;
  final bool canDownload;

  static VisitAttachmentItem? fromRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final fileType = VisitAttachmentFileType.tryParse(row['file_type']?.toString());
    final uploadedBy = row['uploaded_by']?.toString();
    final sizeBytes = optionalVisitInt(row['size_bytes']);
    final createdAt = parseVisitDateTime(row['created_at']);
    final canDownloadRaw = row['can_download'];

    if (id == null ||
        id.isEmpty ||
        fileType == null ||
        uploadedBy == null ||
        uploadedBy.isEmpty ||
        sizeBytes == null ||
        createdAt == null) {
      return null;
    }

    final canDownload = switch (canDownloadRaw) {
      bool value => value,
      _ => canDownloadRaw?.toString().trim().toLowerCase() == 'true',
    };

    return VisitAttachmentItem(
      id: id,
      fileType: fileType,
      label: optionalVisitString(row['label']),
      uploadedBy: uploadedBy,
      uploadedByName: optionalVisitString(row['uploaded_by_name']),
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      canDownload: canDownload,
    );
  }

  VisitAttachmentItem copyWith({
    String? id,
    VisitAttachmentFileType? fileType,
    Object? label = copyWithSentinel,
    String? uploadedBy,
    Object? uploadedByName = copyWithSentinel,
    int? sizeBytes,
    DateTime? createdAt,
    bool? canDownload,
  }) {
    return VisitAttachmentItem(
      id: id ?? this.id,
      fileType: fileType ?? this.fileType,
      label: identical(label, copyWithSentinel) ? this.label : label as String?,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      uploadedByName: identical(uploadedByName, copyWithSentinel) ? this.uploadedByName : uploadedByName as String?,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      canDownload: canDownload ?? this.canDownload,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VisitAttachmentItem &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            fileType == other.fileType &&
            label == other.label &&
            uploadedBy == other.uploadedBy &&
            uploadedByName == other.uploadedByName &&
            sizeBytes == other.sizeBytes &&
            createdAt == other.createdAt &&
            canDownload == other.canDownload;
  }

  @override
  int get hashCode => Object.hash(id, fileType, label, uploadedBy, uploadedByName, sizeBytes, createdAt, canDownload);
}
