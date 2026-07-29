import '../../sync/windows_sync_policy.dart';
import 'cert_lab_models.dart';

/// Manifiesto de capacidades del Sync Engine vistas desde el Cert Lab.
///
/// El lab NO modifica el Sync Engine aquí: solo **lee** [WindowsSyncPolicy]
/// y reporta si el contrato de inbound seguro se cumple.
///
/// P0-99 pasa solo con evidencia en código: soft-pull incluye `stock_ops`,
/// presupuestos `maxApply ≤ 4` (causa raíz del cierre del EXE) y
/// `recentLimit > 0`.
class CertLabEngineManifest {
  /// Windows recibe stock_ops vía soft-pull con presupuesto anti-crash.
  static bool get windowsAutomaticStockInboundCertified =>
      CertLabEngineChecks.windowsStockInboundSafe();

  /// Triple-hop real (EXE↔Firebase↔APK) fuera del protocolo lab.
  static const bool realFirebaseTripleHopCertified = false;

  /// Soak EXE ≥ 2h con sync activa sin cierre espontáneo.
  static const bool exeSoakTwoHoursCertified = false;

  /// Evalúa P0-99 con el primer check rojo (si hay).
  static CertLabFailure? p099FailureOrNull() {
    final failed = CertLabEngineChecks.runAll().where((c) => !c.ok).toList();
    if (failed.isEmpty) return null;
    final f = failed.first;
    return CertLabFailure(
      scenarioId: 'P0-99-engine-contract-windows-inbound',
      entity: CertLabEntity.stock,
      where: f.where,
      message: f.detail,
      expected: f.expected,
      actual: f.actual,
      file: f.file,
      clazz: 'WindowsSyncPolicy',
      method: f.method,
      firestorePath: 'tenants/{tenant}/stock_ops/{opId}',
      hint:
          'Causa raíz histórica: maxApply≥50–60 tumbaba el EXE. '
          'Inbound seguro = soft-pull stock_ops + hardCap≤4 + recentLimit>0.',
      stackTrace: StackTrace.current.toString(),
    );
  }
}

class CertLabEngineCheck {
  const CertLabEngineCheck({
    required this.ok,
    required this.where,
    required this.expected,
    required this.actual,
    required this.detail,
    required this.file,
    required this.method,
  });

  final bool ok;
  final String where;
  final String expected;
  final String actual;
  final String detail;
  final String file;
  final String method;
}

class CertLabEngineChecks {
  CertLabEngineChecks._();

  /// Techo duro: maxApply ≥50–60 cerraba el EXE ~2 min post-login.
  static const int hardCap = 4;

  static bool windowsStockInboundSafe() =>
      runAll().every((c) => c.ok);

  static List<CertLabEngineCheck> runAll() {
    const file = 'lib/core/sync/windows_sync_policy.dart';
    final quiet = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 0);
    final mid = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 20);
    final busy = WindowsSyncPolicy.stockOpsPullBudget(pendingProductos: 200);
    final catchup = WindowsSyncPolicy.windowsCatchupStockOpsBudget();
    final manual = WindowsSyncPolicy.manualRefreshBudgetWindows(
      pendingProductos: 0,
    );
    final softPull = WindowsSyncPolicy.softPullOtherLanes;
    final listeners = WindowsSyncPolicy.windowsBusinessListenerCollections;

    bool applyOk(int maxApply, int recentLimit) =>
        maxApply > 0 && maxApply <= hardCap && recentLimit > 0;

    return [
      CertLabEngineCheck(
        ok: softPull.contains('stock_ops'),
        where: 'windows_sync_policy.softPullOtherLanes',
        expected: "incluye 'stock_ops' (inbound automático vía soft-pull)",
        actual: softPull.toString(),
        detail:
            'Sin stock_ops en soft-pull el Windows no recibe deltas '
            'automáticos del celular.',
        file: file,
        method: 'softPullOtherLanes',
      ),
      CertLabEngineCheck(
        ok: !listeners.contains('stock_ops'),
        where: 'windows_sync_policy.windowsBusinessListenerCollections',
        expected: "NO incluye 'stock_ops' (realtime letal)",
        actual: listeners.toString(),
        detail:
            'Listener realtime de stock_ops en Windows es ráfaga letal. '
            'Inbound debe ser soft-pull con presupuesto.',
        file: file,
        method: 'windowsBusinessListenerCollections',
      ),
      CertLabEngineCheck(
        ok: applyOk(quiet.maxApply, quiet.recentLimit),
        where: 'stockOpsPullBudget(pendingProductos:0)',
        expected: 'maxApply 1..$hardCap y recentLimit>0',
        actual: 'maxApply=${quiet.maxApply} recentLimit=${quiet.recentLimit}',
        detail:
            'maxApply>$hardCap en quiet fue la causa raíz del cierre del EXE.',
        file: file,
        method: 'stockOpsPullBudget',
      ),
      CertLabEngineCheck(
        ok: applyOk(mid.maxApply, mid.recentLimit),
        where: 'stockOpsPullBudget(pendingProductos:20)',
        expected: 'maxApply 1..$hardCap y recentLimit>0',
        actual: 'maxApply=${mid.maxApply} recentLimit=${mid.recentLimit}',
        detail: 'Budget medio no puede superar hardCap=$hardCap.',
        file: file,
        method: 'stockOpsPullBudget',
      ),
      CertLabEngineCheck(
        ok: applyOk(busy.maxApply, busy.recentLimit),
        where: 'stockOpsPullBudget(pendingProductos:200)',
        expected: 'maxApply 1..$hardCap y recentLimit>0',
        actual: 'maxApply=${busy.maxApply} recentLimit=${busy.recentLimit}',
        detail: 'Busy budget no puede superar hardCap=$hardCap.',
        file: file,
        method: 'stockOpsPullBudget',
      ),
      CertLabEngineCheck(
        ok: catchup.maxApply > 0 && catchup.maxApply <= hardCap,
        where: 'windowsCatchupStockOpsBudget().maxApply',
        expected: '1..$hardCap',
        actual: '${catchup.maxApply}',
        detail: 'Catch-up tampoco puede superar hardCap=$hardCap.',
        file: file,
        method: 'windowsCatchupStockOpsBudget',
      ),
      CertLabEngineCheck(
        ok: applyOk(manual.stockMaxApply, manual.stockRecentLimit),
        where: 'manualRefreshBudgetWindows(pendingProductos:0).stockMaxApply',
        expected: '1..$hardCap con stockRecentLimit>0',
        actual:
            'stockMaxApply=${manual.stockMaxApply} '
            'recent=${manual.stockRecentLimit}',
        detail:
            'Actualizar ahora también debe respetar hardCap (ráfaga manual '
            'histórica tumbaba el EXE).',
        file: file,
        method: 'manualRefreshBudgetWindows',
      ),
    ];
  }
}
