import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/domain/domain_event.dart';
import 'package:sistema_nuevo/core/domain/inventory_ledger_service.dart';
import 'package:sistema_nuevo/core/sync/stable_document_id.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

/// Demuestra convergencia: dos nodos con localIds distintos, mismo numero.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nodos A/B: localId distinto, documentId=numero → mismo net ledger',
      () async {
    // Nodo A
    final dirA = await Directory.systemTemp.createTemp('node_a_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(dirA.path, 'a.db'),
    );
    final dbA = await DatabaseHelper.instance.database;
    final prodA = await dbA.insert('productos', {
      'codigo': 'SKU1',
      'descripcion': 'x',
      'stock': 100,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    const numero = 'R-CONV-1';
    final localIdA = 42; // simula autoincrement origen
    final stable = stableCommercialDocumentId(
      numero: numero,
      localId: localIdA,
    );
    await dbA.transaction((txn) async {
      await InventoryLedgerService.instance.applyInTxn(
        txn,
        DomainEvent(
          eventId: 'inv:entrega:remito:$localIdA',
          type: DomainEventType.mercaderiaEntregada,
          aggregateType: 'remito',
          aggregateId: '$localIdA',
          createdBy: 'a',
          payload: {
            'documentType': 'remito',
            'documentId': stable,
            'lines': [
              InventoryLine(productoId: prodA, cantidad: 5).toJson(),
            ],
          },
        ),
        sign: -1,
        movimientoTipo: 'salida',
        enqueueOutboundStockOps: false,
      );
    });
    final netA = await InventoryLedgerService.instance.ledgerNetForDocument(
      documentType: 'remito',
      documentId: stable,
    );
    expect(netA, -5);
    await DatabaseHelper.instance.cerrar();

    // Nodo B — otro localId, mismo numero/stable
    final dirB = await Directory.systemTemp.createTemp('node_b_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(dirB.path, 'b.db'),
    );
    final dbB = await DatabaseHelper.instance.database;
    final prodB = await dbB.insert('productos', {
      'codigo': 'SKU1',
      'descripcion': 'x',
      'stock': 100,
      'precio': 1,
      'costo': 0,
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    });
    final localIdB = 99; // peer autoincrement distinto
    // Peer aplica stock_op remoto con documentId estable
    await InventoryLedgerService.instance.applyRemoteStockOp(
      opId: 'inv:entrega:remito:$localIdA',
      productoId: prodB,
      codigo: 'SKU1',
      delta: -5,
      documentType: 'remito',
      documentId: stable,
      notify: false,
    );
    final netB = await InventoryLedgerService.instance.ledgerNetForDocument(
      documentType: 'remito',
      documentId: stable,
    );
    expect(netB, -5);
    // Lookup por localId del peer NO encuentra (correcto — no es la clave)
    expect(
      await InventoryLedgerService.instance.ledgerNetForDocument(
        documentType: 'remito',
        documentId: '$localIdB',
      ),
      0,
    );
    // Candidates resuelven vía numero
    final keys = ledgerDocumentIdCandidates(numero: numero, localId: localIdB);
    var found = 0;
    for (final k in keys) {
      final n = await InventoryLedgerService.instance.ledgerNetForDocument(
        documentType: 'remito',
        documentId: k,
      );
      if (n != 0) found = n;
    }
    expect(found, -5);

    await DatabaseHelper.instance.cerrar();
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });
}
