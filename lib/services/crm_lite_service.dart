import '../database/database_helper.dart';
import '../models/cliente.dart';
import '../services/cliente_service.dart';
import '../services/comentario_interno_service.dart';
import '../services/cuenta_corriente_service.dart';

/// Lectura agregada para Seguimiento comercial (CRM Lite).
/// Sin sync, sin tablas nuevas: solo SQLite local existente.
class CrmLiteService {
  CrmLiteService._();
  static final CrmLiteService instance = CrmLiteService._();

  final _clientes = ClienteService();
  final _cc = CuentaCorrienteService();
  final _notas = ComentarioInternoService.instance;

  Future<List<ClienteDeudor>> deudores({int limite = 30}) async {
    final todos = await _cc.clientesDeudores();
    return todos.take(limite).toList();
  }

  /// Clientes sin remitos confirmados en los últimos [dias] días.
  Future<List<Map<String, dynamic>>> inactivos({
    int dias = 30,
    int limite = 40,
  }) async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery(
      '''
      SELECT c.id, c.nombre, c.apellido, c.telefono, c.whatsapp, c.email
      FROM clientes c
      LEFT JOIN remitos r
        ON r.clienteId = c.id
       AND r.estado != 'anulado'
       AND datetime(r.fecha) >= datetime('now', ?)
      WHERE r.id IS NULL
        AND LOWER(TRIM(c.nombre)) != 'mostrador'
      ORDER BY c.nombre
      LIMIT ?
      ''',
      ['-$dias days', limite],
    );
  }

  Future<List<Map<String, dynamic>>> conNotasRecientes({int limite = 20}) async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery(
      '''
      SELECT c.id, c.nombre, c.apellido, c.telefono, c.whatsapp,
             MAX(ci.fecha) AS ultimaNota,
             COUNT(ci.id) AS cantidadNotas
      FROM comentarios_internos ci
      INNER JOIN clientes c ON CAST(c.id AS TEXT) = ci.entidadId
      WHERE ci.entidadTipo = 'cliente'
        AND ci.activo = 1
      GROUP BY c.id
      ORDER BY datetime(MAX(ci.fecha)) DESC
      LIMIT ?
      ''',
      [limite],
    );
  }

  Future<Cliente?> obtenerCliente(int id) async {
    final todos = await _clientes.obtenerTodos();
    for (final c in todos) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<int> contarNotasCliente(int clienteId) {
    return _notas.contar(
      entidadTipo: 'cliente',
      entidadId: '$clienteId',
    );
  }

  Future<CrmLiteResumen> resumen() async {
    final d = await deudores(limite: 500);
    final i = await inactivos(limite: 500);
    final n = await conNotasRecientes(limite: 500);
    final deuda = d.fold<double>(0, (s, e) => s + e.saldoPendiente);
    return CrmLiteResumen(
      deudores: d.length,
      inactivos: i.length,
      conNotas: n.length,
      deudaTotal: deuda,
    );
  }
}

class CrmLiteResumen {
  final int deudores;
  final int inactivos;
  final int conNotas;
  final double deudaTotal;

  const CrmLiteResumen({
    required this.deudores,
    required this.inactivos,
    required this.conNotas,
    required this.deudaTotal,
  });
}
