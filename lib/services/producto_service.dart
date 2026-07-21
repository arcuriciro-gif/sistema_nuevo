import 'dart:async';
import 'dart:convert';

import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/media_sync_service.dart';
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
    // Si no hay sesión de nube, entra en cola persistente; si hay, re-empuja.
    unawaited(
      FirestoreSyncService.instance.subirProductoPorId(
        id,
        incluirStockAbsoluto: incluirStockAbsoluto,
        forzar: incluirStockAbsoluto,
      ),
    );
  }

  Future<int> insertar(Producto producto) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.crear,
      operacion: 'crear producto',
    );
    final conFotos = await _conFotosEnNube(producto);
    final preparado = await _precioCalculador.aplicarListasDesdeCosto(conFotos);
    final id = await _repo.insertar(preparado);
    final guardado = preparado.copyWith(id: id);

    await AuthService.instance.registrarCambio(
      'ALTA_PRODUCTO',
      'productos',
      'Nuevo producto: ${guardado.descripcion}',
      valorNuevo: _snapshot(guardado),
    );
    // Alta: el stock inicial tiene que ir a la nube.
    _asegurarSyncProducto(id, incluirStockAbsoluto: true);
    DataRefreshHub.instance.notifyProductos();

    return id;
  }

  Future<void> insertarLista(List<Producto> productos) async {
    AuthorizationService.instance.require(
      AuthModules.productos,
      AuthzAction.crear,
      operacion: 'importar productos',
    );
    final preparados = <Producto>[];
    for (final producto in productos) {
      preparados.add(await _precioCalculador.aplicarListasDesdeCosto(producto));
    }
    await _repo.insertarLista(preparados);
    // Tras import masivo, encolar los recién cargados (si no hay sesión nube).
    try {
      for (final p in preparados) {
        final local = await buscarPorCodigo(p.codigo);
        _asegurarSyncProducto(local?.id);
      }
    } catch (_) {}
    DataRefreshHub.instance.notifyProductos();
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

        final result = await _repo.actualizar(actualizado);
        await AuthService.instance.registrarCambio(
          'MODIFICACION_PRODUCTO',
          'productos',
          'Producto actualizado: ${actualizado.descripcion}',
          valorAnterior: _snapshot(anteriorProducto),
          valorNuevo: _snapshot(actualizado),
        );
        // Si cambiaron el stock a mano en el formulario, hay que subir el
        // valor absoluto (los remitos usan deltas aparte).
        final stockCambio = anteriorProducto.stock != actualizado.stock;
        _asegurarSyncProducto(
          actualizado.id,
          incluirStockAbsoluto: stockCambio,
        );
        DataRefreshHub.instance.notifyProductos();
        return result;
      }
    }

    final result = await _repo.actualizar(conFotos);
    await AuthService.instance.registrarCambio(
      'MODIFICACION_PRODUCTO',
      'productos',
      'Producto actualizado: ${conFotos.descripcion}',
      valorNuevo: _snapshot(conFotos),
    );
    _asegurarSyncProducto(conFotos.id, incluirStockAbsoluto: true);
    DataRefreshHub.instance.notifyProductos();
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
    await db.delete('productos', where: 'id = ?', whereArgs: [id]);
    try {
      // Soft-delete remoto ya aplicado; forzar borrado remoto vía actualizar no aplica.
      // El Dual repo no expone hard delete; se deja solo local + audit.
    } catch (_) {}
    await AuthService.instance.registrarCambio(
      'ELIMINAR_DEFINITIVO_PRODUCTO',
      'productos',
      'Producto eliminado definitivamente: ${producto.descripcion}',
      valorAnterior: _snapshot(producto),
    );
    DataRefreshHub.instance.notifyProductos();
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
