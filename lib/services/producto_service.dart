import 'dart:convert';

import '../core/config/device_identity.dart';
import '../core/config/platform_capabilities.dart';
import '../core/domain/domain_bootstrap.dart';
import '../core/domain/domain_event.dart';
import '../core/domain/event_bus.dart';
import '../core/domain/inventory_ledger_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/events/producto_side_effects.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/cloud_sync_throttle.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/media_sync_service.dart';
import '../core/sync/sync_background.dart';
import '../core/utils/media_path.dart';
import '../database/database_helper.dart';
import '../models/producto.dart';
import '../repositories/producto_repository.dart';
import 'auth_service.dart';
import 'precio_calculador_service.dart';

class ProductoService {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final PrecioCalculadorService _precioCalculador = PrecioCalculadorService.instance;

  ProductoRepository get _repo => FirestoreSyncService.instance.writeRepository;

  String _snapshot(Producto producto) {
    return jsonEncode({
      'id': producto.id,
      'codigo': producto.codigo,
      'codigoBarras': producto.codigoBarras,
      'descripcion': producto.descripcion,
      'marca': producto.marca,
      'categoria': producto.categoria,
      'stock': producto.stock,
      'costo': producto.costo,
      'precio': producto.precio,
      'precio2': producto.precio2,
      'precio3': producto.precio3,
      'favorito': producto.favorito,
      'deletedAt': producto.deletedAt,
    });
  }

  Future<Producto> _conFotosEnNube(Producto producto) async {
    final entrantes =
        producto.todasLasFotos.where((f) => f.isNotEmpty).toList();
    if (entrantes.isEmpty) return producto;

    final fotos = await MediaSyncService.instance.sincronizarFotosProducto(
      producto.codigo,
      entrantes,
    );
    if (fotos.isEmpty) return producto;

    final urls = fotos.where(esUrlRemota).toList();
    final teniaLocal = entrantes.any((f) => !esUrlRemota(f));

    // Si la nube falla (p. ej. Storage sin reglas), igual guardamos local
    // para que se vea en este equipo; lastError lo muestra el formulario.
    if (urls.isNotEmpty) {
      return producto.copyWith(foto: urls.first, fotos: urls);
    }
    if (teniaLocal &&
        MediaSyncService.instance.nubeDisponible &&
        MediaSyncService.instance.lastError != null) {
      // Conservar rutas locales; no bloquear stock/costos.
      return producto.copyWith(foto: fotos.first, fotos: fotos);
    }
    return producto.copyWith(foto: fotos.first, fotos: fotos);
  }

  /// Re-sube a Storage las fotos que todavía son rutas locales (tras activar nube).
  Future<int> sincronizarFotosLocalesPendientes() async {
    final todos = await obtenerTodos();
    var actualizados = 0;
    final db = await _databaseHelper.database;
    for (final p in todos) {
      final locales = p.todasLasFotos
          .where((f) => f.isNotEmpty && !esUrlRemota(f))
          .toList();
      if (locales.isEmpty) continue;
      final fotos = await MediaSyncService.instance.sincronizarFotosProducto(
        p.codigo,
        p.todasLasFotos,
      );
      if (fotos.isEmpty) continue;
      final huboUrl = fotos.any(esUrlRemota);
      if (!huboUrl) continue;
      final actualizado = p.copyWith(foto: fotos.first, fotos: fotos);
      await db.update(
        'productos',
        {
          'foto': actualizado.fotoPrincipal,
          'fotos': actualizado.toMap()['fotos'],
        },
        where: 'id = ?',
        whereArgs: [p.id],
      );
      try {
        await _repo.actualizar(actualizado);
      } catch (_) {}
      actualizados++;
    }
    if (actualizados > 0) {
      DataRefreshHub.instance.notifyProductos();
    }
    return actualizados;
  }

  void _asegurarSyncProducto(
    int? id, {
    bool incluirStockAbsoluto = false,
  }) {
    if (id == null) return;
    // Windows fast-safe: 1 producto via throttle (serializado, delay corto).
    // Evita ráfagas concurrentes que tumban el .exe, pero sube al toque.
    if (PlatformCapabilities.isWindowsDesktop) {
      syncInBackground(
        CloudSyncThrottle.enqueue(
          () => FirestoreSyncService.instance.subirProductoPorId(
            id,
            incluirStockAbsoluto: incluirStockAbsoluto,
            forzar: incluirStockAbsoluto,
          ),
          tag: 'subirProductoInteractivo',
          interactive: true,
        ),
        tag: 'subirProducto',
      );
      return;
    }
    // Si no hay sesión de nube, entra en cola persistente; si hay, re-empuja.
    syncInBackground(
      FirestoreSyncService.instance.subirProductoPorId(
        id,
        incluirStockAbsoluto: incluirStockAbsoluto,
        forzar: incluirStockAbsoluto,
      ),
      tag: 'subirProducto',
    );
  }

  Future<void> _validarProducto(Producto producto, {int? excludeId}) async {
    final codigo = producto.codigo.trim();
    if (codigo.isEmpty) {
      throw ArgumentError('El código del producto es obligatorio.');
    }
    if (producto.costo < 0) {
      throw ArgumentError('El costo no puede ser negativo.');
    }
    if (producto.precio < 0 || producto.precio2 < 0 || producto.precio3 < 0) {
      throw ArgumentError('Los precios no pueden ser negativos.');
    }
    final db = await _databaseHelper.database;
    final dups = await db.query(
      'productos',
      columns: ['id'],
      where: excludeId == null
          ? "codigo = ? AND (deleted_at IS NULL OR deleted_at = '')"
          : "codigo = ? AND id != ? AND (deleted_at IS NULL OR deleted_at = '')",
      whereArgs: excludeId == null ? [codigo] : [codigo, excludeId],
      limit: 1,
    );
    if (dups.isNotEmpty) {
      throw StateError('Ya existe un producto con el código "$codigo".');
    }
  }

  /// R4/R5: stock solo vía ledger. Nunca `productos.stock = N` absoluto.
  Future<void> _aplicarAjusteStockLedger({
    required int productoId,
    required int delta,
    required String motivo,
    required String eventId,
  }) async {
    if (delta == 0) return;
    DomainBootstrap.ensureInitialized();
    final tipo = delta > 0 ? 'entrada' : 'salida';
    final user = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final tag = await DeviceIdentity.shortTag();
    final event = DomainEvent(
      eventId: eventId,
      type: DomainEventType.ajusteInventario,
      aggregateType: 'producto',
      aggregateId: '$productoId',
      createdBy: user,
      deviceId: tag,
      payload: {
        'tipo': tipo,
        'motivo': motivo,
        'documentType': 'ajuste',
        'documentId': eventId,
        'lines': [
          InventoryLine(
            productoId: productoId,
            cantidad: delta.abs(),
          ).toJson(),
        ],
      },
    );
    final db = await _databaseHelper.database;
    final applied = await db.transaction((txn) async {
      return InventoryLedgerService.instance.applyInTxn(
        txn,
        event,
        sign: delta > 0 ? 1 : -1,
        movimientoTipo: tipo,
      );
    });
    if (applied) {
      InventoryLedgerService.instance.enqueueCloudAfterApply(
        event,
        sign: delta > 0 ? 1 : -1,
      );
      await DomainEventBus.instance.publish(event);
    }
  }

  Future<int> insertar(Producto producto) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.crear,
      operacion: 'crear producto',
    );
    await _validarProducto(producto);
    final conFotos = await _conFotosEnNube(
      producto.copyWith(codigo: producto.codigo.trim()),
    );
    final preparado = await _precioCalculador.aplicarListasDesdeCosto(conFotos);
    final stockInicial = preparado.stock;
    // Inserta con stock 0; el saldo inicial va por movimiento de ledger.
    final id = await _repo.insertar(preparado.copyWith(stock: 0));
    if (stockInicial != 0) {
      await _aplicarAjusteStockLedger(
        productoId: id,
        delta: stockInicial,
        motivo: 'Inventario inicial alta ${preparado.codigo}',
        eventId: 'inv:ajuste:alta:$id:${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
    }
    final guardado = preparado.copyWith(id: id, stock: stockInicial);

    await AuthService.instance.registrarCambio(
      'ALTA_PRODUCTO',
      'productos',
      'Nuevo producto: ${guardado.descripcion}',
      valorNuevo: _snapshot(guardado),
    );
    // Alta: sync metadata; stock via stock_ops del ledger.
    _asegurarSyncProducto(id, incluirStockAbsoluto: false);
    DataRefreshHub.instance.notifyProductos();
    DataRefreshHub.instance.notifyStock();
    ProductoSideEffects.scheduleAfterSave(guardado, op: 'upsert');

    return id;
  }

  Future<void> insertarLista(List<Producto> productos) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.crear,
      operacion: 'importar productos',
    );
    final preparados = <Producto>[];
    final stockPorCodigo = <String, int>{};
    final vistos = <String>{};
    for (final producto in productos) {
      final codigo = producto.codigo.trim();
      if (codigo.isEmpty) {
        throw ArgumentError('Hay productos sin código en la importación.');
      }
      if (producto.costo < 0) {
        throw ArgumentError('Costo negativo en producto $codigo.');
      }
      if (!vistos.add(codigo)) {
        throw StateError('Código duplicado en la importación: $codigo');
      }
      await _validarProducto(producto.copyWith(codigo: codigo));
      final prep = await _precioCalculador.aplicarListasDesdeCosto(
        producto.copyWith(codigo: codigo),
      );
      stockPorCodigo[codigo] = prep.stock;
      preparados.add(prep.copyWith(stock: 0));
    }
    await _repo.insertarLista(preparados);
    final batchTs = DateTime.now().toUtc().microsecondsSinceEpoch;
    try {
      for (final p in preparados) {
        final local = await buscarPorCodigo(p.codigo);
        final localId = local?.id;
        if (localId == null) continue;
        final stock = stockPorCodigo[p.codigo] ?? 0;
        if (stock != 0) {
          await _aplicarAjusteStockLedger(
            productoId: localId,
            delta: stock,
            motivo: 'Inventario inicial importación ${p.codigo}',
            eventId: 'inv:ajuste:import:$batchTs:${p.codigo}',
          );
        }
        _asegurarSyncProducto(localId);
      }
    } catch (_) {}
    DataRefreshHub.instance.notifyProductos();
    DataRefreshHub.instance.notifyStock();
  }

  Future<List<Producto>> obtenerTodos({int? limit, int? offset}) =>
      _repo.obtenerTodos(limit: limit, offset: offset);

  Future<Producto?> buscarPorCodigo(String codigo) => _repo.buscarPorCodigo(codigo);

  Future<Producto?> buscarPorCodigoBarras(String codigoBarras) =>
      _repo.buscarPorCodigoBarras(codigoBarras);

  Future<bool> tieneProductos() => _repo.tieneProductos();

  Future<List<Producto>> obtenerFavoritos() async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'productos',
      where: "favorito = 1 AND (deleted_at IS NULL OR deleted_at = '')",
      orderBy: 'descripcion',
    );
    return rows.map(Producto.fromMap).toList();
  }

  Future<List<Producto>> obtenerEliminados() async {
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'productos',
      where: "deleted_at IS NOT NULL AND deleted_at != ''",
      orderBy: 'datetime(deleted_at) DESC',
    );
    return rows.map(Producto.fromMap).toList();
  }

  Future<void> toggleFavorito(Producto producto) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.editar,
      operacion: 'marcar favorito',
    );
    if (producto.id == null) return;
    final nuevo = !producto.favorito;
    final db = await _databaseHelper.database;
    await db.update(
      'productos',
      {'favorito': nuevo ? 1 : 0},
      where: 'id = ?',
      whereArgs: [producto.id],
    );
    await AuthService.instance.registrarCambio(
      nuevo ? 'FAVORITO_PRODUCTO' : 'QUITAR_FAVORITO_PRODUCTO',
      'productos',
      '${nuevo ? 'Marcado' : 'Quitado'} favorito: ${producto.descripcion}',
      valorAnterior: _snapshot(producto),
      valorNuevo: _snapshot(producto.copyWith(favorito: nuevo)),
    );
    // Sync remoto si aplica
    try {
      await _repo.actualizar(producto.copyWith(favorito: nuevo));
    } catch (_) {}
    _asegurarSyncProducto(producto.id);
    DataRefreshHub.instance.notifyProductos();
  }

  Future<int> actualizar(Producto producto) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.editar,
      operacion: 'editar producto',
    );
    if (producto.costo < 0) {
      throw ArgumentError('El costo no puede ser negativo.');
    }
    if (producto.precio < 0 || producto.precio2 < 0 || producto.precio3 < 0) {
      throw ArgumentError('Los precios no pueden ser negativos.');
    }
    final conFotos = await _conFotosEnNube(producto);
    final db = await _databaseHelper.database;
    Producto? anteriorProducto;

    if (conFotos.id != null) {
      final anterior = await db.query(
        'productos',
        where: 'id = ?',
        whereArgs: [conFotos.id],
        limit: 1,
      );
      if (anterior.isNotEmpty) {
        anteriorProducto = Producto.fromMap(anterior.first);
        // Código inmutable (docId en Firestore).
        final actualizado = conFotos.copyWith(codigo: anteriorProducto.codigo);
        final costoCambio = anteriorProducto.costo != actualizado.costo;

        final costoAnterior = anteriorProducto.costo;
        final precioAnterior = anteriorProducto.precio;
        final listasModificadas = <String>[];
        if (precioAnterior != actualizado.precio) listasModificadas.add('Lista 1');
        if (anteriorProducto.precio2 != actualizado.precio2) {
          listasModificadas.add('Lista 2');
        }
        if (anteriorProducto.precio3 != actualizado.precio3) {
          listasModificadas.add('Lista 3');
        }

        if (costoCambio || listasModificadas.isNotEmpty) {
          final variacion = precioAnterior > 0
              ? ((actualizado.precio - precioAnterior) / precioAnterior) * 100
              : 0.0;
          await db.insert('historial_precios', {
            'productoId': conFotos.id,
            'fecha': DateTime.now().toIso8601String(),
            'usuario': AuthService.instance.currentUser?.usuario ?? 'sistema',
            'costoAnterior': costoAnterior,
            'costoNuevo': actualizado.costo,
            'precioAnterior': precioAnterior,
            'precioNuevo': actualizado.precio,
            'porcentaje': variacion,
            'listaModificada':
                listasModificadas.isEmpty ? 'Costo' : listasModificadas.join(', '),
            'motivo': costoCambio ? 'Cambio de costo' : 'Edición de producto',
          });
        }

        // R4: nunca sobrescribir stock absoluto desde el formulario.
        // Si el caller envió otro stock, se convierte en movimiento de ajuste.
        final stockDeseado = actualizado.stock;
        final stockActual = anteriorProducto.stock;
        final metaOnly = actualizado.copyWith(stock: stockActual);
        final result = await _repo.actualizar(metaOnly);
        final delta = stockDeseado - stockActual;
        if (delta != 0) {
          await _aplicarAjusteStockLedger(
            productoId: actualizado.id!,
            delta: delta,
            motivo: 'Ajuste por edición producto ${actualizado.codigo}',
            eventId:
                'inv:ajuste:edit:${actualizado.id}:${DateTime.now().toUtc().microsecondsSinceEpoch}',
          );
        }
        final finalSnap = metaOnly.copyWith(stock: stockActual + delta);
        await AuthService.instance.registrarCambio(
          'MODIFICACION_PRODUCTO',
          'productos',
          'Producto actualizado: ${actualizado.descripcion}',
          valorAnterior: _snapshot(anteriorProducto),
          valorNuevo: _snapshot(finalSnap),
        );
        _asegurarSyncProducto(actualizado.id, incluirStockAbsoluto: false);
        DataRefreshHub.instance.notifyProductos();
        DataRefreshHub.instance.notifyStock();
        ProductoSideEffects.scheduleAfterSave(finalSnap, op: 'upsert');
        return result;
      }
    }

    final result = await _repo.actualizar(conFotos.copyWith(stock: 0));
    await AuthService.instance.registrarCambio(
      'MODIFICACION_PRODUCTO',
      'productos',
      'Producto actualizado: ${conFotos.descripcion}',
      valorNuevo: _snapshot(conFotos),
    );
    _asegurarSyncProducto(conFotos.id, incluirStockAbsoluto: false);
    DataRefreshHub.instance.notifyProductos();
    ProductoSideEffects.scheduleAfterSave(conFotos, op: 'upsert');
    return result;
  }

  /// Soft-delete → va a la papelera.
  Future<int> eliminar(int id) async {
    AuthorizationService.instance.require(
      'productos',
      AuthzAction.eliminar,
      operacion: 'eliminar producto',
    );
    final db = await _databaseHelper.database;
    final anterior = await db.query(
      'productos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final producto = anterior.isNotEmpty ? Producto.fromMap(anterior.first) : null;

    final result = await _repo.eliminar(id);

    if (producto != null) {
      await AuthService.instance.registrarCambio(
        'BAJA_PRODUCTO',
        'productos',
        'Producto enviado a papelera: ${producto.descripcion}',
        valorAnterior: _snapshot(producto),
        valorNuevo: _snapshot(
          producto.copyWith(deletedAt: DateTime.now().toIso8601String()),
        ),
      );
    }
    _asegurarSyncProducto(id);
    DataRefreshHub.instance.notifyProductos();
    if (producto != null) {
      ProductoSideEffects.scheduleAfterSave(
        producto.copyWith(deletedAt: DateTime.now().toIso8601String()),
        op: 'delete',
      );
    }

    return result;
  }

  Future<void> restaurar(int id) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.editar,
      operacion: 'restaurar producto',
    );
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'productos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final producto = Producto.fromMap(rows.first);
    final restaurado = producto.copyWith(
      clearDeletedAt: true,
      actualizadoEn: DateTime.now().toUtc().toIso8601String(),
    );
    await db.update(
      'productos',
      {
        'deleted_at': null,
        'actualizadoEn': restaurado.actualizadoEn,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    try {
      await _repo.actualizar(restaurado);
    } catch (_) {}
    _asegurarSyncProducto(id);
    await AuthService.instance.registrarCambio(
      'RESTAURAR_PRODUCTO',
      'productos',
      'Producto restaurado: ${producto.descripcion}',
      valorAnterior: _snapshot(producto),
      valorNuevo: _snapshot(restaurado),
    );
    DataRefreshHub.instance.notifyProductos();
    ProductoSideEffects.scheduleAfterSave(restaurado, op: 'upsert');
  }

  Future<void> eliminarDefinitivo(int id) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.eliminar,
      operacion: 'eliminar producto definitivo',
    );
    final db = await _databaseHelper.database;
    final rows = await db.query(
      'productos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final producto = Producto.fromMap(rows.first);
    final codigo = producto.codigo.trim();
    // Capacidad 7: tombstone en outbox ANTES del hard-delete local.
    if (codigo.isNotEmpty) {
      try {
        await FirestoreSyncService.instance.eliminarProductoRemoto(
          codigo,
          localId: id,
        );
      } catch (e) {
        assert(() {
          // ignore: avoid_print
          print('eliminarProductoRemoto: $e');
          return true;
        }());
      }
    }
    try {
      await db.delete('productos', where: 'id = ?', whereArgs: [id]);
    } catch (_) {
      // Puede haberlo borrado el tombstone remoto en paralelo.
    }
    await AuthService.instance.registrarCambio(
      'ELIMINAR_DEFINITIVO_PRODUCTO',
      'productos',
      'Producto eliminado definitivamente: ${producto.descripcion}',
      valorAnterior: _snapshot(producto),
    );
    DataRefreshHub.instance.notifyProductos();
    ProductoSideEffects.scheduleAfterSave(producto, op: 'delete');
  }

  Future<List<Map<String, dynamic>>> historialCambios(int productoId) async {
    final db = await _databaseHelper.database;
    final precios = await db.query(
      'historial_precios',
      where: 'productoId = ?',
      whereArgs: [productoId],
      orderBy: 'datetime(fecha) DESC',
    );
    final audit = await db.rawQuery('''
      SELECT * FROM audit_log
      WHERE tablaAfectada = 'productos'
        AND (
          valorAnterior LIKE ? OR valorNuevo LIKE ?
          OR detalle LIKE ?
        )
      ORDER BY datetime(fecha) DESC
      LIMIT 100
    ''', ['%"id":$productoId%', '%"id":$productoId%', '%id":$productoId%']);

    final combinados = <Map<String, dynamic>>[];
    for (final p in precios) {
      combinados.add({
        'tipo': 'precio',
        'fecha': p['fecha'],
        'usuario': p['usuario'],
        'detalle': p['motivo'] ?? 'Cambio de precio',
        'extra': p,
      });
    }
    for (final a in audit) {
      combinados.add({
        'tipo': 'auditoria',
        'fecha': a['fecha'],
        'usuario': a['usuario'],
        'detalle': a['detalle'] ?? a['accion'],
        'extra': a,
      });
    }
    combinados.sort((a, b) {
      final fa = DateTime.tryParse(a['fecha']?.toString() ?? '') ?? DateTime(1970);
      final fb = DateTime.tryParse(b['fecha']?.toString() ?? '') ?? DateTime(1970);
      return fb.compareTo(fa);
    });
    return combinados;
  }
}
