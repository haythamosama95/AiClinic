import 'package:flutter/foundation.dart';

/// Domain value for attachment bytes staged before upload.
@immutable
class VisitAttachmentPick {
  const VisitAttachmentPick({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;
}
