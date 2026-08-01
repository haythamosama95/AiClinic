<<<<<<< HEAD
=======
// ignore_for_file: avoid_print

>>>>>>> master
import 'package:intl/intl.dart';

void main() {
  final d = DateTime(2026, 7, 4);
  try {
    print('empty: [${DateFormat('').format(d)}]');
  } catch (e) {
    print('empty err: $e');
  }
  print('d EEE: ${DateFormat('d EEE').format(d)}');
}
