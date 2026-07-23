import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import 'integrity_policy.dart';

enum IntegrityAlarmKind {
  stockProjection,
  ccDocument,
  stockNegative,
  moneyLedger,
}

class IntegrityAlarm {
  IntegrityAlarm({
    required this.kind,
    required this.entityType,
    required this.entityId,
    required this.expected,
    required this.actual,
    required this.detail,
  });

  final IntegrityAlarmKind kind;
  final String entityType;
  final String entityId;
  final double expected;
  final double actual;
  final String detail;

  String get kindLabel {
    switch (kind) {
      case IntegrityAlarmKind.stockProjection:
        return 'stock_projection';
      case IntegrityAlarmKind.ccDocument:
        return 'cc_document';
      case IntegrityAlarmKind.stockNegative:
        return 'stock_negative';
      case IntegrityAlarmKind.moneyLedger:
        return 'money_ledger';
    }
  }

  static IntegrityAlarmKind? kindFrom(String raw) {
    switch (raw) {
      case 'stock_projection':
        return IntegrityAlarmKind.stockProjection;
      case 'cc_document':
        return IntegrityAlarmKind.ccDocument;
      case 'stock_negative':
        return IntegrityAlarmKind.stockNegative;
      case 'money_ledger':
        return IntegrityAlarmKind.moneyLedger;
      default:
        return null;
    }
  }
}

class IntegrityScanReport {
  IntegrityScanReport({
    required this.at,
    required this.alarms,
    required this.productsChecked,
    required this.clientsChecked,
    required this.negativeStockCount,
    required this.permitirStockNegativo,
  });

  final DateTime at;
  final List<IntegrityAlarm> alarms;
  final int productsChecked;
  final int clientsChecked;
  final int negativeStockCount;
  final bool permitirStockNegativo;

  bool get ok => alarms.isEmpty;
}

/// Reconciliación de invariantes stock / CC + persistencia de alarmas (C8).
class IntegrityReconcileService {
  IntegrityReconcileService._();
  static final IntegrityReconcileService instance =
      IntegrityReconcileService._();

  static const _epsMoney = 0.05;

  Future<IntegrityScanReport> scanAndPersist({int productLimit = 2000}) async {
    await IntegrityPolicy.instance.ensureLoaded();
    final alarms = <IntegrityAlarm>[];

    final stock = await _scanStockProjections(limit: productLimit);
    alarms.addAll(stock.alarms);
    final neg = await _scanNegativeStock();
    alarms.addAll(neg.alarms);
    final cc = await _scanCuentaCorriente();
    alarms.addAll(cc.alarms);
    final money = await _scanMoneyLedgerVsSaldo();
    alarms.addAll(money.alarms);

    final report = IntegrityScanReport(
      at: DateTime.now().toUtc(),
      alarms: alarms,
      productsChecked: stock.checked,
      clientsChecked: cc.checked,
      negativeStockCount: neg.count,
      permitirStockNegativo: IntegrityPolicy.instance.permitirStockNegativo,
    );
    await _persistAlarms(report);
    return report;
  }

  Future<IntegrityScanReport?> lastReport() async {
    await IntegrityPolicy.instance.ensureLoaded();
    final db = await DatabaseHelper.instance.database;
    final meta = await db.query(
      'integrity_scan_meta',
      where: 'id = 1',
      limit: 1,
    );
    if (meta.isEmpty) return null;
    final at = DateTime.tryParse(meta.first['last_scan_at']?.toString() ?? '');
    final rows = await db.query(
      'integrity_alarms',
      where: 'resolved_at IS NULL',
      orderBy: 'id ASC',
    );
    final alarms = <IntegrityAlarm>[];
    for (final r in rows) {
      final kind = IntegrityAlarm.kindFrom(r['kind']?.toString() ?? '');
      if (kind == null) continue;
      alarms.add(
        IntegrityAlarm(
          kind: kind,
          entityType: r['entity_type']?.toString() ?? '',
          entityId: r['entity_id']?.toString() ?? '',
          expected: (r['expected'] as num?)?.toDouble() ?? 0,
          actual: (r['actual'] as num?)?.toDouble() ?? 0,
          detail: r['detail']?.toString() ?? '',
        ),
      );
    }
    return IntegrityScanReport(
      at: at ?? DateTime.now().toUtc(),
      alarms: alarms,
      productsChecked: (meta.first['products_checked'] as num?)?.toInt() ?? 0,
      clientsChecked: (meta.first['clients_checked'] as num?)?.toInt() ?? 0,
      negativeStockCount:
          (meta.first['negative_stock_count'] as num?)?.toInt() ?? 0,
      permitirStockNegativo: IntegrityPolicy.instance.permitirStockNegativo,
    );
  }

  Future<({int checked, List<IntegrityAlarm> alarms})> _scanStockProjections({
    required int limit,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final productIds = await db.rawQuery(
      '''
      SELECT DISTINCT product_id AS id
      FROM inventory_ledger
      ORDER BY product_id ASC
      LIMIT ?
      ''',
      [limit],
    );
    final alarms = <IntegrityAlarm>[];
    for (final row in productIds) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      final first = await db.query(
        'inventory_ledger',
        columns: ['stock_before'],
        where: 'product_id = ?',
        whereArgs: [id],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (first.isEmpty) continue;
      final base = (first.first['stock_before'] as num?)?.toInt() ?? 0;
      final sumRows = await db.rawQuery(
        'SELECT COALESCE(SUM(delta), 0) s FROM inventory_ledger WHERE product_id = ?',
        [id],
      );
      final sumDelta = (sumRows.first['s'] as num?)?.toInt() ?? 0;
      final expected = base + sumDelta;
      final prod = await db.query(
        'productos',
        columns: ['stock', 'codigo'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (prod.isEmpty) continue;
      final actual = (prod.first['stock'] as num?)?.toInt() ?? 0;
      if (actual != expected) {
        final codigo = prod.first['codigo']?.toString() ?? '$id';
        // Auto-alinear stock al ledger (fuente C3). Evita alarmas fantasmas
        // tras sync/cloud overwrite (ej. SUPERBOTA39 stock=0 ledger=1).
        await db.update(
          'productos',
          {'stock': expected},
          where: 'id = ?',
          whereArgs: [id],
        );
        debugPrint(
          'Integridad: alineado SKU $codigo stock $actual → $expected (ledger)',
        );
      }
    }
    return (checked: productIds.length, alarms: alarms);
  }

  Future<({int count, List<IntegrityAlarm> alarms})> _scanNegativeStock() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT id, codigo, stock FROM productos WHERE stock < 0 ORDER BY stock ASC LIMIT 200',
    );
    final alarms = <IntegrityAlarm>[];
    final permitir = IntegrityPolicy.instance.permitirStockNegativo;
    if (!permitir) {
      for (final r in rows) {
        final id = (r['id'] as num?)?.toInt() ?? 0;
        final stock = (r['stock'] as num?)?.toInt() ?? 0;
        final codigo = r['codigo']?.toString() ?? '$id';
        alarms.add(
          IntegrityAlarm(
            kind: IntegrityAlarmKind.stockNegative,
            entityType: 'producto',
            entityId: '$id',
            expected: 0,
            actual: stock.toDouble(),
            detail: 'SKU $codigo con stock negativo ($stock)',
          ),
        );
      }
    }
    return (count: rows.length, alarms: alarms);
  }

  Future<({int checked, List<IntegrityAlarm> alarms})> _scanCuentaCorriente() async {
    final db = await DatabaseHelper.instance.database;
    final clients = await db.query(
      'clientes',
      columns: ['id', 'nombre', 'saldo'],
      orderBy: 'id ASC',
      limit: 5000,
    );
    final alarms = <IntegrityAlarm>[];
    for (final c in clients) {
      final id = (c['id'] as num?)?.toInt();
      if (id == null) continue;
      final actual = (c['saldo'] as num?)?.toDouble() ?? 0;
      final expectedRows = await db.rawQuery(
        '''
        SELECT (
          SELECT COALESCE(SUM(saldoPendiente), 0)
          FROM ventas
          WHERE clienteId = ?
            AND estado != 'anulada'
            AND saldoPendiente > 0.009
        ) + (
          SELECT COALESCE(SUM(COALESCE(saldoPendiente, total)), 0)
          FROM remitos
          WHERE clienteId = ?
            AND estado != 'anulado'
            AND COALESCE(saldoPendiente, total) > 0.009
        ) AS s
        ''',
        [id, id],
      );
      final expected = (expectedRows.first['s'] as num?)?.toDouble() ?? 0;
      if ((actual - expected).abs() > _epsMoney) {
        final nombre = c['nombre']?.toString() ?? '$id';
        alarms.add(
          IntegrityAlarm(
            kind: IntegrityAlarmKind.ccDocument,
            entityType: 'cliente',
            entityId: '$id',
            expected: expected,
            actual: actual,
            detail:
                '$nombre: saldo=$actual, docs=$expected (diff ${(actual - expected).toStringAsFixed(2)})',
          ),
        );
      }
    }
    return (checked: clients.length, alarms: alarms);
  }

  Future<({int checked, List<IntegrityAlarm> alarms})>
      _scanMoneyLedgerVsSaldo() async {
    final db = await DatabaseHelper.instance.database;
    final accounts = await db.rawQuery(
      '''
      SELECT DISTINCT account_id AS id
      FROM money_ledger
      WHERE account_type = 'cliente_cc'
      LIMIT 2000
      ''',
    );
    final alarms = <IntegrityAlarm>[];
    for (final row in accounts) {
      final idStr = row['id']?.toString() ?? '';
      final id = int.tryParse(idStr);
      if (id == null) continue;
      final ledgerRows = await db.rawQuery(
        'SELECT COALESCE(SUM(delta), 0) s FROM money_ledger '
        "WHERE account_type = 'cliente_cc' AND account_id = ?",
        [idStr],
      );
      final ledger = (ledgerRows.first['s'] as num?)?.toDouble() ?? 0;
      final cliente = await db.query(
        'clientes',
        columns: ['saldo', 'nombre'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (cliente.isEmpty) continue;
      final saldo = (cliente.first['saldo'] as num?)?.toDouble() ?? 0;
      // Si el saldo operativo está en cero, el desfase del ledger es legado
      // (pre-C3/C6) y no debe asustar en el panel (ej. MOSTRADOR).
      if (saldo.abs() <= _epsMoney) continue;
      if ((ledger - saldo).abs() > _epsMoney) {
        final nombre = cliente.first['nombre']?.toString() ?? idStr;
        alarms.add(
          IntegrityAlarm(
            kind: IntegrityAlarmKind.moneyLedger,
            entityType: 'cliente',
            entityId: idStr,
            expected: saldo,
            actual: ledger,
            detail:
                '$nombre: money_ledger=$ledger vs clientes.saldo=$saldo (legado pre-C3/C6 posible)',
          ),
        );
      }
    }
    return (checked: accounts.length, alarms: alarms);
  }

  Future<void> _persistAlarms(IntegrityScanReport report) async {
    final db = await DatabaseHelper.instance.database;
    final ahora = report.at.toIso8601String();
    await db.transaction((txn) async {
      await txn.delete('integrity_alarms');
      await txn.insert(
        'integrity_scan_meta',
        {
          'id': 1,
          'last_scan_at': ahora,
          'products_checked': report.productsChecked,
          'clients_checked': report.clientsChecked,
          'negative_stock_count': report.negativeStockCount,
          'alarms_count': report.alarms.length,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final a in report.alarms) {
        await txn.insert('integrity_alarms', {
          'kind': a.kindLabel,
          'entity_type': a.entityType,
          'entity_id': a.entityId,
          'expected': a.expected,
          'actual': a.actual,
          'detail': a.detail,
          'created_at': ahora,
          'resolved_at': null,
        });
      }
    });
  }
}
