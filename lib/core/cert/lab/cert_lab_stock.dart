import '../../../models/remito.dart';
import '../../../models/remito_detalle.dart';
import '../../../services/cliente_service.dart';
import '../../../services/producto_service.dart';
import '../../../services/remito_service.dart';
import 'cert_lab_auth.dart';
import 'cert_lab_models.dart';
import 'cert_lab_world.dart';

/// Escenarios Stock — RemitoService / ledger reales.
class CertLabStockScenarios {
  static Future<void> _publishMostrador(CertLabWorld w, CertLabNodeId node) async {
    final n = node == CertLabNodeId.windows ? w.windows : w.android;
    final c = await ClienteService().obtenerOCrearMostrador();
    await n.upsertCliente(
      syncId: 'mostrador',
      nombre: c.nombre,
      saldo: c.saldo,
    );
  }

  static List<CertLabScenario> all() => [
        CertLabScenario(
          id: 'STK-01-remito-salida-android-to-windows',
          title: 'Remito salida Android → stock Win + nube',
          tags: const ['stock', 'remito', 'real'],
          run: (w) async {
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              await _publishMostrador(w, CertLabNodeId.android);
              final svc = ProductoService();
              final p = await svc.buscarPorCodigo('pruebq');
              if (p?.id == null) throw StateError('pruebq missing');
              final stockBefore = p!.stock;
              final mostrador = await ClienteService().obtenerOCrearMostrador();
              final remitoSvc = RemitoService();
              final numero = await remitoSvc.generarNumero();
              await remitoSvc.insertar(
                Remito(
                  numero: numero,
                  fecha: DateTime.now(),
                  tipo: 'salida',
                  clienteId: '${mostrador.id}',
                  estado: 'confirmado',
                  observaciones: 'cert lab STK-01',
                  total: 30,
                  totalPagado: 30,
                ),
                [
                  RemitoDetalle(
                    remitoId: 0,
                    productoId: p.id!,
                    cantidad: 3,
                    precioUnitario: 10,
                    subtotal: 30,
                  ),
                ],
              );
              final after = await svc.buscarPorCodigo('pruebq');
              if (after == null || after.stock != stockBefore - 3) {
                throw StateError(
                  'stock local Android ${after?.stock} != ${stockBefore - 3}',
                );
              }
              w.record(
                node: CertLabNodeId.android,
                kind: 'remito_salida',
                entity: CertLabEntity.stock,
                payload: {
                  'codigo': 'pruebq',
                  'delta': -3,
                  'numero': numero,
                },
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'STK-02-remito-salida-windows-to-android',
          title: 'Remito salida Windows → stock Android + nube',
          tags: const ['stock', 'remito', 'real'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              CertLabAuth.ensureAdmin();
              await _publishMostrador(w, CertLabNodeId.windows);
              final svc = ProductoService();
              final p = await svc.buscarPorCodigo('1127');
              if (p?.id == null) throw StateError('1127 missing');
              final stockBefore = p!.stock;
              final mostrador = await ClienteService().obtenerOCrearMostrador();
              final remitoSvc = RemitoService();
              final numero = await remitoSvc.generarNumero();
              await remitoSvc.insertar(
                Remito(
                  numero: numero,
                  fecha: DateTime.now(),
                  tipo: 'salida',
                  clienteId: '${mostrador.id}',
                  estado: 'confirmado',
                  observaciones: 'cert lab STK-02',
                  total: 10,
                  totalPagado: 10,
                ),
                [
                  RemitoDetalle(
                    remitoId: 0,
                    productoId: p.id!,
                    cantidad: 2,
                    precioUnitario: 5,
                    subtotal: 10,
                  ),
                ],
              );
              final after = await svc.buscarPorCodigo('1127');
              if (after == null || after.stock != stockBefore - 2) {
                throw StateError(
                  'stock local Win ${after?.stock} != ${stockBefore - 2}',
                );
              }
              w.record(
                node: CertLabNodeId.windows,
                kind: 'remito_salida',
                entity: CertLabEntity.stock,
                payload: {'codigo': '1127', 'delta': -2, 'numero': numero},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'STK-03-ajuste-entrada-ambos',
          title: 'Ajustes entrada concurrentes SKUs distintos',
          tags: const ['stock', 'ajuste', 'concurrencia'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              await w.windows.applyLocalStockDelta(
                codigo: 'SKU-A',
                delta: 5,
                opId:
                    'stk:ajuste:win:sku-a:${DateTime.now().microsecondsSinceEpoch}',
              );
            });
            await w.withNode(w.android, () async {
              await w.android.applyLocalStockDelta(
                codigo: 'pruebq',
                delta: 2,
                opId:
                    'stk:ajuste:apk:pruebq:${DateTime.now().microsecondsSinceEpoch}',
              );
            });
            w.record(
              node: CertLabNodeId.windows,
              kind: 'ajuste',
              entity: CertLabEntity.stock,
              payload: {'codigo': 'SKU-A', 'delta': 5},
            );
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'STK-04-offline-remito-reconnect',
          title: 'Remito offline Android + reconexión',
          tags: const ['stock', 'offline', 'remito'],
          run: (w) async {
            w.android.online = false;
            late String numero;
            final opsBefore = w.cloud.stockOps.length;
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              await _publishMostrador(w, CertLabNodeId.android);
              final p = await ProductoService().buscarPorCodigo('SKU-A');
              if (p?.id == null) throw StateError('SKU-A missing');
              final mostrador = await ClienteService().obtenerOCrearMostrador();
              final remitoSvc = RemitoService();
              numero = await remitoSvc.generarNumero();
              await remitoSvc.insertar(
                Remito(
                  numero: numero,
                  fecha: DateTime.now(),
                  tipo: 'salida',
                  clienteId: '${mostrador.id}',
                  estado: 'confirmado',
                  observaciones: 'cert lab STK-04 offline',
                  total: 1,
                  totalPagado: 1,
                ),
                [
                  RemitoDetalle(
                    remitoId: 0,
                    productoId: p!.id!,
                    cantidad: 1,
                    precioUnitario: 1,
                    subtotal: 1,
                  ),
                ],
              );
              w.record(
                node: CertLabNodeId.android,
                kind: 'remito_offline',
                entity: CertLabEntity.stock,
                payload: {'codigo': 'SKU-A', 'delta': -1, 'numero': numero},
              );
            });
            await w.withNode(w.android, () async {
              await w.bridge.flush(w.android);
            });
            if (w.cloud.stockOps.length != opsBefore) {
              throw StateError(
                'offline no debe publicar stock_ops '
                '(antes=$opsBefore ahora=${w.cloud.stockOps.length})',
              );
            }
            w.android.online = true;
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'STK-05-stress-40-deltas',
          title: '40 deltas stock (20+20) sin pérdida',
          tags: const ['stock', 'stress'],
          run: (w) async {
            final ts = DateTime.now().microsecondsSinceEpoch;
            await w.withNode(w.windows, () async {
              for (var i = 0; i < 20; i++) {
                await w.windows.applyLocalStockDelta(
                  codigo: 'SKU-A',
                  delta: i.isEven ? -1 : 1,
                  opId: 'stk:stress:win:$ts:$i',
                );
              }
            });
            await w.withNode(w.android, () async {
              for (var i = 0; i < 20; i++) {
                await w.android.applyLocalStockDelta(
                  codigo: 'SKU-A',
                  delta: i.isEven ? 1 : -1,
                  opId: 'stk:stress:apk:$ts:$i',
                );
              }
            });
            w.record(
              node: CertLabNodeId.firestore,
              kind: 'stress',
              entity: CertLabEntity.stock,
              payload: {'ops': 40},
            );
            await w.syncAll();
          },
        ),
      ];
}
