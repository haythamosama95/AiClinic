/// Attachment file type aligned with PostgreSQL `visit_attachment_file_type` enum (V1-5).
enum VisitAttachmentFileType {
  pdf,
  docx,
  jpeg,
  png;

  static VisitAttachmentFileType? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return switch (normalized) {
      'pdf' => VisitAttachmentFileType.pdf,
      'docx' => VisitAttachmentFileType.docx,
      'jpeg' => VisitAttachmentFileType.jpeg,
      'png' => VisitAttachmentFileType.png,
      _ => null,
    };
  }

  String get wireValue => switch (this) {
    VisitAttachmentFileType.pdf => 'pdf',
    VisitAttachmentFileType.docx => 'docx',
    VisitAttachmentFileType.jpeg => 'jpeg',
    VisitAttachmentFileType.png => 'png',
  };

  String get label => switch (this) {
    VisitAttachmentFileType.pdf => 'PDF',
    VisitAttachmentFileType.docx => 'DOCX',
    VisitAttachmentFileType.jpeg => 'JPEG',
    VisitAttachmentFileType.png => 'PNG',
  };
}
