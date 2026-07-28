import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_nuevo/core/sync/stock_ops_pull_hold_store.dart';
import 'package:sistema_nuevo/core/sync/stock_ops_pull_policy.dart';
import 'package:sistema_nuevo/database/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('pending_apply nunca adelanta watermark (causa EXE≠APK)', () {
    expect(
      shouldAdvanceStockOpsWatermark(
        consideredValid: 0,
        skippedMissingProduct: 0,
        skippedPendingApply: 1,
        blockersParkedInHolds: true,
      ),
      isFalse,
    );
  });

  test('forceDueForCodigo libera backoff al llegar el SKU', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = await Directory.systemTemp.createTemp('hold_due_');
    await DatabaseHelper.instance.resetForTests(
      absolutePath: p.join(tmp.path, 't.db'),
    );

    await StockOpsPullHoldStore.instance.upsert(
      opId: 'op-1127-a',
      reason: StockOpsPullHoldStore.reasonMissingProduct,
      codigo: '1127',
      delta: -1,
      at: DateTime.now().toUtc().toIso8601String(),
    );
    // Segundo upsert pone retry_after en el futuro.
    await StockOpsPullHoldStore.instance.upsert(
      opId: 'op-1127-a',
      reason: StockOpsPullHoldStore.reasonMissingProduct,
      codigo: '1127',
      delta: -1,
    );

    var due = await StockOpsPullHoldStore.instance.listDue(limit: 10);
    expect(due.where((e) => e['op_id'] == 'op-1127-a'), isEmpty,
        reason: 'con backoff no debería estar due');

    final n = await StockOpsPullHoldStore.instance.forceDueForCodigo('1127');
    expect(n, greaterThan(0));
    due = await StockOpsPullHoldStore.instance.listDue(limit: 10);
    expect(due.any((e) => e['op_id'] == 'op-1127-a'), isTrue);

    await DatabaseHelper.instance.cerrar();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });
}
