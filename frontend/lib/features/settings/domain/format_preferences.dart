/// Workstation date display format (web `DateFormat`).
enum AppDateFormat {
  dmy('dmy', 'DD/MM/YYYY'),
  mdy('mdy', 'MM/DD/YYYY');

  const AppDateFormat(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static const defaultValue = AppDateFormat.dmy;

  static AppDateFormat? tryParse(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final value in AppDateFormat.values) {
      if (value.storageValue == raw) {
        return value;
      }
    }
    return null;
  }
}

/// Workstation clock display format (web `TimeFormat`).
enum AppTimeFormat {
  h12('12h', '12-hour (3:30 PM)'),
  h24('24h', '24-hour (15:30)');

  const AppTimeFormat(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static const defaultValue = AppTimeFormat.h12;

  static AppTimeFormat? tryParse(String? raw) {
    if (raw == null) {
      return null;
    }
    for (final value in AppTimeFormat.values) {
      if (value.storageValue == raw) {
        return value;
      }
    }
    return null;
  }
}
