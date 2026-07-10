import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/comparacion.dart';
import '../models/producto.dart';
import 'auth_service.dart';
import 'producto_service.dart';
import 'talle_rango_parser.dart';

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

  /// Compara la lista importada contra la base usando el campo [costo].
  /// [proveedor] identifica de qué lista/proveedor provienen los datos.
  ///
  /// Si el código no existe, intenta matchear por **nombre + talle/rango**
  /// (ej. proveedor: `PAPI FEBO BLANCA 39 AL 42` → productos 39,40,41,42).
  Future<void> compararProductos(
    List<Producto> productosImportados, {
    String proveedor = '',
  }) async {
    await limpiarComparaciones();

    final base = await productoService.obtenerTodos();
    final porCodigo = <String, Producto>{
      for (final p in base) p.codigo: p,
    };
    final porBaseNombre = <String, List<_ProductoConTalle>>{};
    for (final p in base) {
      final info = TalleRangoParser.parsearProducto(
        descripcion: p.descripcion,
        talleCampo: p.talle,
      );
      porBaseNombre
          .putIfAbsent(info.baseNombre, () => [])
          .add(_ProductoConTalle(p, info.talle));
    }

    final codigosYaComparados = <String>{};

    for (final productoNuevo in productosImportados) {
      final codigo = productoNuevo.codigo.trim();
      if (codigo.isNotEmpty && porCodigo.containsKey(codigo)) {
        final productoViejo = porCodigo[codigo]!;
        await _guardarDiff(
          productoViejo: productoViejo,
          costoNuevo: productoNuevo.costo,
          descripcionMostrar: productoViejo.descripcion,
          marca: productoNuevo.marca.isNotEmpty
              ? productoNuevo.marca
              : productoViejo.marca,
          proveedor: proveedor,
        );
        codigosYaComparados.add(codigo);
        continue;
      }

      // Intentar rango / talle por descripción
      final lineaTexto = productoNuevo.descripcion.trim().isNotEmpty
          ? productoNuevo.descripcion.trim()
          : codigo;
      final linea = TalleRangoParser.parsearLineaProveedor(
        _textoConCosto(lineaTexto, productoNuevo.costo),
      );

      if (linea != null && linea.costo != null) {
        final candidatos = porBaseNombre[linea.baseNombre] ?? const [];
        final matches = candidatos.where((c) {
          if (c.talle == null) return false;
          return linea.contieneTalle(c.talle!);
        }).toList();

        if (matches.isNotEmpty) {
          for (final m in matches) {
            if (codigosYaComparados.contains(m.producto.codigo)) continue;
            await _guardarDiff(
              productoViejo: m.producto,
              costoNuevo: linea.costo!,
              descripcionMostrar:
                  '${m.producto.descripcion}  ← ${linea.etiquetaRango}',
              marca: productoNuevo.marca.isNotEmpty
                  ? productoNuevo.marca
                  : m.producto.marca,
              proveedor: proveedor,
            );
            codigosYaComparados.add(m.producto.codigo);
          }
          continue;
        }

        // Ningún producto en ese rango
        await guardarComparacion(
          Comparacion(
            codigo: codigo.isNotEmpty ? codigo : 'RANGO',
            descripcion:
                '${linea.etiquetaRango} (sin productos en base para este rango)',
            precioViejo: 0,
            precioNuevo: linea.costo!,
            estado: 'SIN_MATCH',
            marca: productoNuevo.marca,
            proveedor: proveedor,
          ),
        );
        continue;
      }

      // Sin match por código ni por rango → NUEVO
      await guardarComparacion(
        Comparacion(
          codigo: codigo.isNotEmpty ? codigo : 'NUEVO',
          descripcion: productoNuevo.descripcion,
          precioViejo: 0,
          precioNuevo: productoNuevo.costo,
          estado: 'NUEVO',
          marca: productoNuevo.marca,
          proveedor: proveedor,
        ),
      );
    }
  }

  String _textoConCosto(String texto, double costo) {
    // Si la descripción ya trae precio, no duplicar
    if (texto.contains(r'$') ||
        RegExp(r'\d{3,}\s*$').hasMatch(texto.replaceAll('.', ''))) {
      return texto;
    }
    if (costo > 0) {
      return '$texto \$${costo.toStringAsFixed(0)}';
    }
    return texto;
  }

  Future<void> _guardarDiff({
    required Producto productoViejo,
    required double costoNuevo,
    required String descripcionMostrar,
    required String marca,
    required String proveedor,
  }) async {
    String estado = 'IGUAL';
    if (costoNuevo > productoViejo.costo) {
      estado = 'SUBIO';
    } else if (costoNuevo < productoViejo.costo) {
      estado = 'BAJO';
    }
    await guardarComparacion(
      Comparacion(
        codigo: productoViejo.codigo,
        descripcion: descripcionMostrar,
        precioViejo: productoViejo.costo,
        precioNuevo: costoNuevo,
        estado: estado,
        marca: marca,
        proveedor: proveedor,
      ),
    );
  }

  /// Actualiza **únicamente el costo** de los productos en comparación.
  /// No modifica descripción, categoría, marca, proveedor, foto, precio de venta ni stock.
  /// Ignora filas `SIN_MATCH` (rangos sin productos).
  Future<void> actualizarProductos() async {
    final comparaciones = await obtenerComparacion();
    final db = await DatabaseHelper.instance.database;
    final usuario = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final ahora = DateTime.now().toIso8601String();

    for (final comp in comparaciones) {
      if (comp.estado == 'SIN_MATCH' || comp.estado == 'IGUAL') {
        continue;
      }

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
            'motivo': 'Actualización de costo por lista',
          });
        }
      } else if (comp.estado == 'NUEVO' &&
          comp.codigo.isNotEmpty &&
          comp.codigo != 'NUEVO' &&
          comp.codigo != 'RANGO') {
        await productoService.insertar(
          Producto(
            codigo: comp.codigo,
            descripcion: comp.descripcion,
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

  Future<int> cantidadSinMatch() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='SIN_MATCH'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}

class _ProductoConTalle {
  final Producto producto;
  final int? talle;
  _ProductoConTalle(this.producto, this.talle);
}
