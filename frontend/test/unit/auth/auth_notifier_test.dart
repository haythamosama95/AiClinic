import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  AuthNotifier readNotifier(ProviderContainer container) => container.read(authNotifierProvider.notifier);

  group('AuthNotifier.validateCredentials', () {
    test('rejects empty and whitespace username', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: '', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: '   ', password: 'x'), isFalse);
    });

    test('rejects invalid username format', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: 'ab', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: 'bad@name', password: 'x'), isFalse);
    });

    test('rejects username with leading or trailing underscore or hyphen', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: '_staff1', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: 'staff1_', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: '-staff1', password: 'x'), isFalse);
      expect(notifier.validateCredentials(username: 'staff1-', password: 'x'), isFalse);
    });

    test('rejects username longer than 32 characters', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: 'a' * 33, password: 'x'), isFalse);
    });

    test('accepts username at minimum and maximum length', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: 'abc', password: 'x'), isTrue);
      expect(notifier.validateCredentials(username: 'a' * 32, password: 'x'), isTrue);
    });

    test('accepts uppercase username that normalizes to valid', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: 'STAFF1', password: 'x'), isTrue);
    });

    test('rejects empty password', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: 'staff1', password: ''), isFalse);
    });

    test('accepts whitespace-only password because only emptiness is rejected', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: 'staff1', password: ' '), isTrue);
    });

    test('accepts valid username and non-empty password', () {
      final notifier = readNotifier(createContainer());

      expect(notifier.validateCredentials(username: '  staff1  ', password: 'pw'), isTrue);
    });

    test('does not mutate AuthUiState', () {
      final container = createContainer();
      final notifier = readNotifier(container);
      const initialState = AuthUiState();

      expect(container.read(authNotifierProvider), initialState);

      notifier.validateCredentials(username: 'ab', password: '');
      notifier.validateCredentials(username: 'staff1', password: 'pw');

      expect(container.read(authNotifierProvider), initialState);
    });
  });
}
