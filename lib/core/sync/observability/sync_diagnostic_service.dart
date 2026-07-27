import '../scheduler/entity_lock_registry.dart';
import '../scheduler/scheduler_state_store.dart';
import '../scheduler/sync_auto_healer.dart';
import '../scheduler/sync_scheduler.dart';
import '../sync_health.dart';
import '../sync_outbox.dart';
import 'sync_circuit_breaker.dart';
import 'sync_flight_recorder.dart';
import 'sync_observability_hub.dart';
import 'sync_sla_monitor.dart';

/// Informe de "Diagnosticar Sincronización" (soporte técnico).
class SyncDiagnosticReport {
  SyncDiagnosticReport({
    required this.at,
    required this.ok,
    required this.healthColor,
    required this.findings,
    required this.actions,
    required this.raw,
  });

  final DateTime at;
  final bool ok;
  final String healthColor;
  final List<String> findings;
  final List<String> actions;
  final Map<String, dynamic> raw;

  String toHumanText() {
    final b = StringBuffer()
      ..writeln('Diagnóstico Sync Engine — ${at.toIso8601String()}')
      ..writeln('Salud: $healthColor  |  OK=$ok')
      ..writeln('')
      ..writeln('Hallazgos:');
    for (final f in findings) {
      b.writeln(' • $f');
    }
    b.writeln('');
    b.writeln('Acciones sugeridas:');
    for (final a in actions) {
      b.writeln(' • $a');
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'ok': ok,
        'healthColor': healthColor,
        'findings': findings,
        'actions': actions,
        'raw': raw,
      };
}

class SyncDiagnosticService {
  SyncDiagnosticService._();
  static final SyncDiagnosticService instance = SyncDiagnosticService._();

  Future<SyncDiagnosticReport> diagnose() async {
    final findings = <String>[];
    final actions = <String>[];
    final health = await SyncHealthService.instance.snapshot();
    final counts = await SyncOutbox.instance.counts();
    final byLane = await SyncOutbox.instance.pendingByLane();
    final engine = SyncScheduler.instance.engineSnapshot();
    final circuit = SyncCircuitBreaker.instance.snapshot();
    final sla = SyncSlaMonitor.instance.snapshot();
    final state = await SchedulerStateStore.instance.load();
    final heal = await SyncAutoHealer.instance.heal(
      staleInflight: const Duration(minutes: 3),
    );
    final locks = EntityLockRegistry.instance.heldCount;
    final flight = SyncFlightRecorder.instance.dumpJson(n: 30);
    final dash = await SyncObservabilityHub.instance.dashboardSnapshot();

    if (!health.firebaseReady) {
      findings.add('Firebase no listo (firebaseReady=false).');
      actions.add('Revisar login nube / Configuración → sincronización.');
    }
    if (!health.canWrite) {
      findings.add('Sin permiso de escritura remota (canWrite=false).');
      actions.add('Verificar sesión y reglas Firestore del tenant.');
    }
    if (health.pendingL1 > 0) {
      findings.add('Cola L1 crítica con ${health.pendingL1} pendientes.');
      actions.add('Priorizar red; Turbo debería estar OFF (focused).');
    }
    if (health.dead > 0) {
      findings.add('${health.dead} ops en estado dead.');
      actions.add('Revisar last_error; reencolar stock_ops vía auto-heal.');
    }
    if (circuit['state'] == 'open') {
      findings.add('Circuit breaker ABIERTO — Firestore lento/errores.');
      actions.add('Esperar cool-down; no forzar reintentos masivos.');
    }
    if (locks > 20) {
      findings.add('Muchos entity locks activos ($locks) — posible trabado.');
      actions.add('Reiniciar app si locks no bajan en 1 minuto.');
    }
    if ((heal['inflightReclaimed'] ?? 0) > 0) {
      findings.add(
        'Auto-heal recuperó ${heal['inflightReclaimed']} inflight stale.',
      );
    }
    final overallSla = sla['overallMeetsSla'] == true;
    if (!overallSla) {
      findings.add('SLA local no cumplido en alguna entidad instrumentada.');
      actions.add('Ver percentiles en dashboard; medir hop remoto en piloto.');
    }
    if (findings.isEmpty) {
      findings.add('Sin anomalías detectadas en este ciclo.');
      actions.add('Continuar monitoreo; correr Benchmark si hay duda de carga.');
    }

    final ok = health.healthColor != 'rojo' &&
        health.firebaseReady &&
        circuit['state'] != 'open';

    return SyncDiagnosticReport(
      at: DateTime.now().toUtc(),
      ok: ok,
      healthColor: health.healthColor,
      findings: findings,
      actions: actions,
      raw: {
        'health': health.toJson(),
        'counts': counts,
        'byLane': byLane,
        'engine': engine,
        'circuit': circuit,
        'sla': sla,
        'schedulerState': state?.mode,
        'heal': heal,
        'locks': locks,
        'flightTail': flight,
        'dashboard': dash,
      },
    );
  }
}
