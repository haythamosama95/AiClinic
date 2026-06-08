import 'package:ai_clinic/app/providers/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthNotifier.validateCredentials', () {
    test('rejects empty and whitespace username', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);

      expect(notifier.validateCredentials(username: '', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: '   ', password: 'x'), isFalse);
    });

    test('rejects invalid username format', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.validateCredentials(username: 'ab', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: 'bad@name', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: 'ab', password: 'x'), isFalse);
    });

    test('rejects empty password', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.validateCredentials(username: 'staff1', password: ''), isFalse);
    });

    test('accepts valid username and non-empty password', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.validateCredentials(username: '  staff1  ', password: 'pw'), isTrue);
    });
  });
}
