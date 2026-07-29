import '../../../models/remito.dart';
import '../../../models/remito_detalle.dart';
import '../../../services/cliente_service.dart';
import '../../../services/producto_service.dart';
import '../../../services/remito_service.dart';
import 'cert_lab_auth.dart';
import 'cert_lab_models.dart';
import 'cert_lab_world.dart';

/// Escenarios Remitos (documento + stock vía RemitoService real).
class CertLabRemitosScenarios {
  static List<CertLabScenario> all() => [
        CertLabScenario(
          id: 'REM-01-crear-y-converger',
          title: 'Crear remito Win → stock convergido en Android',
          tags: const ['remitos', 'real'],
          run: (w) async {
            late String numero;
            await w.withNode(w.windows, () async {
              CertLabAuth.ensureAdmin();
              final p = await ProductoService().buscarPorCodigo('pruebq');
              if (p?.id == null) throw StateError('pruebq missing');
              final mostrador = await ClienteService().obtenerOCrearMostrador();
              await w.windows.upsertCliente(
                syncId: 'mostrador',
                nombre: mostrador.nombre,
                saldo: mostrador.saldo,
              );
              final remitoSvc = RemitoService();
              numero = await remitoSvc.generarNumero();
              await remitoSvc.insertar(
                Remito(
                  numero: numero,
                  fecha: DateTime.now(),
                  tipo: 'salida',
                  clienteId: '${mostrador.id}',
                  estado: 'confirmado',
                  observaciones: 'cert REM-01',
                  total: 10,
                  totalPagado: 10,
                ),
                [
                  RemitoDetalle(
                    remitoId: 0,
                    productoId: p!.id!,
                    cantidad: 1,
                    precioUnitario: 10,
                    subtotal: 10,
                  ),
                ],
              );
              w.record(
                node: CertLabNodeId.windows,
                kind: 'remito_crear',
                entity: CertLabEntity.remito,
                payload: {'numero': numero, 'codigo': 'pruebq', 'delta': -1},
              );
            });
            await w.syncAll();
            await w.withNode(w.android, () async {
              final stock = await w.android.stockOf('pruebq');
              if (stock != 49) {
                throw StateError(
                  'stock pruebq Android=$stock expected 49 (seed 50 - 1)',
                );
              }
            });
          },
        ),
      ];
}

class CertLabClientesScenarios {
  static List<CertLabScenario> all() => [
        CertLabScenario(
          id: 'CLI-01-alta-mostrador-sync',
          title: 'Cliente/mostrador Android → Windows',
          tags: const ['clientes', 'real'],
          run: (w) async {
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              final c = await ClienteService().obtenerOCrearMostrador();
              await w.android.upsertCliente(
                syncId: 'cli_mostrador',
                nombre: c.nombre,
                saldo: c.saldo,
              );
              w.record(
                node: CertLabNodeId.android,
                kind: 'cliente_alta',
                entity: CertLabEntity.cliente,
                payload: {'nombre': c.nombre},
              );
            });
            await w.syncAll();
            await w.withNode(w.windows, () async {
              final db = await w.windows.database;
              final rows = await db.query(
                'clientes',
                where: 'nombre = ?',
                whereArgs: ['MOSTRADOR'],
                limit: 1,
              );
              if (rows.isEmpty) {
                throw StateError('MOSTRADOR no llegó a Windows');
              }
            });
          },
        ),
      ];
}
