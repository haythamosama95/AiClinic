import 'package:flutter_quill/flutter_quill.dart';

/// Whether a stored Quill delta JSON has no meaningful text content.
bool richDeltaIsEffectivelyEmpty(List<dynamic>? deltaJson) {
  if (deltaJson == null || deltaJson.isEmpty) {
    return true;
  }
  if (deltaJson.length == 1) {
    final first = deltaJson.first;
    if (first is Map && first['insert'] == '\n') {
      return true;
    }
  }
  return false;
}

/// Plain-text fallback for a stored Quill delta when editor flush callbacks are unavailable.
String plainTextFromRichDelta(List<dynamic>? deltaJson) {
  if (richDeltaIsEffectivelyEmpty(deltaJson)) {
    return '';
  }
  final raw = Document.fromJson(deltaJson!).toPlainText();
  if (raw.endsWith('\n')) {
    return raw.substring(0, raw.length - 1);
  }
  return raw;
}
