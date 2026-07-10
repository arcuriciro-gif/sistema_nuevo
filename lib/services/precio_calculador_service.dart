import '../models/lista_precio.dart';
import '../models/producto.dart';
import 'lista_precio_service.dart';

/// Recalcula listas de precios cuando cambia el costo.
class PrecioCalculadorService {
  PrecioCalculadorService._();

  static final PrecioCalculadorService instance = PrecioCalculadorService._();

  final ListaPrecioService _listaPrecioService = ListaPrecioService();

  Future<Producto> aplicarListasDesdeCosto(
    Producto producto, {
    List<ListaPrecio>? listasActivas,
    bool forzar = false,
  }) async {
    if (producto.costo <= 0) return producto;

    final listas = listasActivas ?? await _listaPrecioService.obtenerActivas();
    if (listas.isEmpty) return producto;

    final precios = Map<String, double>.from(producto.preciosListas);
    var actualizado = producto;

    for (final lista in listas) {
      final listaId = lista.id?.toString() ?? lista.nombre;
      final bloqueado = producto.preciosBloqueados.contains(listaId);
      if (bloqueado && !forzar) continue;
      precios[listaId] = lista.calcularPrecio(producto.costo);
    }

    actualizado = actualizado.copyWith(preciosListas: precios);

    // Compatibilidad con las 3 listas históricas del sistema.
    final ordenadas = [...listas]
      ..sort((a, b) => a.orden.compareTo(b.orden));
    final p1 = ordenadas.isNotEmpty
        ? precios[ordenadas[0].id?.toString() ?? ordenadas[0].nombre]
        : null;
    final p2 = ordenadas.length > 1
        ? precios[ordenadas[1].id?.toString() ?? ordenadas[1].nombre]
        : null;
    final p3 = ordenadas.length > 2
        ? precios[ordenadas[2].id?.toString() ?? ordenadas[2].nombre]
        : null;

    return actualizado.copyWith(
      precio: p1 ?? actualizado.precio,
      precio2: p2 ?? actualizado.precio2,
      precio3: p3 ?? actualizado.precio3,
      foto: actualizado.fotoPrincipal,
      fotos: actualizado.todasLasFotos,
    );
  }
}
