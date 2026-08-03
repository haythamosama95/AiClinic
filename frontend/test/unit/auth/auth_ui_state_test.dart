import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthUiState', () {
    test('default constructor values', () {
      const state = AuthUiState();

      expect(state.isSubmitting, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.isInfoMessage, isFalse);
    });

    test('copyWith with no args preserves all fields', () {
      const state = AuthUiState(isSubmitting: true, errorMessage: 'oops', isInfoMessage: true);

      expect(state.copyWith(), state);
    });

    test('copyWith updates each field independently', () {
      const state = AuthUiState();

      expect(state.copyWith(isSubmitting: true).isSubmitting, isTrue);
      expect(state.copyWith(errorMessage: 'error').errorMessage, 'error');
      expect(state.copyWith(isInfoMessage: true).isInfoMessage, isTrue);
    });

    group('copyWith errorMessage sentinel', () {
      test('omitting errorMessage preserves existing non-null message', () {
        const state = AuthUiState(errorMessage: 'keep me');

        expect(state.copyWith(isSubmitting: true).errorMessage, 'keep me');
      });

      test('omitting errorMessage preserves null', () {
        const state = AuthUiState();

        expect(state.copyWith(isSubmitting: true).errorMessage, isNull);
      });

      test('explicit null clears existing non-null message', () {
        const state = AuthUiState(errorMessage: 'clear me');

        expect(state.copyWith(errorMessage: null).errorMessage, isNull);
      });

      test('explicit null on null message stays null', () {
        const state = AuthUiState();

        expect(state.copyWith(errorMessage: null).errorMessage, isNull);
      });
    });

    test('copyWith(isSubmitting: true) preserves an existing error', () {
      const state = AuthUiState(errorMessage: 'bad password');

      final next = state.copyWith(isSubmitting: true);

      expect(next.isSubmitting, isTrue);
      expect(next.errorMessage, 'bad password');
    });
  });
}
