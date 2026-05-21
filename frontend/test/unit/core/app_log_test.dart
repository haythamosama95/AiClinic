import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AppLog.debugClearRecords);

  test('redacts password email and jwt-like tokens from messages', () {
    AppLog.warning('auth.sign_in.failed password=secret user@test.com Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig');

    expect(AppLog.debugRecords, isNotEmpty);
    final message = AppLog.debugRecords.last.message;
    expect(message, isNot(contains('secret')));
    expect(message, isNot(contains('user@test.com')));
    expect(message, isNot(contains('eyJhbGci')));
    expect(message, contains('[redacted]'));
  });

  test('context failure uses reason category without credentials', () {
    AppLog.warning('auth.session.context_failed reason=missing_staff_role');
    expect(AppLog.debugRecords.last.message, contains('reason=missing_staff_role'));
    expect(AppLog.debugRecords.last.level, 'warning');
  });

  test('info does not use warning level', () {
    AppLog.info('supabase.bootstrap.ready');
    expect(AppLog.debugRecords.last.level, 'info');
  });

  test('fine is recorded only in debug mode', () {
    AppLog.fine('auth.route.redirect from=/home to=/login');
    if (kDebugMode) {
      expect(AppLog.debugRecords.last.level, 'fine');
    } else {
      expect(AppLog.debugRecords, isEmpty);
    }
  });
}
