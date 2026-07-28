import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/observability/sync_path_logger.dart';
import 'package:sistema_nuevo/core/sync/remote_line_product_resolve.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Evidencia forense P0: hipótesis FK + peer productoId.
///
/// Demuestra:
/// 1) PRAGMA foreign_keys ON
/// 2) SQL + DatabaseException exacta al insertar peer id inexistente
/// 3) Apply batch abortado → remitos posteriores nunca llegan
/// 4) Fix: resolve solo por codigo → batch completo + header sin ítem si falta SKU
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SyncPathLogger.instance.resetForTests();
    SyncPathLogger.instance.configure(deviceId: 'apk-forense');
    tmp = await Directory.systemTemp.createTemp('sync_p0_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 't.db'),
    );
  });

  tearDown(() async {
    await DatabaseHelper.instance.cerrar();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<int> _remitoHeader(Database db, String numero) async {
    return db.insert('remitos', {
      'numero': numero,
      'fecha': DateTime.now().toIso8601String(),
      'total': 100,
      'descuento': 0,
      'estado': 'confirmado',
      'estadoPago': 'pendiente',
      'totalPagado': 0,
      'saldoPendiente': 100,
      'observaciones': '',
      'fechaCreacion': DateTime.now().toIso8601String(),
    });
  }

  test('EVIDENCIA: foreign_keys=ON en DatabaseHelper', () async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('PRAGMA foreign_keys');
    expect(rows.first.values.first, 1,
        reason: 'PRAGMA foreign_keys debe estar ON (forense 1.4.10)');
  });

  test(
      'EVIDENCIA FK: peer productoId=99 inexistente → DatabaseException + SQL',
      () async {
    final db = await DatabaseHelper.instance.database;
    final rid = await _remitoHeader(db, 'R-P0-FK');

    Object? caught;
    StackTrace? stack;
    const sqlLike =
        'INSERT INTO remito_items (remitoId, productoId, ...) VALUES (…, 99, …)';
    try {
      await db.insert('remito_items', {
        'remitoId': rid,
        'productoId': 99, // id del PC Windows — no existe en APK
        'cantidad': 1,
        'precio': 100,
        'subtotal': 100,
        'costoUnitario': 0,
        'ganancia': 0,
      });
    } catch (e, st) {
      caught = e;
      stack = st;
    }

    expect(caught, isA<DatabaseException>());
    final msg = caught.toString();
    // sqflite_ffi / sqlite3 suele mencionar FOREIGN KEY
    expect(
      msg.toLowerCase().contains('foreign key') ||
          msg.toLowerCase().contains('constraint'),
      isTrue,
      reason: 'mensaje=$msg',
    );
    expect(stack, isNotNull);

    SyncPathLogger.instance.hop(
      stage: 'fk_evidence',
      entityType: 'remito_item',
      eventId: 'forense:R-P0-FK',
      entityId: 'R-P0-FK',
      opId: 'forense:insert_item',
      transactionId: 'tx-forense-fk',
      outcome: 'FAILED',
      extra: {
        'table': 'remito_items',
        'idEsperadoLocal': null,
        'idRecibidoPeer': 99,
        'sql': sqlLike,
        'exception': msg,
        'stackHead': stack.toString().split('\n').take(8).join(' | '),
      },
    );

    final hops = SyncPathLogger.instance.forEntity('R-P0-FK');
    expect(hops, isNotEmpty);
    expect(hops.last['outcome'], 'FAILED');
  });

  test(
      'EVIDENCIA REGRESIÓN: legacy resolve + FK aborta batch (R2 nunca llega)',
      () async {
    final db = await DatabaseHelper.instance.database;
    // Catálogo APK vacío para SKU-B; remito R1 usa SKU-A local, R2 peer id.
    final pidA = await db.insert('productos', {
      'codigo': 'SKU-A',
      'descripcion': 'a',
      'stock': 0,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final localByCodigo = {'SKU-A': pidA};

    final docs = <Map<String, dynamic>>[
      {
        'numero': 'R1',
        'items': [
          {'productoId': 7, 'productoCodigo': 'SKU-A', 'cantidad': 1},
        ],
      },
      {
        'numero': 'R2',
        'items': [
          // Peer Windows id 55; SKU-B no existe en APK → legacy conserva 55 → FK
          {'productoId': 55, 'productoCodigo': 'SKU-B', 'cantidad': 2},
        ],
      },
      {
        'numero': 'R3',
        'items': [
          {'productoId': 7, 'productoCodigo': 'SKU-A', 'cantidad': 1},
        ],
      },
    ];

    Object? batchError;
    var watermarkAdvanced = false;
    final applied = <String>[];

    try {
      for (final doc in docs) {
        final numero = doc['numero'] as String;
        final rid = await _remitoHeader(db, numero);
        for (final raw in (doc['items'] as List)) {
          final item = Map<String, dynamic>.from(raw as Map);
          final productoId = legacyResolveRemoteLineProductoIdKeepingPeer(
            peerProductoId: (item['productoId'] as num?)?.toInt(),
            codigo: item['productoCodigo']?.toString(),
            localIdByCodigo: localByCodigo,
          );
          expect(productoId, isNotNull);
          await db.insert('remito_items', {
            'remitoId': rid,
            'productoId': productoId,
            'cantidad': item['cantidad'] ?? 0,
            'precio': 10,
            'subtotal': 10,
            'costoUnitario': 0,
            'ganancia': 0,
          });
        }
        applied.add(numero);
      }
      watermarkAdvanced = true; // solo si el loop termina (como _persistirWatermark)
    } catch (e) {
      batchError = e;
      SyncPathLogger.instance.hop(
        stage: 'apply_abort',
        entityType: 'remito',
        eventId: 'batch:legacy',
        transactionId: 'tx-legacy-batch',
        outcome: 'FAILED',
        extra: {
          'appliedBeforeAbort': applied,
          'error': e.toString(),
        },
      );
    }

    expect(batchError, isA<DatabaseException>());
    expect(applied, ['R1'],
        reason: 'R1 ok; R2 FK aborta; R3 nunca se procesa');
    expect(watermarkAdvanced, isFalse,
        reason: 'watermark no avanza si el apply aborta (código pre-fix)');

    final remitos = await db.query('remitos');
    final numeros = remitos.map((r) => r['numero']).toSet();
    // Header R2 pudo insertarse antes del ítem fallido (auto-commit).
    expect(numeros.contains('R1'), isTrue);
    expect(numeros.contains('R3'), isFalse,
        reason: 'R3 desaparece: nunca llegó al apply tras abort');
  });

  test('FIX: resolve solo por codigo → batch completo sin FK crash', () async {
    final db = await DatabaseHelper.instance.database;
    final pidA = await db.insert('productos', {
      'codigo': 'SKU-A',
      'descripcion': 'a',
      'stock': 0,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final localByCodigo = {'SKU-A': pidA};

    final docs = <Map<String, dynamic>>[
      {
        'numero': 'R1',
        'items': [
          {'productoId': 7, 'productoCodigo': 'SKU-A', 'cantidad': 1},
        ],
      },
      {
        'numero': 'R2',
        'items': [
          {'productoId': 55, 'productoCodigo': 'SKU-B', 'cantidad': 2},
        ],
      },
      {
        'numero': 'R3',
        'items': [
          {'productoId': 7, 'productoCodigo': 'SKU-A', 'cantidad': 1},
        ],
      },
    ];

    final applied = <String>[];
    for (final doc in docs) {
      final numero = doc['numero'] as String;
      final rid = await _remitoHeader(db, numero);
      var itemsOk = 0;
      for (final raw in (doc['items'] as List)) {
        final item = Map<String, dynamic>.from(raw as Map);
        final productoId = resolveRemoteLineProductoId(
          peerProductoId: (item['productoId'] as num?)?.toInt(),
          codigo: item['productoCodigo']?.toString(),
          localIdByCodigo: localByCodigo,
        );
        if (productoId == null) {
          SyncPathLogger.instance.hop(
            stage: 'line_resolve',
            entityType: 'remito_item',
            entityId: numero,
            eventId: 'pull:remito:$numero',
            opId: 'pull:remito:$numero',
            outcome: 'skipped_missing_sku',
            extra: {
              'peerProductoId': item['productoId'],
              'codigo': item['productoCodigo'],
            },
          );
          continue;
        }
        await db.insert('remito_items', {
          'remitoId': rid,
          'productoId': productoId,
          'cantidad': item['cantidad'] ?? 0,
          'precio': 10,
          'subtotal': 10,
          'costoUnitario': 0,
          'ganancia': 0,
        });
        itemsOk++;
      }
      applied.add(numero);
      SyncPathLogger.instance.hop(
        stage: 'sqlite_items',
        entityType: 'remito',
        entityId: numero,
        eventId: 'pull:remito:$numero',
        opId: 'pull:remito:$numero',
        outcome: 'applied',
        extra: {'itemsOk': itemsOk},
      );
    }

    expect(applied, ['R1', 'R2', 'R3']);
    final remitos = await db.query('remitos');
    expect(remitos, hasLength(3));

    Future<int> itemCount(String n) async {
      final r = await db.query('remitos', where: 'numero = ?', whereArgs: [n]);
      final id = r.first['id'];
      return Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) AS c FROM remito_items WHERE remitoId = ?',
              [id],
            ),
          ) ??
          0;
    }

    expect(await itemCount('R1'), 1);
    expect(await itemCount('R2'), 0,
        reason: 'SKU-B ausente: header sí, sin peer id → sin FK crash');
    expect(await itemCount('R3'), 1);
  });

  test('RULES EVIDENCIA: create productos stock!=0 era bloqueante', () {
    // Predicado hardening 1.4.11 (revertido en 1.4.14):
    // allow create iff !('stock' in data) || stock == 0
    bool createAllowedHardening({required int? stock}) {
      if (stock == null) return true; // campo ausente
      return stock == 0;
    }

    // Caso real: FieldValue.increment sobre SKU ausente → CREATE con stock=delta≠0
    expect(createAllowedHardening(stock: 5), isFalse,
        reason: 'stub stock_ops increment CREATE era permission-denied');
    expect(createAllowedHardening(stock: 0), isTrue);
    expect(createAllowedHardening(stock: null), isTrue);

    // Fix 1.4.14: create = canWriteOps (sin exigir stock==0)
    bool createAllowedRecovery({required bool canWriteOps}) => canWriteOps;
    expect(createAllowedRecovery(canWriteOps: true), isTrue);
  });

  test('UI vs SYNC: filtro _soloConStock oculta stock==0 (no es pérdida sync)',
      () {
    final productos = [
      {'codigo': 'Z0', 'stock': 0},
      {'codigo': 'Z1', 'stock': 3},
    ];
    const soloConStock = true;
    final visibles = productos
        .where((p) => !soloConStock || (p['stock'] as int) > 0)
        .toList();
    expect(visibles.map((e) => e['codigo']), ['Z1']);
    expect(productos.where((p) => p['stock'] == 0).length, 1,
        reason: 'dato existe en SQLite; UI lo filtra si KPI Con stock activo');
  });
}
