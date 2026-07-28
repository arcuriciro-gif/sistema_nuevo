import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/core/sync/remote_line_product_resolve.dart';

void main() {
  group('resolveRemoteLineProductoId', () {
    test('nunca usa productoId del peer si no hay codigo local', () {
      expect(
        resolveRemoteLineProductoId(
          peerProductoId: 42,
          codigo: null,
          localIdByCodigo: const {},
        ),
        isNull,
      );
      expect(
        resolveRemoteLineProductoId(
          peerProductoId: 42,
          codigo: 'SKU-1',
          localIdByCodigo: const {},
        ),
        isNull,
      );
    });

    test('resuelve solo por codigo local', () {
      expect(
        resolveRemoteLineProductoId(
          peerProductoId: 999,
          codigo: 'SKU-1',
          localIdByCodigo: const {'SKU-1': 7},
        ),
        7,
      );
    });
  });
}
