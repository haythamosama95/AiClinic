import 'package:ai_clinic/core/ui/rich_text/rich_text_delta_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// Quill delta JSON for formatted text without a synced plain-text field (EDGE-002).
List<dynamic> richDeltaBoldText(String text) => [
  {'insert': text, 'attributes': const {'bold': true}},
  {'insert': '\n'},
];

/// Default empty Quill document after all text is removed (EDGE-007).
const List<dynamic> richDeltaEffectivelyEmpty = [
  {'insert': '\n'},
];

void main() {
  group('plainTextFromRichDelta', () {
    test('returns empty string for null delta', () {
      expect(plainTextFromRichDelta(null), '');
    });

    test('returns empty string for effectively empty delta', () {
      expect(plainTextFromRichDelta(richDeltaEffectivelyEmpty), '');
    });

    test('extracts plain text from formatted delta', () {
      expect(plainTextFromRichDelta(richDeltaBoldText('Headache')), 'Headache');
    });

    test('strips trailing newline from Quill document', () {
      const deltaWithTrailingNewline = [
        {'insert': 'Line one\nLine two'},
        {'insert': '\n'},
      ];
      expect(plainTextFromRichDelta(deltaWithTrailingNewline), 'Line one\nLine two');
    });
  });

  group('richDeltaIsEffectivelyEmpty', () {
    test('treats null and empty list as empty', () {
      expect(richDeltaIsEffectivelyEmpty(null), isTrue);
      expect(richDeltaIsEffectivelyEmpty(const []), isTrue);
    });

    test('treats lone newline insert without attributes as empty (EDGE-007)', () {
      expect(richDeltaIsEffectivelyEmpty(richDeltaEffectivelyEmpty), isTrue);
    });

    test('treats lone formatted newline insert as empty', () {
      const formattedBlankLine = [
        {'insert': '\n', 'attributes': {'header': 1}},
      ];
      expect(richDeltaIsEffectivelyEmpty(formattedBlankLine), isTrue);
    });

    test('treats formatted text delta as non-empty', () {
      expect(richDeltaIsEffectivelyEmpty(richDeltaBoldText('Headache')), isFalse);
    });
  });
}
