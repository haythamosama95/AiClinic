import 'dart:io';

/// Serializes boundary DB resets across parallel `flutter test` isolates.
class BoundaryProcessLock {
  static File get _lockFile => File('${Directory.systemTemp.path}/aiclinic_boundary_test.lock');

  static Future<T> synchronized<T>(Future<T> Function() action) async {
    RandomAccessFile? handle;
    for (var attempt = 0; attempt < 600; attempt++) {
      try {
        handle = _lockFile.openSync(mode: FileMode.write);
        handle.lockSync(FileLock.exclusive);
        break;
      } on IOException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    final locked = handle;
    if (locked == null) {
      throw StateError('Timed out waiting for boundary process lock.');
    }

    try {
      return await action();
    } finally {
      locked.unlockSync();
      locked.closeSync();
    }
  }
}
