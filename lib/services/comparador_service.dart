import 'package:sqflite/sqflite.dart';

import '../core/utils/texto_producto.dart';
import '../database/database_helper.dart';
import '../models/comparacion.dart';
import '../models/producto.dart';
import 'auth_service.dart';
import 'producto_service.dart';

class ComparadorService {
  final ProductoService productoService = ProductoService();

  Future<void> limpiarComparaciones() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('comparacion');
  }

  Future<void> guardarComparacion(Comparacion comparacion) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'comparacion',
      comparacion.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Comparacion>> obtenerComparacion() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.query('comparacion', orderBy: 'descripcion');
    return resultado.map((e) => Comparacion.fromMap(e)).toList();
  }

  /// Compara la lista del proveedor contra la base por **descripción**
  /// (no por código interno).
  ///
  /// - Rangos (Febo): "papi blanco 39-42" → todos tus talles 39..42 de ese modelo.
  /// - Un precio / toda la numeración (Leal): "marilyn 39" o "marilyn" →
  ///   todos tus marilyn (35, 36, 39, …), porque el costo es el mismo.
  Future<void> compararProductos(
    List<Producto> productosImportados, {
    String proveedor = '',
  }) async {
    await limpiarComparaciones();
    final locales = await productoService.obtenerTodos();

    // Índice por descripción normalizada (exacta).
    final porDesc = <String, List<Producto>>{};
    // Índice por descripción+color (sin talle).
    final porDescColor = <String, List<Producto>>{};
    for (final p in locales) {
      final d = TextoProducto.normalizar(p.descripcion);
      if (d.isNotEmpty) {
        porDesc.putIfAbsent(d, () => []).add(p);
      }
      final dc = TextoProducto.textoLocalSinTalle(
        descripcion: p.descripcion,
        color: p.colorProducto,
      );
      if (dc.isNotEmpty) {
        porDescColor.putIfAbsent(dc, () => []).add(p);
      }
      // Si el talle está pegado en la descripción ("papi blanco 40"),
      // también indexar la base sin ese número.
      if (p.talle.trim().isEmpty) {
        final sinTalle = TextoProducto.quitarTalleFinal(
          p.colorProducto.trim().isEmpty
              ? p.descripcion
              : '${p.descripcion} ${p.colorProducto}',
        );
        if (sinTalle.isNotEmpty && sinTalle != dc && sinTalle != d) {
          porDescColor.putIfAbsent(sinTalle, () => []).add(p);
        }
      }
      final full = TextoProducto.textoLocal(
        descripcion: p.descripcion,
        color: p.colorProducto,
        talle: p.talle,
      );
      if (full.isNotEmpty && full != d && full != dc) {
        porDesc.putIfAbsent(full, () => []).add(p);
      }
    }

    for (final importado in productosImportados) {
      final descProv = importado.descripcion.trim();
      if (descProv.isEmpty) continue;

      final matches = _buscarLocales(
        descripcionProveedor: descProv,
        porDesc: porDesc,
        porDescColor: porDescColor,
        todos: locales,
      );

      if (matches.isEmpty) {
        await guardarComparacion(
          Comparacion(
            codigo: importado.codigo.isNotEmpty
                ? importado.codigo
                : 'NUEVO-${TextoProducto.normalizar(descProv).hashCode.abs()}',
            descripcion: descProv,
            precioViejo: 0,
            precioNuevo: importado.costo,
            estado: 'NUEVO',
            marca: importado.marca,
            proveedor: proveedor,
          ),
        );
        continue;
      }

      for (final local in matches) {
        var estado = 'IGUAL';
        if (importado.costo > local.costo) {
          estado = 'SUBIO';
        } else if (importado.costo < local.costo) {
          estado = 'BAJO';
        }
        // codigo = código LOCAL (para actualizar el producto correcto).
        await guardarComparacion(
          Comparacion(
            codigo: local.codigo,
            descripcion:
                '${local.descripcion}${local.colorProducto.isNotEmpty ? ' ${local.colorProducto}' : ''}${local.talle.isNotEmpty ? ' ${local.talle}' : ''}  ←  $descProv',
            precioViejo: local.costo,
            precioNuevo: importado.costo,
            estado: estado,
            marca: local.marca.isNotEmpty ? local.marca : importado.marca,
            proveedor: proveedor,
          ),
        );
      }
    }
  }

  List<Producto> _buscarLocales({
    required String descripcionProveedor,
    required Map<String, List<Producto>> porDesc,
    required Map<String, List<Producto>> porDescColor,
    required List<Producto> todos,
  }) {
    final n = TextoProducto.normalizar(descripcionProveedor);
    final rango = TextoProducto.parsearRangoTalle(descripcionProveedor);

    // 1) Rango de talles (Febo): "papi blanco 39-42" / "papi negro 39-42"
    if (rango.desde != null && rango.hasta != null) {
      final base = rango.base;
      final bases = <String>{
        base,
        base
            .replaceAll(
              RegExp(r'\b(x par|por par|en eva|eva|pu|pve|tr|goma)\b'),
              ' ',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      }..removeWhere((e) => e.isEmpty);

      final candidatos = <Producto>{};

      for (final b in bases) {
        final porColor = porDescColor[b];
        if (porColor != null) candidatos.addAll(porColor);
        final soloDesc = porDesc[b];
        if (soloDesc != null) candidatos.addAll(soloDesc);
      }

      for (final p in todos) {
        final dc = TextoProducto.textoLocalSinTalle(
          descripcion: p.descripcion,
          color: p.colorProducto,
        );
        if (dc.isEmpty) continue;
        if (bases.any(
          (b) => b == dc || TextoProducto.coincidePorTokens(b, dc),
        )) {
          candidatos.add(p);
        }
      }

      final enRango = candidatos.where((p) {
        return TextoProducto.localEnRangoProveedor(
          descripcionLocal: p.descripcion,
          colorLocal: p.colorProducto,
          talleLocal: p.talle,
          desde: rango.desde!,
          hasta: rango.hasta!,
        );
      }).toList();

      if (enRango.isNotEmpty) return enRango;
      // Si el rango no pegó, seguimos con match de modelo (por si el formato vino raro).
    }

    // 2) Un precio para toda la numeración (Leal, etc.):
    //    "marilyn 39" o "marilyn" → TODOS los talles locales de ese modelo.
    final baseProv = TextoProducto.quitarTalleFinal(descripcionProveedor);
    final basesModelo = <String>{
      baseProv,
      n,
      if (baseProv != n) baseProv,
    }..removeWhere((e) => e.isEmpty);

    final delModelo = <Producto>{};
    for (final b in basesModelo) {
      final porColor = porDescColor[b];
      if (porColor != null) delModelo.addAll(porColor);
      final soloDesc = porDesc[b];
      if (soloDesc != null) delModelo.addAll(soloDesc);
    }

    for (final p in todos) {
      final localDc = TextoProducto.textoLocalSinTalle(
        descripcion: p.descripcion,
        color: p.colorProducto,
      );
      if (localDc.isEmpty) continue;
      if (basesModelo.any(
        (b) =>
            b == localDc ||
            TextoProducto.coincidePorTokens(b, localDc),
      )) {
        delModelo.add(p);
      }
    }

    if (delModelo.isNotEmpty) {
      return delModelo.toList();
    }

    // 3) Match exacto del texto completo (último recurso).
    final exactos = porDesc[n];
    if (exactos != null && exactos.isNotEmpty) {
      return List<Producto>.from(exactos);
    }

    return const [];
  }

  /// Actualiza **únicamente el costo** de los productos emparejados (por código local).
  Future<void> actualizarProductos() async {
    final comparaciones = await obtenerComparacion();
    final db = await DatabaseHelper.instance.database;
    final usuario = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final ahora = DateTime.now().toIso8601String();

    for (final comp in comparaciones) {
      final producto = await productoService.buscarPorCodigo(comp.codigo);
      if (producto != null) {
        if (comp.precioNuevo != comp.precioViejo) {
          await db.update(
            'productos',
            {'costo': comp.precioNuevo},
            where: 'id = ?',
            whereArgs: [producto.id],
          );

          await db.insert('historial_precios', {
            'productoId': producto.id,
            'fecha': ahora,
            'usuario': usuario,
            'costoAnterior': comp.precioViejo,
            'costoNuevo': comp.precioNuevo,
            'precioAnterior': producto.precio,
            'precioNuevo': producto.precio,
            'porcentaje': comp.precioViejo > 0
                ? ((comp.precioNuevo - comp.precioViejo) / comp.precioViejo) *
                    100
                : 0.0,
            'listaModificada':
                comp.proveedor.isNotEmpty ? comp.proveedor : 'Lista proveedor',
            'motivo': 'Actualización de costo por lista (desc)',
          });
        }
      } else if (comp.estado == 'NUEVO') {
        await productoService.insertar(
          Producto(
            codigo: comp.codigo,
            descripcion: comp.descripcion.split('  ←  ').first.trim(),
            marca: comp.marca,
            categoria: '',
            proveedor: comp.proveedor,
            ubicacion: '',
            stock: 0,
            costo: comp.precioNuevo,
            precio: 0,
            observaciones: '',
            foto: '',
          ),
        );
      }
    }
  }

  Future<int> cantidadAumentos() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='SUBIO'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> cantidadBajas() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='BAJO'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> cantidadNuevos() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='NUEVO'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> cantidadIguales() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='IGUAL'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}
