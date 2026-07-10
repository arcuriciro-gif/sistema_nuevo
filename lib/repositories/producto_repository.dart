import '../models/producto.dart';

abstract class ProductoRepository {
  Future<int> insertar(Producto producto);
  Future<void> insertarLista(List<Producto> productos);
  Future<List<Producto>> obtenerTodos({int? limit, int? offset});
  Future<Producto?> buscarPorCodigo(String codigo);
  Future<Producto?> buscarPorCodigoBarras(String codigoBarras);
  Future<bool> tieneProductos();
  Future<int> actualizar(Producto producto);
  Future<int> eliminar(int id);
  Stream<List<Producto>> watchTodos({int limit = 200});
}
