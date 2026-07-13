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
  /// (no por código interno). Soporta rangos tipo "papi blanco 39-42".
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

    // 1) Match exacto de descripción completa / desc+color+talle
    final exactos = porDesc[n];
    if (exactos != null && exactos.isNotEmpty) {
      return List<Producto>.from(exactos);
    }

    // 2) Si hay rango de talles: "febo papifutbol 39-42 blanco"
    if (rango.desde != null && rango.hasta != null) {
      final base = rango.base;
      final bases = <String>{
        base,
        // Variantes sin ruido típico de listas de proveedor
        base
            .replaceAll(RegExp(r'\b(x par|por par|en eva|eva|pu|pve|tr|goma)\b'), ' ')
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

      // Fallback: locales cuyo desc+color coincida de forma suave con la base
      if (candidatos.isEmpty) {
        for (final p in todos) {
          final dc = TextoProducto.textoLocalSinTalle(
            descripcion: p.descripcion,
            color: p.colorProducto,
          );
          if (dc.isEmpty) continue;
          if (bases.any((b) => b == dc || _coincideSuave(b, dc))) {
            candidatos.add(p);
          }
        }
      }

      final enRango = candidatos.where((p) {
        final t = TextoProducto.parsearTalle(p.talle) ??
            TextoProducto.parsearTalleAlFinal(p.descripcion) ??
            TextoProducto.parsearTalleAlFinal(
              '${p.descripcion} ${p.colorProducto}',
            );
        if (t == null) {
          final full = TextoProducto.textoLocal(
            descripcion: p.descripcion,
            color: p.colorProducto,
            talle: p.talle,
          );
          return full == n || bases.any(full.startsWith);
        }
        return t >= rango.desde! && t <= rango.hasta!;
      }).toList();

      if (enRango.isNotEmpty) return enRango;
    }

    // 3) Match por descripción+color sin talle (un solo costo para todos los talles)
    final dc = porDescColor[n];
    if (dc != null && dc.isNotEmpty) return List<Producto>.from(dc);

    // 4) Contención suave con tokens significativos (evita "blanco" ≠ todo blanco)
    final suaves = <Producto>[];
    for (final p in todos) {
      final localDc = TextoProducto.textoLocalSinTalle(
        descripcion: p.descripcion,
        color: p.colorProducto,
      );
      final localFull = TextoProducto.textoLocal(
        descripcion: p.descripcion,
        color: p.colorProducto,
        talle: p.talle,
      );
      if (localDc.isEmpty) continue;
      if (n == localFull || n == localDc) {
        suaves.add(p);
        continue;
      }
      if (_coincideSuave(n, localFull) || _coincideSuave(n, localDc)) {
        suaves.add(p);
      }
    }
    return suaves;
  }

  bool _coincideSuave(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length > b.length ? a : b;
    if (shorter.length < 8 || !longer.contains(shorter)) return false;
    final tokensA = a.split(' ').where((t) => t.length > 2).toSet();
    final tokensB = b.split(' ').where((t) => t.length > 2).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return false;
    final comunes = tokensA.intersection(tokensB).length;
    if (tokensA.length <= 2 || tokensB.length <= 2) {
      return comunes >= 1;
    }
    return comunes >= 2;
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
