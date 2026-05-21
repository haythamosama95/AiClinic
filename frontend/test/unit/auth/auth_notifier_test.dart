import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthNotifier.validateCredentials', () {
    test('rejects empty and whitespace email', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);

      expect(notifier.validateCredentials(email: '', password: 'x'), isFalse);
      expect(notifier.validateCredentials(email: '   ', password: 'x'), isFalse);
    });

    test('rejects email without @', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.validateCredentials(email: 'notanemail', password: 'x'), isFalse);
    });

    test('rejects empty password', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.validateCredentials(email: 'a@b.co', password: ''), isFalse);
    });

    test('accepts trimmed valid email and non-empty password', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(authNotifierProvider.notifier);
      expect(notifier.validateCredentials(email: '  staff@clinic.test  ', password: 'pw'), isTrue);
    });
  });
}
