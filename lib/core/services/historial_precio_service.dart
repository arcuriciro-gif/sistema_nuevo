import '../database/database_helper.dart';

class HistorialPrecioService {
  final DatabaseHelper dbHelper = DatabaseHelper.instance;

  Future<int> registrar({
    required int productoId,
    required String usuario,
    required double costoAnterior,
    required double costoNuevo,
    String motivo = '',
  }) async {
    final db = await dbHelper.database;
    return db.insert('historial_precios', {
      'productoId': productoId,
      'fecha': DateTime.now().toIso8601String(),
      'usuario': usuario,
      'costoAnterior': costoAnterior,
      'costoNuevo': costoNuevo,
      'motivo': motivo,
    });
  }

  Future<List<Map<String, dynamic>>> obtenerPorProducto(int productoId) async {
    final db = await dbHelper.database;
    return db.query(
      'historial_precios',
      where: 'productoId = ?',
      whereArgs: [productoId],
      orderBy: 'datetime(fecha) DESC, id DESC',
    );
  }
}
