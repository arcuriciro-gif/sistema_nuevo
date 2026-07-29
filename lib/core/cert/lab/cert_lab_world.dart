import 'dart:io';

import '../../sync/cloud_sync_throttle.dart';
import 'cert_lab_auth.dart';
import 'cert_lab_cloud.dart';
import 'cert_lab_engine_manifest.dart';
import 'cert_lab_models.dart';
import 'cert_lab_node.dart';
import 'cert_lab_oracle.dart';

typedef CertLabScenarioFn = Future<void> Function(CertLabWorld world);

class CertLabScenario {
  const CertLabScenario({
    required this.id,
    required this.title,
    required this.run,
    this.tags = const [],
  });

  final String id;
  final String title;
  final CertLabScenarioFn run;
  final List<String> tags;
}

/// Mundo del laboratorio: 2 nodos + nube + bitácora de eventos.
class CertLabWorld {
  CertLabWorld({
    required this.windows,
    required this.android,
    required this.cloud,
    required this.bridge,
    required this.seedStock,
    required this.seedPrecios,
  });

  final CertLabNode windows;
  final CertLabNode android;
  final CertLabCloud cloud;
  final CertLabBridge bridge;
  final Map<String, int> seedStock;
  final Map<String, double> seedPrecios;

  final List<CertLabEvent> events = [];
  var _seq = 0;

  void record({
    required CertLabNodeId node,
    required String kind,
    required CertLabEntity entity,
    Map<String, dynamic> payload = const {},
  }) {
    events.add(
      CertLabEvent(
        seq: ++_seq,
        at: DateTime.now().toUtc(),
        node: node,
        kind: kind,
        entity: entity,
        payload: payload,
      ),
    );
  }

  static Future<CertLabWorld> create({
    Map<String, ({int stock, double precio})>? catalog,
  }) async {
    final cat = catalog ??
        {
          'pruebq': (stock: 50, precio: 10),
          '1127': (stock: 20, precio: 5),
          'SKU-A': (stock: 100, precio: 1),
        };
    final seedStock = {for (final e in cat.entries) e.key: e.value.stock};
    final seedPrecios = {for (final e in cat.entries) e.key: e.value.precio};

    final dirW = await Directory.systemTemp.createTemp('certlab_win_');
    final dirA = await Directory.systemTemp.createTemp('certlab_apk_');
    final win = CertLabNode(
      id: CertLabNodeId.windows,
      label: 'windows',
      dir: dirW,
    );
    final apk = CertLabNode(
      id: CertLabNodeId.android,
      label: 'android',
      dir: dirA,
    );
    final cloud = CertLabCloud();
    final bridge = CertLabBridge(cloud);

    await win.open();
    await win.seedProductos(cat);
    await win.close();

    await apk.open();
    await apk.seedProductos(cat);
    await apk.close();

    // Metadatos de catálogo en nube (stock NO es autoridad).
    for (final e in cat.entries) {
      cloud.upsert('productos', e.key, {
        'codigo': e.key,
        'descripcion': e.key,
        'precio': e.value.precio,
        // stock omitido / no autoridad
      });
    }

    return CertLabWorld(
      windows: win,
      android: apk,
      cloud: cloud,
      bridge: bridge,
      seedStock: seedStock,
      seedPrecios: seedPrecios,
    );
  }

  Future<void> withNode(CertLabNode node, Future<void> Function() fn) async {
    await node.open();
    CertLabAuth.ensureAdmin();
    try {
      await fn();
      // Dejar que jobs bg de ProductoService no escriban DB cerrada.
      CloudSyncThrottle.resetForTests();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    } finally {
      CloudSyncThrottle.resetForTests();
      await node.close();
    }
  }

  Future<void> syncAll() async {
    await withNode(windows, () async {
      await bridge.flush(windows);
      await bridge.pull(windows);
    });
    await withNode(android, () async {
      await bridge.flush(android);
      await bridge.pull(android);
    });
    await withNode(windows, () async {
      await bridge.pull(windows);
      await bridge.flush(windows);
    });
    await withNode(android, () async {
      await bridge.pull(android);
      await bridge.flush(android);
    });
  }

  Future<CertLabFailure?> assertConverged(String scenarioId) async {
    late CertLabSnapshot snapW;
    late CertLabSnapshot snapA;
    await withNode(windows, () async {
      snapW = await windows.snapshot();
    });
    await withNode(android, () async {
      snapA = await android.snapshot();
    });
    final snapF = cloud.snapshot(
      seedStock: seedStock,
      seedPrecios: seedPrecios,
    );
    return CertLabOracle.compareTriple(
      scenarioId: scenarioId,
      windows: snapW,
      android: snapA,
      firestore: snapF,
      events: events,
    );
  }

  Future<void> dispose() async {
    try {
      await windows.close();
    } catch (_) {}
    try {
      await android.close();
    } catch (_) {}
    try {
      await windows.dir.delete(recursive: true);
    } catch (_) {}
    try {
      await android.dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Batería P0 del laboratorio (protocolo + contrato de motor).
class CertLabBattery {
  static List<CertLabScenario> p0() => [
        CertLabScenario(
          id: 'P0-01-stock-venta-android-to-windows',
          title: 'Venta en Android → stock igual en Windows y Firestore',
          tags: const ['stock', 'venta', 'sync'],
          run: (w) async {
            await w.withNode(w.android, () async {
              await w.android.applyLocalStockDelta(
                codigo: 'pruebq',
                delta: -3,
                opId: 'lab:venta:apk:pruebq:1',
                documentType: 'venta',
                documentId: 'V-LAB-1',
              );
              w.record(
                node: CertLabNodeId.android,
                kind: 'venta',
                entity: CertLabEntity.stock,
                payload: {'codigo': 'pruebq', 'delta': -3},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-02-stock-venta-windows-to-android',
          title: 'Venta en Windows → stock igual en Android y Firestore',
          tags: const ['stock', 'venta', 'sync'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              await w.windows.applyLocalStockDelta(
                codigo: '1127',
                delta: -2,
                opId: 'lab:venta:win:1127:1',
                documentType: 'venta',
                documentId: 'V-LAB-2',
              );
              w.record(
                node: CertLabNodeId.windows,
                kind: 'venta',
                entity: CertLabEntity.stock,
                payload: {'codigo': '1127', 'delta': -2},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-03-ajuste-ambos-sentidos',
          title: 'Ajustes Win+Android sobre SKUs distintos convergen',
          tags: const ['stock', 'ajuste'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              await w.windows.applyLocalStockDelta(
                codigo: 'SKU-A',
                delta: 7,
                opId: 'lab:ajuste:win:sku-a:1',
              );
              w.record(
                node: CertLabNodeId.windows,
                kind: 'ajuste',
                entity: CertLabEntity.stock,
                payload: {'codigo': 'SKU-A', 'delta': 7},
              );
            });
            await w.withNode(w.android, () async {
              await w.android.applyLocalStockDelta(
                codigo: 'pruebq',
                delta: 4,
                opId: 'lab:ajuste:apk:pruebq:1',
              );
              w.record(
                node: CertLabNodeId.android,
                kind: 'ajuste',
                entity: CertLabEntity.stock,
                payload: {'codigo': 'pruebq', 'delta': 4},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-04-precio-modificacion',
          title: 'Cambio de precio en Windows llega a Android y nube',
          tags: const ['precio', 'producto'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              await w.windows.setPrecio('1127', 99.5);
              w.record(
                node: CertLabNodeId.windows,
                kind: 'set_precio',
                entity: CertLabEntity.precio,
                payload: {'codigo': '1127', 'precio': 99.5},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-05-cliente-alta',
          title: 'Alta de cliente en Android aparece en Windows y nube',
          tags: const ['cliente'],
          run: (w) async {
            await w.withNode(w.android, () async {
              await w.android.upsertCliente(
                syncId: 'cli_lab_1',
                nombre: 'Cliente Lab',
                saldo: 150,
              );
              w.record(
                node: CertLabNodeId.android,
                kind: 'alta_cliente',
                entity: CertLabEntity.cliente,
                payload: {'syncId': 'cli_lab_1', 'nombre': 'Cliente Lab'},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-06-proveedor-alta',
          title: 'Alta de proveedor en Windows aparece en Android y nube',
          tags: const ['proveedor'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              await w.windows.upsertProveedor(
                syncId: 'prov_lab_1',
                nombre: 'Proveedor Lab',
              );
              w.record(
                node: CertLabNodeId.windows,
                kind: 'alta_proveedor',
                entity: CertLabEntity.proveedor,
                payload: {'syncId': 'prov_lab_1', 'nombre': 'Proveedor Lab'},
              );
            });
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-07-offline-android-reconnect',
          title: 'Android offline vende; al reconectar converge',
          tags: const ['offline', 'reconnect', 'stock'],
          run: (w) async {
            w.android.online = false;
            await w.withNode(w.android, () async {
              await w.android.applyLocalStockDelta(
                codigo: 'SKU-A',
                delta: -5,
                opId: 'lab:venta:apk:offline:1',
                documentType: 'venta',
              );
              w.record(
                node: CertLabNodeId.android,
                kind: 'venta_offline',
                entity: CertLabEntity.stock,
                payload: {'codigo': 'SKU-A', 'delta': -5},
              );
            });
            // Intento de sync mientras offline: no debe subir.
            await w.withNode(w.android, () async {
              await w.bridge.flush(w.android);
            });
            if (w.cloud.hasStockOp('lab:venta:apk:offline:1')) {
              throw StateError('flush offline no debe publicar stock_op');
            }
            w.android.online = true;
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-08-offline-windows-reconnect',
          title: 'Windows offline ajusta; al reconectar converge',
          tags: const ['offline', 'reconnect', 'stock'],
          run: (w) async {
            w.windows.online = false;
            await w.withNode(w.windows, () async {
              await w.windows.applyLocalStockDelta(
                codigo: '1127',
                delta: 3,
                opId: 'lab:ajuste:win:offline:1',
              );
              w.record(
                node: CertLabNodeId.windows,
                kind: 'ajuste_offline',
                entity: CertLabEntity.stock,
                payload: {'codigo': '1127', 'delta': 3},
              );
            });
            w.windows.online = true;
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-09-concurrencia-skus-distintos',
          title: 'Ventas concurrentes en SKUs distintos convergen',
          tags: const ['concurrencia', 'stock'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              await w.windows.applyLocalStockDelta(
                codigo: 'pruebq',
                delta: -1,
                opId: 'lab:conc:win:pruebq:1',
                documentType: 'venta',
              );
            });
            await w.withNode(w.android, () async {
              await w.android.applyLocalStockDelta(
                codigo: '1127',
                delta: -1,
                opId: 'lab:conc:apk:1127:1',
                documentType: 'venta',
              );
            });
            w.record(
              node: CertLabNodeId.windows,
              kind: 'concurrent_sale',
              entity: CertLabEntity.stock,
              payload: {'codigo': 'pruebq', 'delta': -1},
            );
            w.record(
              node: CertLabNodeId.android,
              kind: 'concurrent_sale',
              entity: CertLabEntity.stock,
              payload: {'codigo': '1127', 'delta': -1},
            );
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-10-stress-80-ops',
          title: '80 movimientos stock (40+40) sin pérdida',
          tags: const ['stress', 'stock'],
          run: (w) async {
            await w.withNode(w.windows, () async {
              for (var i = 0; i < 40; i++) {
                await w.windows.applyLocalStockDelta(
                  codigo: 'SKU-A',
                  delta: i.isEven ? -1 : 1,
                  opId: 'lab:stress:win:$i',
                );
              }
            });
            await w.withNode(w.android, () async {
              for (var i = 0; i < 40; i++) {
                await w.android.applyLocalStockDelta(
                  codigo: 'SKU-A',
                  delta: i.isEven ? 1 : -1,
                  opId: 'lab:stress:apk:$i',
                );
              }
            });
            w.record(
              node: CertLabNodeId.firestore,
              kind: 'stress',
              entity: CertLabEntity.stock,
              payload: {'ops': 80, 'codigo': 'SKU-A'},
            );
            await w.syncAll();
          },
        ),
        CertLabScenario(
          id: 'P0-99-engine-contract-windows-inbound',
          title:
              'Contrato motor: Windows inbound stock automático certificado',
          tags: const ['engine', 'contract', 'gate'],
          run: (w) async {
            // No modifica Sync Engine. Lee manifiesto del lab.
            if (!CertLabEngineManifest.windowsAutomaticStockInboundCertified) {
              throw CertLabContractException(
                CertLabFailure(
                  scenarioId: 'P0-99-engine-contract-windows-inbound',
                  entity: CertLabEntity.stock,
                  where: 'CertLabEngineManifest.windowsAutomaticStockInboundCertified',
                  message:
                      'Capacidad no certificada: Windows no demuestra recepción '
                      'automática de stock_ops (campo: pruebq/1127 divergentes; '
                      'freeze/manual-only en ramas de estabilización).',
                  expected:
                      'windowsAutomaticStockInboundCertified == true '
                      'con P0-01..P0-10 verdes + evidencia de campo',
                  actual: 'windowsAutomaticStockInboundCertified == false',
                  file: 'lib/core/cert/lab/cert_lab_engine_manifest.dart',
                  clazz: 'CertLabEngineManifest',
                  method: 'windowsAutomaticStockInboundCertified',
                  firestorePath: 'tenants/{tenant}/stock_ops/{opId}',
                  hint:
                      'Laboratorio listo. Cuando se autorice tocar el Sync Engine, '
                      'corregir UNO: inbound Windows seguro. Luego poner este flag '
                      'en true SOLO con evidencia. Hasta entonces: CERT_LAB_RED.',
                ),
              );
            }
          },
        ),
      ];
}

class CertLabContractException implements Exception {
  CertLabContractException(this.failure);
  final CertLabFailure failure;
  @override
  String toString() => failure.message;
}
