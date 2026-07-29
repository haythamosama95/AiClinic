import 'package:ai_clinic/features/auth/presentation/providers/clinic_setup_welcome_shown_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer createContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  group('clinicSetupWelcomeShownProvider', () {
    test('initial state is false for a fresh staffMemberId', () {
      final container = createContainer();

      expect(container.read(clinicSetupWelcomeShownProvider('staff-a')), isFalse);
    });

    test('tryMarkShown returns true on first call and flips state to true', () {
      final container = createContainer();
      final provider = clinicSetupWelcomeShownProvider('staff-a');
      final notifier = container.read(provider.notifier);

      expect(notifier.tryMarkShown(), isTrue);
      expect(container.read(provider), isTrue);
    });

    test('second tryMarkShown returns false and leaves state true', () {
      final container = createContainer();
      final provider = clinicSetupWelcomeShownProvider('staff-a');
      final notifier = container.read(provider.notifier);

      expect(notifier.tryMarkShown(), isTrue);
      expect(notifier.tryMarkShown(), isFalse);
      expect(container.read(provider), isTrue);
    });

    test('family isolation keeps independent state per staffMemberId', () {
      final container = createContainer();
      final providerA = clinicSetupWelcomeShownProvider('staff-a');
      final providerB = clinicSetupWelcomeShownProvider('staff-b');

      expect(container.read(providerA.notifier).tryMarkShown(), isTrue);

      expect(container.read(providerA), isTrue);
      expect(container.read(providerB), isFalse);
    });

    test('same staffMemberId returns the same notifier within one container', () {
      final container = createContainer();
      final provider = clinicSetupWelcomeShownProvider('staff-a');

      final notifierA = container.read(provider.notifier);
      final notifierB = container.read(provider.notifier);

      expect(identical(notifierA, notifierB), isTrue);
      expect(container.read(provider), isFalse);
    });

    test('invalidate resets state so tryMarkShown returns true again', () {
      final container = createContainer();
      final provider = clinicSetupWelcomeShownProvider('staff-a');
      final notifier = container.read(provider.notifier);

      expect(notifier.tryMarkShown(), isTrue);
      expect(container.read(provider), isTrue);

      container.invalidate(provider);

      expect(container.read(provider), isFalse);
      expect(container.read(provider.notifier).tryMarkShown(), isTrue);
    });

    test('handles empty-string and unusual staffMemberId values without throwing', () {
      final container = createContainer();
      final emptyProvider = clinicSetupWelcomeShownProvider('');
      final unusualProvider = clinicSetupWelcomeShownProvider('staff/with spaces');

      expect(() => container.read(emptyProvider.notifier).tryMarkShown(), returnsNormally);
      expect(() => container.read(unusualProvider.notifier).tryMarkShown(), returnsNormally);
      expect(container.read(emptyProvider), isTrue);
      expect(container.read(unusualProvider), isTrue);
    });

    test('autoDispose creates a fresh notifier after the last listener closes', () {
      final container = createContainer();
      const staffMemberId = 'staff-a';
      final provider = clinicSetupWelcomeShownProvider(staffMemberId);

      final subscription = container.listen(provider, (_, _) {});
      expect(container.read(provider.notifier).tryMarkShown(), isTrue);
      expect(container.read(provider), isTrue);

      subscription.close();

      expect(container.read(provider), isFalse);
      expect(container.read(provider.notifier).tryMarkShown(), isTrue);
    });
  });
}
