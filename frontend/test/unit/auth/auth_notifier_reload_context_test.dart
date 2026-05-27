import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  setUp(() {
    _ReloadTrackingNotifier.reloadCount = 0;
  });

  test('AuthNotifier.reloadContext delegates to AuthSessionNotifier.reloadContext', () async {
    final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(_ReloadTrackingNotifier.new)]);
    addTearDown(container.dispose);

    final notifier = container.read(authNotifierProvider.notifier);
    await notifier.reloadContext();

    expect(container.read(_reloadCountProvider), 1);
  });
}

final _reloadCountProvider = Provider<int>((ref) => _ReloadTrackingNotifier.reloadCount);

class _ReloadTrackingNotifier extends TestAuthSessionNotifier {
  static int reloadCount = 0;

  @override
  Future<void> reloadContext() async {
    reloadCount++;
  }
}
