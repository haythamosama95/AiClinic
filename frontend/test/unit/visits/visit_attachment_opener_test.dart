import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_attachment_opener.dart';

void main() {
  group('visitMessageForOpenError', () {
    test('returns opener message for VisitAttachmentOpenException', () {
      expect(
        visitMessageForOpenError(const VisitAttachmentOpenException('No application found.')),
        'No application found.',
      );
    });
  });
}
