import '../core/events/data_refresh_hub.dart';
import '../database/database_helper.dart';
import '../models/crm_seguimiento.dart';

/// Agenda de seguimientos comerciales — solo local, sin outbox/sync.
class CrmSeguimientoService {
  CrmSeguimientoService._();
  static final CrmSeguimientoService instance = CrmSeguimientoService._();

  Future<List<CrmSeguimiento>> listarPendientes({int limite = 80}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'crm_seguimientos',
      where: "estado = 'pendiente'",
      orderBy: 'datetime(fechaVencimiento) ASC',
      limit: limite,
    );
    return rows.map(CrmSeguimiento.fromMap).toList();
  }

  Future<List<CrmSeguimiento>> listarDeCliente(int clienteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'crm_seguimientos',
      where: 'clienteId = ?',
      whereArgs: [clienteId],
      orderBy: 'datetime(fechaVencimiento) DESC',
      limit: 40,
    );
    return rows.map(CrmSeguimiento.fromMap).toList();
  }

  Future<int> contarPendientes() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM crm_seguimientos WHERE estado = 'pendiente'",
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> contarVencidos() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM crm_seguimientos
      WHERE estado = 'pendiente'
        AND datetime(fechaVencimiento) < datetime('now')
      ''',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> crear(CrmSeguimiento s) async {
    final db = await DatabaseHelper.instance.database;
    final map = s.toMap()..remove('id');
    final id = await db.insert('crm_seguimientos', map);
    DataRefreshHub.instance.notifyTodo();
    return id;
  }

  Future<void> marcarHecho(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'crm_seguimientos',
      {
        'estado': 'hecho',
        'completadoEn': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> cancelar(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'crm_seguimientos',
      {
        'estado': 'cancelado',
        'completadoEn': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    DataRefreshHub.instance.notifyTodo();
  }

  Future<void> eliminar(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('crm_seguimientos', where: 'id = ?', whereArgs: [id]);
    DataRefreshHub.instance.notifyTodo();
  }
}
