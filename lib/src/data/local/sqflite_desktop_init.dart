import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

void ensureSqfliteDesktopInitialized() {
  if (_initialized) {
    return;
  }
  if (Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _initialized = true;
}
