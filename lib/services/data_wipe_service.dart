import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/config/backend_config_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/firebase/firebase_bootstrap.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_outbox.dart';
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
    'compra_items',
    'compras',
    'remito_items',
    'remitos',
    'ventas_items',
    'ventas',
    'pagos',
    'pagos_v28',
    'movimientos_stock',
    'historial_precios',
    'comparacion',
    'documentos_cliente',
    'comentarios_internos',
    'chat_mensajes',
    'chat_conversaciones',
    'notificaciones_internas',
    'crm_seguimientos',
    'wa_mensajes_log',
    'wa_catalog_items',
    'stock_ops_applied',
    'stock_ops_pull_holds',
    'inventory_ledger',
    'money_ledger',
    'domain_events',
    'sync_outbox',
    'sync_watermarks',
    'sync_conflicts',
    'sync_op_traces',
    'sync_scheduler_state',
    'sync_metrics_samples',
    'integrity_alarms',
    'integrity_scan_meta',
    'import_jobs',
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
        final snap = await col.limit(300).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        await Future<void>.delayed(const Duration(milliseconds: 40));
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

  Future<void> _pauseSync() async {
    try {
      await FirestoreSyncService.instance.stop();
    } catch (_) {}
    try {
      await ComunicacionesService.instance.detener();
    } catch (_) {}
    try {
      AutoBackupService.instance.detener();
    } catch (_) {}
  }

  Future<void> _resumeSync() async {
    try {
      await FirestoreSyncService.instance.start();
    } catch (_) {}
    try {
      await ComunicacionesService.instance.iniciar();
    } catch (_) {}
    try {
      await AutoBackupService.instance.iniciar();
    } catch (_) {}
    DataRefreshHub.instance.notifyTodo();
  }

  Future<({bool ok, String mensaje})> vaciarProductos() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;
    await _pauseSync();
    try {
      await db.transaction((txn) async {
        for (final t in [
          'compra_items',
          'remito_items',
          'ventas_items',
          'movimientos_stock',
          'historial_precios',
          'comentarios_internos',
          'comparacion',
          'stock_ops_applied',
          'stock_ops_pull_holds',
          'inventory_ledger',
          'productos',
        ]) {
          try {
            await txn.delete(t);
          } catch (_) {}
        }
      });
      await _vaciarColeccion('productos');
      await _vaciarColeccion('stock_ops');
      try {
        await SyncOutbox.instance.quietWindowsGhostQueue(aggressive: true);
      } catch (_) {}
      await AuthService.instance.registrarCambio(
        'VACIAR_PRODUCTOS',
        'productos',
        'Vacío completo del catálogo de productos',
      );
      return (ok: true, mensaje: 'Productos eliminados (local y nube).');
    } finally {
      await _resumeSync();
    }
  }

  Future<({bool ok, String mensaje})> vaciarClientes() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;
    await _pauseSync();
    try {
      await db.transaction((txn) async {
        try {
          await txn.delete('pagos');
        } catch (_) {}
        try {
          await txn.delete('pagos_v28');
        } catch (_) {}
        try {
          await txn.delete('documentos_cliente');
        } catch (_) {}
        try {
          await txn.delete('crm_seguimientos');
        } catch (_) {}
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
      return (ok: true, mensaje: 'Clientes eliminados (local y nube).');
    } finally {
      await _resumeSync();
    }
  }

  /// Vacía comprobantes (remitos) + ítems.
  Future<({bool ok, String mensaje})> vaciarComprobantes() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;
    await _pauseSync();
    try {
      await db.transaction((txn) async {
        try {
          await txn.delete('remito_items');
        } catch (_) {}
        await txn.delete('remitos');
      });
      await _vaciarColeccion('remitos');
      await AuthService.instance.registrarCambio(
        'VACIAR_COMPROBANTES',
        'remitos',
        'Vacío completo de comprobantes/remitos',
      );
      return (ok: true, mensaje: 'Comprobantes eliminados (local y nube).');
    } finally {
      await _resumeSync();
    }
  }

  /// Sistema operativo vacío. Conserva usuarios, permisos y branding.
  Future<({bool ok, String mensaje})> sistemaVirgen() async {
    _requiereAdmin();
    final db = await DatabaseHelper.instance.database;
    await _pauseSync();
    try {
      for (final t in _tablasOperativas) {
        await _deleteAll(db, t);
      }
      await _deleteAll(db, 'productos');
      await _deleteAll(db, 'clientes');
      await _deleteAll(db, 'proveedores');
      await _deleteAll(db, 'categorias');
      await _deleteAll(db, 'listas_precios');
      await _deleteAll(db, 'audit_log');

      for (final c in [
        'productos',
        'clientes',
        'proveedores',
        'ventas',
        'remitos',
        'compras',
        'documentos',
        'comentarios',
        'categorias',
        'listas_precios',
        'stock_ops',
      ]) {
        await _vaciarColeccion(c);
      }

      await AuthService.instance.registrarCambio(
        'SISTEMA_VIRGEN',
        'sistema',
        'Restablecimiento a sistema virgen (datos operativos borrados; usuarios conservados)',
      );

      return (
        ok: true,
        mensaje:
            'Sistema virgen: se borraron productos, clientes, comprobantes, '
            'ventas y demás datos operativos. Usuarios y permisos se conservaron.',
      );
    } finally {
      await _resumeSync();
    }
  }

  /// Reinicia sync/comms sin borrar datos.
  Future<({bool ok, String mensaje})> reiniciarServicios() async {
    _requiereAdmin();
    await _pauseSync();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _resumeSync();
    await AuthService.instance.registrarCambio(
      'REINICIAR_SISTEMA',
      'sistema',
      'Reinicio de servicios internos (sin borrar datos)',
    );
    return (
      ok: true,
      mensaje: 'Servicios reiniciados. Los datos no se modificaron.',
    );
  }
}
