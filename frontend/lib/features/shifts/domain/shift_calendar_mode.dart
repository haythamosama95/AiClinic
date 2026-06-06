/// Calendar presentation mode for branch shift views (V1-7).
enum ShiftCalendarMode {
  week,
  month;

  String get label => switch (this) {
    ShiftCalendarMode.week => 'Week',
    ShiftCalendarMode.month => 'Month',
  };
}
