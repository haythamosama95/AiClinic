import 'package:ai_clinic/core/auth/idle_timeout_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IdleTimeoutService', () {
    test('does not fire before idle duration elapses', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(
          idleDuration: const Duration(minutes: 15),
          onIdleTimeout: () => fired = true,
        );
        addTearDown(service.dispose);

        service.enable();
        async.elapse(const Duration(minutes: 14, seconds: 59));
        expect(fired, isFalse);
        expect(service.isEnabled, isTrue);
      });
    });

    test('fires exactly once after full idle duration', () {
      FakeAsync().run((async) {
        var fireCount = 0;
        final service = IdleTimeoutService(idleDuration: const Duration(minutes: 15), onIdleTimeout: () => fireCount++);
        addTearDown(service.dispose);

        service.enable();
        async.elapse(const Duration(minutes: 15));
        expect(fireCount, 1);
        expect(service.isEnabled, isFalse);

        async.elapse(const Duration(minutes: 15));
        expect(fireCount, 1);
      });
    });

    test('recordActivity resets the idle deadline', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(
          idleDuration: const Duration(minutes: 15),
          onIdleTimeout: () => fired = true,
        );
        addTearDown(service.dispose);

        service.enable();
        async.elapse(const Duration(minutes: 14));
        service.recordActivity();
        async.elapse(const Duration(minutes: 14));
        expect(fired, isFalse);

        async.elapse(const Duration(minutes: 1));
        expect(fired, isTrue);
      });
    });

    test('rapid activity bursts keep pushing timeout forward', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(
          idleDuration: const Duration(seconds: 30),
          onIdleTimeout: () => fired = true,
        );
        addTearDown(service.dispose);

        service.enable();
        for (var i = 0; i < 20; i++) {
          async.elapse(const Duration(seconds: 25));
          service.recordActivity();
        }
        async.elapse(const Duration(seconds: 29));
        expect(fired, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(fired, isTrue);
      });
    });

    test('disable prevents timeout while idle period passes', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(
          idleDuration: const Duration(seconds: 10),
          onIdleTimeout: () => fired = true,
        );
        addTearDown(service.dispose);

        service.enable();
        async.elapse(const Duration(seconds: 5));
        service.disable();
        async.elapse(const Duration(hours: 1));
        expect(fired, isFalse);
      });
    });

    test('enable without resetTimer keeps the existing deadline', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(
          idleDuration: const Duration(seconds: 20),
          onIdleTimeout: () => fired = true,
        );
        addTearDown(service.dispose);

        service.enable();
        async.elapse(const Duration(seconds: 15));
        service.enable(resetTimer: false);
        async.elapse(const Duration(seconds: 5));
        expect(fired, isTrue);
      });
    });

    test('recordActivity while disabled is a no-op', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(idleDuration: const Duration(seconds: 5), onIdleTimeout: () => fired = true);
        addTearDown(service.dispose);

        service.recordActivity();
        async.elapse(const Duration(seconds: 10));
        expect(fired, isFalse);
      });
    });

    test('recordActivity before enable does not schedule timeout', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(idleDuration: const Duration(seconds: 5), onIdleTimeout: () => fired = true);
        addTearDown(service.dispose);

        service.recordActivity();
        service.enable();
        async.elapse(const Duration(seconds: 5));
        expect(fired, isTrue);
      });
    });

    test('dispose cancels a pending timeout', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(
          idleDuration: const Duration(seconds: 30),
          onIdleTimeout: () => fired = true,
        );

        service.enable();
        async.elapse(const Duration(seconds: 20));
        service.dispose();
        async.elapse(const Duration(hours: 2));
        expect(fired, isFalse);
      });
    });

    test('dispose then recordActivity does not throw or fire', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(idleDuration: const Duration(seconds: 1), onIdleTimeout: () => fired = true);

        service.enable();
        service.dispose();
        expect(() => service.recordActivity(), returnsNormally);
        async.elapse(const Duration(minutes: 5));
        expect(fired, isFalse);
      });
    });

    test('very short idle duration fires quickly for test harnesses', () {
      FakeAsync().run((async) {
        var fired = false;
        final service = IdleTimeoutService(idleDuration: Duration.zero, onIdleTimeout: () => fired = true);
        addTearDown(service.dispose);

        service.enable();
        async.elapse(Duration.zero);
        expect(fired, isTrue);
      });
    });

    test('default duration matches FR-005a policy', () {
      expect(kIdleTimeoutDuration, const Duration(minutes: 15));
    });

    test('idle and session-ended messages are user-facing and distinct', () {
      expect(kIdleTimeoutSignOutMessage, contains('inactivity'));
      expect(kSessionEndedMessage, contains('session'));
      expect(kIdleTimeoutSignOutMessage, isNot(equals(kSessionEndedMessage)));
    });
  });
}
