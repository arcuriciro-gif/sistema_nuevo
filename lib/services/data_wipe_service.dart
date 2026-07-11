import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/config/backend_config_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/firebase/firebase_bootstrap.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import '../database/database_helper.dart';
import 'auth_service.dart';
import 'auto_backup_service.dart';
import 'comunicaciones_service.dart';

/// Borrados masivos / sistema virgen. Solo admin + clave (validada en UI).
class DataWipeService {
  DataWipeService._();
  static final DataWipeService instance = DataWipeService._();

  void _requiereAdmin() {
    if (!AuthService.instance.esAdministrador()) {
      throw StateError('Solo el administrador puede vaciar datos.');
    }
  }

  static const _tablasOperativas = [
    'pedido_items',
    'pedidos',
    'compra_items',
    'compras',
    'remito_items',
    'remitos',
    'ventas_items',
    'ventas',
    'pagos',
    'movimientos_stock',
    'historial_precios',
    'comparacion',
    'documentos_cliente',
    'comentarios_internos',
    'chat_mensajes',
    'chat_conversaciones',
    'notificaciones_internas',
    'sync_queue',
    'sync_history',
  ];

  CollectionReference<Map<String, dynamic>> _col(String name) {
    final tenant = BackendConfigService.instance.tenantId;
    return FirebaseFirestore.instance
        .collection('tenants')
        .doc(tenant)
        .collection(name);
  }

  Future<void> _vaciarColeccion(String nombre) async {
    if (!BackendConfigService.instance.firebaseEnabled ||
        !FirebaseBootstrap.isReady) {
      return;
    }
    try {
      final col = _col(nombre);
      while (true) {
        final snap = await col.limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Wipe remoto $nombre: $e');
    }
  }

  Future<void> _deleteAll(Database db, String table) async {
    try {
      await db.delete(table);
    } catch (e) {
      debugPrint('Wipe local $table: $e');
    }
  }

  Future<({bool ok, String mensaje})> vaciarProductos() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;
    await SyncQueueService.instance.stop();
    await FirestoreSyncService.instance.stop();

    await db.transaction((txn) async {
      await txn.delete('pedido_items');
      await txn.delete('compra_items');
      await txn.delete('remito_items');
      await txn.delete('ventas_items');
      await txn.delete('movimientos_stock');
      await txn.delete('historial_precios');
      await txn.delete('comentarios_internos');
      await txn.delete('comparacion');
      await txn.delete('productos');
    });
    await _vaciarColeccion('productos');

    await AuthService.instance.registrarCambio(
      'VACIAR_PRODUCTOS',
      'productos',
      'Vacío completo del catálogo de productos',
    );

    await FirestoreSyncService.instance.start();
    await SyncQueueService.instance.start();
    DataRefreshHub.instance.notifyTodo();
    return (ok: true, mensaje: 'Productos eliminados (local y nube).');
  }

  Future<({bool ok, String mensaje})> vaciarClientes() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;
    await SyncQueueService.instance.stop();
    await FirestoreSyncService.instance.stop();

    await db.transaction((txn) async {
      await txn.delete('pagos');
      await txn.delete('documentos_cliente');
      // Desvincular ventas/remitos de clientes
      try {
        await txn.rawUpdate('UPDATE ventas SET clienteId = NULL');
      } catch (_) {}
      try {
        await txn.rawUpdate('UPDATE remitos SET clienteId = NULL');
      } catch (_) {}
      await txn.delete('clientes');
    });
    await _vaciarColeccion('clientes');

    await AuthService.instance.registrarCambio(
      'VACIAR_CLIENTES',
      'clientes',
      'Vacío completo de clientes',
    );

    await FirestoreSyncService.instance.start();
    await SyncQueueService.instance.start();
    DataRefreshHub.instance.notifyTodo();
    return (ok: true, mensaje: 'Clientes eliminados (local y nube).');
  }

  /// Deja el sistema operativo vacío: catálogo, clientes, docs y movimientos.
  /// Conserva usuarios, permisos y branding (preferencias).
  Future<({bool ok, String mensaje})> sistemaVirgen() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;

    await SyncQueueService.instance.stop();
    await FirestoreSyncService.instance.stop();
    await ComunicacionesService.instance.detener();
    AutoBackupService.instance.detener();

    for (final t in _tablasOperativas) {
      await _deleteAll(db, t);
    }
    await _deleteAll(db, 'productos');
    await _deleteAll(db, 'clientes');
    await _deleteAll(db, 'proveedores');
    await _deleteAll(db, 'categorias');
    await _deleteAll(db, 'listas_precios');
    // Limpiar audit_log operativo pero dejar constancia del wipe
    await _deleteAll(db, 'audit_log');

    for (final c in [
      'productos',
      'clientes',
      'proveedores',
      'ventas',
      'remitos',
      'compras',
      'pedidos',
      'documentos',
      'comentarios',
      'categorias',
      'listas_precios',
    ]) {
      await _vaciarColeccion(c);
    }

    await AuthService.instance.registrarCambio(
      'SISTEMA_VIRGEN',
      'sistema',
      'Restablecimiento a sistema virgen (datos operativos borrados; usuarios conservados)',
    );

    await FirestoreSyncService.instance.start();
    await SyncQueueService.instance.start();
    await ComunicacionesService.instance.iniciar();
    await AutoBackupService.instance.iniciar();
    DataRefreshHub.instance.notifyTodo();

    return (
      ok: true,
      mensaje:
          'Sistema virgen: se borraron productos, clientes, ventas y demás datos operativos. Usuarios y permisos se conservaron.',
    );
  }
}
