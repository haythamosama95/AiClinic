import 'dart:typed_data';

import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';

/// Visit attachment seed specification for dev clinic dummy data.
class DevClinicVisitAttachmentSeed {
  const DevClinicVisitAttachmentSeed({required this.fileType, required this.filename, required this.label});

  final VisitAttachmentFileType fileType;
  final String filename;
  final String? label;
}

/// Deterministic visit attachment combinations for dev clinic seeding.
abstract final class DevClinicSeedAttachments {
  /// All single-attachment combinations: 4 file types × with/without label.
  static const singleAttachmentCombos = 8;

  /// Whether this visit should receive any attachments.
  static bool shouldSeedAttachments(int seedKey) => seedKey % 11 != 10;

  /// Whether this visit receives two attachments (multi-file case).
  static bool shouldSeedMultipleAttachments(int seedKey) => seedKey % 7 == 0;

  /// Attachments to upload for a seeded visit.
  static List<DevClinicVisitAttachmentSeed> attachmentsFor({
    required int seedKey,
    required String branchCode,
    required int patientIndex,
  }) {
    if (!shouldSeedAttachments(seedKey)) {
      return const [];
    }

    if (shouldSeedMultipleAttachments(seedKey)) {
      final firstCombo = (seedKey ~/ 7) % singleAttachmentCombos;
      final secondCombo = (firstCombo + 1) % singleAttachmentCombos;
      return [
        _attachmentForCombo(combo: firstCombo, branchCode: branchCode, patientIndex: patientIndex, suffix: 'a'),
        _attachmentForCombo(combo: secondCombo, branchCode: branchCode, patientIndex: patientIndex, suffix: 'b'),
      ];
    }

    return [
      _attachmentForCombo(
        combo: seedKey % singleAttachmentCombos,
        branchCode: branchCode,
        patientIndex: patientIndex,
        suffix: '',
      ),
    ];
  }

  static DevClinicVisitAttachmentSeed _attachmentForCombo({
    required int combo,
    required String branchCode,
    required int patientIndex,
    required String suffix,
  }) {
    final fileType = VisitAttachmentFileType.values[combo % VisitAttachmentFileType.values.length];
    final hasLabel = combo >= VisitAttachmentFileType.values.length;
    final extension = switch (fileType) {
      VisitAttachmentFileType.pdf => 'pdf',
      VisitAttachmentFileType.docx => 'docx',
      VisitAttachmentFileType.jpeg => 'jpg',
      VisitAttachmentFileType.png => 'png',
    };

    return DevClinicVisitAttachmentSeed(
      fileType: fileType,
      filename: 'dev-seed-$branchCode-p$patientIndex$suffix.$extension',
      label: hasLabel ? 'Dev seed ${fileType.label} — $branchCode #$patientIndex$suffix' : null,
    );
  }

  /// Minimal non-empty bytes for storage upload (content is not validated server-side).
  static Uint8List dummyBytesFor(VisitAttachmentFileType fileType) {
    return switch (fileType) {
      VisitAttachmentFileType.pdf => Uint8List.fromList('%PDF-1.0 dev seed'.codeUnits),
      VisitAttachmentFileType.docx => Uint8List.fromList('PK dev seed docx'.codeUnits),
      VisitAttachmentFileType.jpeg => Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
      ]),
      VisitAttachmentFileType.png => Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
      ]),
    };
  }
}
