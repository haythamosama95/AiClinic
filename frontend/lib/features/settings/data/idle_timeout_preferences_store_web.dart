import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/features/settings/domain/idle_timeout_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _idleTimeoutKey = 'idle_timeout_minutes';

Future<Duration> loadIdleDuration() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt(_idleTimeoutKey);
    if (minutes == null) {
      return IdleTimeoutConfig.defaultDuration;
    }

    return IdleTimeoutConfig.clampMinutes(minutes);
  } on Exception catch (error) {
    AppLog.warning('settings.idle_timeout.load_failed reason=${error.runtimeType}');
    return IdleTimeoutConfig.defaultDuration;
  }
}

Future<void> saveIdleDuration(Duration duration) async {
  final clamped = IdleTimeoutConfig.clampDuration(duration);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_idleTimeoutKey, clamped.inMinutes);
  AppLog.fine('settings.idle_timeout.saved minutes=${clamped.inMinutes}');
}
