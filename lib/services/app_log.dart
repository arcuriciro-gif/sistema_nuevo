import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> appendAppLog(String message) async {
  final line = '${DateTime.now().toIso8601String()} $message\n';
  debugPrint(message);
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tata_manager_error.log'));
    await file.writeAsString(line, mode: FileMode.append);
  } catch (_) {}
  try {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final file = File(p.join(exeDir.path, 'tata_manager_error.log'));
    await file.writeAsString(line, mode: FileMode.append);
  } catch (_) {}
}
