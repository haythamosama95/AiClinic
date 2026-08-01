/// Workstation notification toggles (web `NotificationPrefs`).
class NotificationPreferences {
  const NotificationPreferences({
    this.appointmentReminders = true,
    this.billingAlerts = true,
    this.labResults = true,
    this.shiftHandoffs = false,
    this.productUpdates = false,
  });

  final bool appointmentReminders;
  final bool billingAlerts;
  final bool labResults;
  final bool shiftHandoffs;
  final bool productUpdates;

  static const defaults = NotificationPreferences();

  NotificationPreferences copyWith({
    bool? appointmentReminders,
    bool? billingAlerts,
    bool? labResults,
    bool? shiftHandoffs,
    bool? productUpdates,
  }) {
    return NotificationPreferences(
      appointmentReminders: appointmentReminders ?? this.appointmentReminders,
      billingAlerts: billingAlerts ?? this.billingAlerts,
      labResults: labResults ?? this.labResults,
      shiftHandoffs: shiftHandoffs ?? this.shiftHandoffs,
      productUpdates: productUpdates ?? this.productUpdates,
    );
  }

  NotificationPreferences merge(NotificationPreferences other) {
    return copyWith(
      appointmentReminders: other.appointmentReminders,
      billingAlerts: other.billingAlerts,
      labResults: other.labResults,
      shiftHandoffs: other.shiftHandoffs,
      productUpdates: other.productUpdates,
    );
  }

  Map<String, dynamic> toJson() => {
    'appointmentReminders': appointmentReminders,
    'billingAlerts': billingAlerts,
    'labResults': labResults,
    'shiftHandoffs': shiftHandoffs,
    'productUpdates': productUpdates,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      appointmentReminders: json['appointmentReminders'] as bool? ?? defaults.appointmentReminders,
      billingAlerts: json['billingAlerts'] as bool? ?? defaults.billingAlerts,
      labResults: json['labResults'] as bool? ?? defaults.labResults,
      shiftHandoffs: json['shiftHandoffs'] as bool? ?? defaults.shiftHandoffs,
      productUpdates: json['productUpdates'] as bool? ?? defaults.productUpdates,
    );
  }
}

enum NotificationPreferenceKey {
  appointmentReminders,
  billingAlerts,
  labResults,
  shiftHandoffs,
  productUpdates,
}
