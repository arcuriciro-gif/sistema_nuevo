import '../../../models/producto.dart';
import '../../../services/producto_service.dart';
import 'cert_lab_auth.dart';
import 'cert_lab_models.dart';
import 'cert_lab_world.dart';

/// Escenarios del módulo Productos usando ProductoService real.
class CertLabProductosScenarios {
  static List<CertLabScenario> all() => [
        CertLabScenario(
          id: 'PROD-01-alta-android-to-windows',
          title: 'Alta producto (ProductoService) Android → Win + nube',
          tags: const ['productos', 'alta', 'real'],
          run: (w) async {
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              final svc = ProductoService();
              await svc.insertar(
                Producto(
                  codigo: 'LAB-P1',
                  descripcion: 'Producto Lab 1',
                  marca: 'Lab',
                  categoria: 'Test',
                  proveedor: 'LabProv',
                  ubicacion: '',
                  stock: 10,
                  precio: 100,
                  costo: 50,
                  observaciones: '',
                  foto: '',
                ),
              );
              await w.bridge.publishProductoCodigo('LAB-P1');
              w.record(
                node: CertLabNodeId.android,
                kind: 'alta_producto_service',
                entity: CertLabEntity.producto,
                payload: {'codigo': 'LAB-P1', 'precio': 100, 'stock': 10},
              );
            });
            await w.syncAll();
            // Seed stock for cloud projection includes only initial catalog;
            // alta adds new product — update seed for oracle stock projection.
            w.seedStock['LAB-P1'] = 0;
            w.seedPrecios['LAB-P1'] = 100;
          },
        ),
        CertLabScenario(
          id: 'PROD-02-precio-windows-to-android',
          title: 'Cambio precio (ProductoService) Win → Android',
          tags: const ['productos', 'precio', 'real'],
          run: (w) async {
            // Ensure product exists both sides first
            await w.withNode(w.windows, () async {
              CertLabAuth.ensureAdmin();
              final svc = ProductoService();
              final existing = await svc.buscarPorCodigo('pruebq');
              if (existing == null) {
                throw StateError('pruebq debe existir en seed');
              }
              await svc.actualizar(
                existing.copyWith(precio: 77.7, stock: existing.stock),
              );
              await w.bridge.publishProductoCodigo('pruebq');
              w.record(
                node: CertLabNodeId.windows,
                kind: 'update_precio_service',
                entity: CertLabEntity.precio,
                payload: {'codigo': 'pruebq', 'precio': 77.7},
              );
            });
            await w.syncAll();
            w.seedPrecios['pruebq'] = 77.7;
          },
        ),
        CertLabScenario(
          id: 'PROD-03-descripcion-categoria',
          title: 'Modificar descripción y categoría Android → Win',
          tags: const ['productos', 'modificacion', 'real'],
          run: (w) async {
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              final svc = ProductoService();
              final p = await svc.buscarPorCodigo('1127');
              if (p == null) throw StateError('1127 seed missing');
              await svc.actualizar(
                p.copyWith(
                  descripcion: 'ABROJO LAB CERT',
                  categoria: 'CertCat',
                  stock: p.stock,
                ),
              );
              await w.bridge.publishProductoCodigo('1127');
              w.record(
                node: CertLabNodeId.android,
                kind: 'update_desc',
                entity: CertLabEntity.producto,
                payload: {
                  'codigo': '1127',
                  'descripcion': 'ABROJO LAB CERT',
                },
              );
            });
            await w.syncAll();
            // Verify description on Windows
            await w.withNode(w.windows, () async {
              CertLabAuth.ensureAdmin();
              final p = await ProductoService().buscarPorCodigo('1127');
              if (p?.descripcion != 'ABROJO LAB CERT') {
                throw StateError(
                  'descripcion Win=${p?.descripcion} expected ABROJO LAB CERT',
                );
              }
              if (p?.categoria != 'CertCat') {
                throw StateError('categoria Win=${p?.categoria}');
              }
            });
          },
        ),
        CertLabScenario(
          id: 'PROD-04-baja-soft-delete',
          title: 'Baja soft (papelera) Win → Android',
          tags: const ['productos', 'baja', 'real'],
          run: (w) async {
            const code = 'SKU-A';
            await w.withNode(w.windows, () async {
              CertLabAuth.ensureAdmin();
              final svc = ProductoService();
              final p = await svc.buscarPorCodigo(code);
              if (p?.id == null) throw StateError('$code missing');
              await svc.eliminar(p!.id!);
              await w.bridge.publishProductoCodigo(code);
              w.record(
                node: CertLabNodeId.windows,
                kind: 'soft_delete',
                entity: CertLabEntity.producto,
                payload: {'codigo': code},
              );
            });
            await w.syncAll();
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              final active = await ProductoService().buscarPorCodigo(code);
              if (active != null) {
                throw StateError('SKU-A aún activo en Android tras baja');
              }
            });
            // Soft-deleted products leave oracle counts — remove from seed maps
            w.seedStock.remove(code);
            w.seedPrecios.remove(code);
          },
        ),
        CertLabScenario(
          id: 'PROD-05-offline-alta-reconnect',
          title: 'Alta offline Android + reconexión',
          tags: const ['productos', 'offline', 'real'],
          run: (w) async {
            w.android.online = false;
            await w.withNode(w.android, () async {
              CertLabAuth.ensureAdmin();
              await ProductoService().insertar(
                Producto(
                  codigo: 'LAB-OFF',
                  descripcion: 'Offline Product',
                  marca: 'Lab',
                  categoria: 'Off',
                  proveedor: 'LabProv',
                  ubicacion: '',
                  stock: 2,
                  precio: 9,
                  costo: 3,
                  observaciones: '',
                  foto: '',
                ),
              );
              // No publish directo: offline solo debe quedar local.
              w.record(
                node: CertLabNodeId.android,
                kind: 'alta_offline',
                entity: CertLabEntity.producto,
                payload: {'codigo': 'LAB-OFF'},
              );
            });
            await w.withNode(w.android, () async {
              await w.bridge.flush(w.android);
            });
            if (w.cloud.get('productos', 'LAB-OFF') != null) {
              throw StateError('offline no debe publicar a nube');
            }
            w.android.online = true;
            await w.withNode(w.android, () async {
              await w.bridge.publishProductoCodigo('LAB-OFF');
              await w.bridge.flush(w.android);
            });
            await w.syncAll();
            w.seedStock['LAB-OFF'] = 0;
            w.seedPrecios['LAB-OFF'] = 9;
            await w.withNode(w.windows, () async {
              CertLabAuth.ensureAdmin();
              final p = await ProductoService().buscarPorCodigo('LAB-OFF');
              if (p == null) {
                throw StateError('LAB-OFF no llegó a Windows');
              }
            });
          },
        ),
      ];
}
