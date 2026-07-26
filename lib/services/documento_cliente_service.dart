import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/config/platform_capabilities.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/sync/cloud_sync_throttle.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/media_sync_service.dart';
import '../core/sync/sync_background.dart';
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
      // Windows: no tocar Firebase aquí (asegurarSyncId pega Firestore).
      if (syncId.isEmpty &&
          clienteId != null &&
          !PlatformCapabilities.isWindowsDesktop) {
        try {
          syncId = await FirestoreSyncService.instance
              .asegurarSyncIdCliente(clienteId)
              .timeout(const Duration(seconds: 3), onTimeout: () => '');
        } catch (_) {
          syncId = '';
        }
      }
      if (syncId.isEmpty) {
        syncId = 'sin_cliente';
      }

      final id = const Uuid().v4();
      final nombreArchivo =
          '${tipo}_${numero.isNotEmpty ? numero : id}_${DateTime.now().millisecondsSinceEpoch}.pdf'
              .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

      // Local primero: no bloquear venta en modo avión.
      final doc = DocumentoCliente(
        id: id,
        clienteSyncId: syncId,
        clienteId: clienteId,
        clienteNombre: clienteNombre,
        tipo: tipo,
        numero: numero,
        nombreArchivo: nombreArchivo,
        url: '',
        localPath: archivo.path,
        creadoPor: AuthService.instance.currentUser?.usuario ?? 'sistema',
        fecha: DateTime.now(),
      );

      final db = await _db.database;
      await db.insert('documentos_cliente', doc.toMap());
      DataRefreshHub.instance.notifyTodo();

      // Nube en background (Storage + Firestore). Windows: mucho más tarde
      // y por throttle (si no, venta rápida + Storage tumba el .exe).
      Future<void> subirNube() async {
        var sid = syncId;
        if (sid == 'sin_cliente' && clienteId != null) {
          try {
            sid = await FirestoreSyncService.instance
                .asegurarSyncIdCliente(clienteId)
                .timeout(const Duration(seconds: 5), onTimeout: () => sid);
          } catch (_) {}
        }
        final url = await MediaSyncService.instance.subirPdfCliente(
              clienteSyncId: sid,
              nombreArchivo: nombreArchivo,
              file: archivo,
            ) ??
            '';
        if (url.isNotEmpty || sid != syncId) {
          await db.update(
            'documentos_cliente',
            {
              if (url.isNotEmpty) 'url': url,
              if (sid != syncId) 'clienteSyncId': sid,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        final actualizado = doc.copyWith(url: url, clienteSyncId: sid);
        await FirestoreSyncService.instance.subirDocumento(actualizado);
      }

      if (PlatformCapabilities.isWindowsDesktop) {
        syncInBackground(
          CloudSyncThrottle.enqueue(() async {
            await Future<void>.delayed(const Duration(seconds: 20));
            await subirNube();
          }, tag: 'archivarPdf'),
          tag: 'archivarPdf',
        );
      } else {
        syncInBackground(subirNube(), tag: 'archivarPdf');
      }

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
