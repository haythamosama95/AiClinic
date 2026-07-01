import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:ai_clinic/features/visits/domain/visit_attachment_file_type.dart';

/// Failure when a downloaded attachment cannot be opened locally.
class VisitAttachmentOpenException implements Exception {
  const VisitAttachmentOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes [bytes] to a temporary file and opens it with the platform default app.
Future<void> openVisitAttachmentBytes({
  required Uint8List bytes,
  required VisitAttachmentFileType fileType,
  String? preferredName,
}) async {
  final directory = await getTemporaryDirectory();
  final extension = _openExtension(fileType);
  final baseName = _sanitizeFilename(preferredName) ?? 'attachment';
  final filename = baseName.toLowerCase().endsWith('.$extension') ? baseName : '$baseName.$extension';
  final path = '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$filename';

  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);

  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    final message = result.message.trim();
    throw VisitAttachmentOpenException(
      message.isNotEmpty ? message : 'Could not open the attachment with the default application.',
    );
  }
}

String _openExtension(VisitAttachmentFileType fileType) {
  return switch (fileType) {
    VisitAttachmentFileType.pdf => 'pdf',
    VisitAttachmentFileType.docx => 'docx',
    VisitAttachmentFileType.jpeg => 'jpg',
    VisitAttachmentFileType.png => 'png',
  };
}

String? _sanitizeFilename(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_');
}
