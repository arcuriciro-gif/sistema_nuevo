import 'package:sqflite/sqflite.dart';
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

  /// Compara la lista importada contra la base usando el campo [costo].
  /// [proveedor] identifica de qué lista/proveedor provienen los datos.
  Future<void> compararProductos(
    List<Producto> productosImportados, {
    String proveedor = '',
  }) async {
    await limpiarComparaciones();
    for (final productoNuevo in productosImportados) {
      final productoViejo =
          await productoService.buscarPorCodigo(productoNuevo.codigo);
      if (productoViejo == null) {
        await guardarComparacion(
          Comparacion(
            codigo: productoNuevo.codigo,
            descripcion: productoNuevo.descripcion,
            precioViejo: 0,
            precioNuevo: productoNuevo.costo,
            estado: 'NUEVO',
            marca: productoNuevo.marca,
            proveedor: proveedor,
          ),
        );
        continue;
      }
      String estado = 'IGUAL';
      if (productoNuevo.costo > productoViejo.costo) {
        estado = 'SUBIO';
      } else if (productoNuevo.costo < productoViejo.costo) {
        estado = 'BAJO';
      }
      await guardarComparacion(
        Comparacion(
          codigo: productoNuevo.codigo,
          descripcion: productoNuevo.descripcion,
          precioViejo: productoViejo.costo,
          precioNuevo: productoNuevo.costo,
          estado: estado,
          marca: productoNuevo.marca,
          proveedor: proveedor,
        ),
      );
    }
  }

  /// Actualiza **únicamente el costo** de los productos en comparación.
  /// No modifica descripción, categoría, marca, proveedor, foto, precio de venta ni stock.
  Future<void> actualizarProductos() async {
    final comparaciones = await obtenerComparacion();
    final db = await DatabaseHelper.instance.database;
    final usuario = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final ahora = DateTime.now().toIso8601String();

    for (final comp in comparaciones) {
      final producto = await productoService.buscarPorCodigo(comp.codigo);
      if (producto != null) {
        if (comp.precioNuevo != comp.precioViejo) {
          // Actualizar solo costo, mantener precio de venta y demás campos
          await db.update(
            'productos',
            {'costo': comp.precioNuevo},
            where: 'id = ?',
            whereArgs: [producto.id],
          );

          // Registrar historial
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
      } else if (comp.estado == 'NUEVO') {
        // Crear producto nuevo con solo los datos del CSV/Excel
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
}
