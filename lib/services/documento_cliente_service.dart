import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/media_sync_service.dart';
import '../database/database_helper.dart';
import '../models/documento_cliente.dart';
import 'auth_service.dart';

/// Archiva PDFs por cliente (local + Firebase Storage/Firestore).
class DocumentoClienteService {
  DocumentoClienteService._();
  static final DocumentoClienteService instance = DocumentoClienteService._();

  final _db = DatabaseHelper.instance;

  Future<DocumentoCliente?> archivarPdf({
    required File archivo,
    required String tipo,
    required String numero,
    required String clienteNombre,
    int? clienteId,
    String? clienteSyncId,
  }) async {
    try {
      var syncId = (clienteSyncId ?? '').trim();
      if (syncId.isEmpty && clienteId != null) {
        syncId = await FirestoreSyncService.instance
            .asegurarSyncIdCliente(clienteId);
      }
      if (syncId.isEmpty) {
        syncId = 'sin_cliente';
      }

      final id = const Uuid().v4();
      final nombreArchivo =
          '${tipo}_${numero.isNotEmpty ? numero : id}_${DateTime.now().millisecondsSinceEpoch}.pdf'
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

      final url = await MediaSyncService.instance.subirPdfCliente(
            clienteSyncId: syncId,
            nombreArchivo: nombreArchivo,
            file: archivo,
          ) ??
          '';

      final doc = DocumentoCliente(
        id: id,
        clienteSyncId: syncId,
        clienteId: clienteId,
        clienteNombre: clienteNombre,
        tipo: tipo,
        numero: numero,
        nombreArchivo: nombreArchivo,
        url: url,
        localPath: archivo.path,
        creadoPor: AuthService.instance.currentUser?.usuario ?? 'sistema',
        fecha: DateTime.now(),
      );

      final db = await _db.database;
      await db.insert('documentos_cliente', doc.toMap());
      await FirestoreSyncService.instance.subirDocumento(doc);
      DataRefreshHub.instance.notifyTodo();
      return doc;
    } catch (e) {
      debugPrint('Archivar PDF: $e');
      return null;
    }
  }

  Future<List<DocumentoCliente>> listar({String? clienteSyncId}) async {
    final db = await _db.database;
    final rows = clienteSyncId == null || clienteSyncId.isEmpty
        ? await db.query(
            'documentos_cliente',
            orderBy: 'datetime(fecha) DESC',
          )
        : await db.query(
            'documentos_cliente',
            where: 'clienteSyncId = ?',
            whereArgs: [clienteSyncId],
            orderBy: 'datetime(fecha) DESC',
          );
    return rows.map(DocumentoCliente.fromMap).toList();
  }

  Future<Map<String, List<DocumentoCliente>>> listarAgrupadoPorCliente() async {
    final todos = await listar();
    final map = <String, List<DocumentoCliente>>{};
    for (final d in todos) {
      final key = d.clienteNombre.isNotEmpty
          ? d.clienteNombre
          : (d.clienteSyncId.isNotEmpty ? d.clienteSyncId : 'Sin cliente');
      map.putIfAbsent(key, () => []).add(d);
    }
    return map;
  }
}
