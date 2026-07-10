import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

class BackupService {
  Future<String> exportarBackup() async {
    final dbPath = await getDatabasesPath();
    final origen = File(p.join(dbPath, 'eltata.db'));
    if (!await origen.exists()) {
      throw Exception('Base de datos no encontrada');
    }

    final docs = await getApplicationDocumentsDirectory();
    final fecha = DateTime.now();
    final nombre =
        'eltata_backup_${fecha.year}${fecha.month.toString().padLeft(2, '0')}${fecha.day.toString().padLeft(2, '0')}.db';
    final destino = File(p.join(docs.path, nombre));
    await origen.copy(destino.path);
    return destino.path;
  }

  Future<void> compartirBackup() async {
    final path = await exportarBackup();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Backup EL TATA Manager',
      ),
    );
  }

  Future<bool> restaurarBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return false;
    }

    await DatabaseHelper.instance.cerrar();

    final origen = File(result.files.first.path!);
    final dbPath = await getDatabasesPath();
    final destino = File(p.join(dbPath, 'eltata.db'));
    if (await destino.exists()) {
      await destino.delete();
    }
    await origen.copy(destino.path);
    return true;
  }
}
