import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/integrity/integrity_policy.dart';
import '../core/integrity/integrity_reconcile_service.dart';
import '../core/ops/technical_health_service.dart';
import '../core/security/authorization_service.dart';
import '../core/sync/observability/sync_benchmark_runner.dart';
import '../core/sync/observability/sync_diagnostic_service.dart';
import '../core/sync/observability/sync_observability_hub.dart';
import '../services/auth_service.dart';
import '../theme/module_app_bar.dart';

/// Panel técnico exclusivo para administradores (Capacidad 5 / ADR §10).
class PanelTecnicoPage extends StatefulWidget {
  const PanelTecnicoPage({super.key});

  @override
  State<PanelTecnicoPage> createState() => _PanelTecnicoPageState();
}

class _PanelTecnicoPageState extends State<PanelTecnicoPage> {
  TechnicalHealthSnapshot? _snap;
  IntegrityScanReport? _integrity;
  Map<String, dynamic>? _dash;
  String? _error;
  bool _loading = true;
  bool _scanning = false;
  bool _busy = false;
  String? _diagText;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!AuthorizationService.instance.esAdministrador) {
        throw StateError('Solo el administrador puede ver el panel técnico');
      }
      final snap = await TechnicalHealthService.instance.snapshot();
      await IntegrityPolicy.instance.ensureLoaded();
      final last = await IntegrityReconcileService.instance.lastReport();
      final dash = await SyncObservabilityHub.instance.dashboardSnapshot();
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _integrity = last;
        _dash = dash;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _diagnosticar() async {
    setState(() => _busy = true);
    try {
      final report = await SyncDiagnosticService.instance.diagnose();
      if (!mounted) return;
      setState(() {
        _diagText = report.toHumanText();
        _busy = false;
      });
      await Clipboard.setData(ClipboardData(text: report.toHumanText()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.ok
                ? 'Diagnóstico OK — copiado al portapapeles'
                : 'Diagnóstico con hallazgos — copiado al portapapeles',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diagnóstico falló: $e')),
      );
    }
  }

  Future<void> _benchmark() async {
    setState(() => _busy = true);
    try {
      final report = await SyncBenchmarkRunner.instance.run();
      if (!mounted) return;
      setState(() => _busy = false);
      await Clipboard.setData(ClipboardData(text: report.toMarkdown()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Benchmark listo — markdown en portapapeles')),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Benchmark falló: $e')),
      );
    }
  }

  Future<void> _escanearIntegridad() async {
    setState(() => _scanning = true);
    try {
      final report =
          await IntegrityReconcileService.instance.scanAndPersist();
      if (!mounted) return;
      setState(() {
        _integrity = report;
        _scanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.ok
                ? 'Integridad OK — sin alarmas'
                : '${report.alarms.length} alarma(s) de integridad',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al escanear: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = AuthService.instance.esAdministrador();
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Panel técnico',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      body: !admin
          ? const Center(child: Text('Solo administradores'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _buildBody(_snap!),
    );
  }

  Widget _buildBody(TechnicalHealthSnapshot s) {
    final sync = s.sync;
    final integrity = _integrity;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Aplicación', [
          _row('Nombre', s.appName),
          _row('Versión', '${s.appVersion}+${s.buildNumber}'),
          _row('Plataforma', s.platform),
        ]),
        _section('Contratos', [
          _row('Schema SQLite', 'v${s.schemaVersion}'),
          _row('Dominio', 'v${s.domainVersion}'),
          _row('Sync', 'v${s.syncVersion}'),
          _row('Eventos', 'v${s.eventsVersion}'),
          _row('Empresa (tenant)', s.tenantId, copyable: true),
        ]),
        _section('Base de datos', [
          _row('Ruta', s.dbPath, copyable: true),
          _row(
            'Último auto-backup',
            s.lastAutoBackup?.toLocal().toString() ?? '—',
          ),
          _row(
            'Última restauración',
            s.lastRestoreAt?.toLocal().toString() ?? '—',
          ),
        ]),
        _section('Sincronización', [
          _row('Salud certificable', sync.isCertifiableHealthy ? 'OK' : 'ATENCIÓN'),
          _row('Indicador', sync.healthColor.toUpperCase()),
          _row('Pending / Inflight / Dead',
              '${sync.pending} / ${sync.inflight} / ${sync.dead}'),
          _row('L1 crítico / L2 alto',
              '${sync.pendingL1} / ${sync.pendingL2}'),
          _row('L3 normal / L4 background',
              '${sync.pendingL3} / ${sync.pendingL4}'),
          _row('Cola crítica / fondo (compat)',
              '${sync.pendingCritical} / ${sync.pendingBackground}'),
          _row('Conflictos 24h', '${sync.conflicts24h}'),
          _row('Ciclos / ACK / Fail',
              '${sync.syncCycles} / ${sync.acksTotal} / ${sync.failsTotal}'),
          _row(
            'Último sync',
            sync.lastSyncAt?.toLocal().toString() ?? '—',
          ),
          _row(
            'Duración último',
            sync.lastSyncDurationMs == null
                ? '—'
                : '${sync.lastSyncDurationMs} ms',
          ),
          _row(
            'Promedio ciclo',
            sync.avgSyncMs == null ? '—' : '${sync.avgSyncMs!.toStringAsFixed(0)} ms',
          ),
          _row('Firebase listo', sync.firebaseReady ? 'sí' : 'no'),
          _row('Puede escribir', sync.canWrite ? 'sí' : 'no'),
          _row('Último error', sync.lastError ?? '—'),
        ]),
        _section('Sync Engine 2.0', [
          _row('Modo', '${sync.engine['mode'] ?? '—'}'),
          _row(
            'Turbo',
            ((sync.engine['turbo'] as Map?)?['turboActive'] == true)
                ? 'ACTIVO'
                : 'off',
          ),
          _row(
            'Preemptions',
            '${(sync.engine['turbo'] as Map?)?['preemptionCount'] ?? 0}',
          ),
          _row(
            'Batch L1 / fondo (adaptativo)',
            '${(sync.engine['adaptive'] as Map?)?['batchL1'] ?? '—'} / '
            '${(sync.engine['adaptive'] as Map?)?['batchBackground'] ?? '—'}',
          ),
          _row(
            'EMA latencia',
            sync.engine['adaptive'] == null ||
                    (sync.engine['adaptive'] as Map)['emaLatencyMs'] == null
                ? '—'
                : '${((sync.engine['adaptive'] as Map)['emaLatencyMs'] as num).toStringAsFixed(0)} ms',
          ),
          _row(
            'Auto-heals',
            '${(sync.engine['healer'] as Map?)?['healsRun'] ?? 0}',
          ),
          _row(
            'Último heal',
            (sync.engine['healer'] as Map?)?['lastHealDetail']?.toString() ??
                '—',
          ),
          _row('Locks entidad', '${sync.engine['locksHeld'] ?? 0}'),
          _row('Muestras 24h', '${sync.history24h.length}'),
        ]),
        if (_dash != null) ...[
          Builder(builder: (context) {
            final d = _dash!;
            final colorName = (d['healthColor'] ?? 'amarillo').toString();
            final color = colorName == 'verde'
                ? Colors.green
                : colorName == 'rojo'
                    ? Colors.red
                    : Colors.orange;
            final sla = (d['sla'] as Map?) ?? const {};
            final byEnt = (sla['byEntity'] as Map?) ?? const {};
            final cb = (d['circuitBreaker'] as Map?) ?? const {};
            final hist = (d['history'] as Map?) ?? const {};
            String histLine(String key) {
              final m = (hist[key] as Map?) ?? const {};
              if ((m['n'] as num?)?.toInt() == 0) return 'sin muestras';
              final avg = m['avgLatencyMs'];
              final err = m['sumErrors'];
              final ops = m['avgOpsPerMin'];
              return 'n=${m['n']} lat=${avg is num ? avg.toStringAsFixed(0) : '—'}ms '
                  'err=$err ops/min=${ops is num ? ops.toStringAsFixed(1) : '—'}';
            }
            return _section('Sync Engine 2.1 — Salud', [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Estado: ${d['healthStatus'] ?? '—'} ($colorName)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _row('Latencia avg / P95',
                  '${d['latencyAvgMs'] ?? '—'} / ${d['latencyP95Ms'] ?? '—'} ms'),
              _row('Throughput',
                  '${d['throughputOpsPerMin'] ?? '—'} ops/min'),
              _row('Pendientes / retries',
                  '${d['pending'] ?? 0} / ${d['retries'] ?? 0}'),
              _row('Conflictos 24h', '${d['conflicts'] ?? 0}'),
              _row('Oldest pending', '${d['oldestPendingAgeSec'] ?? 0}s'),
              _row('Workers L1/L2/L3/L4',
                  '${((d['workers'] as Map?)?['l1'] ?? 0)}/'
                  '${((d['workers'] as Map?)?['l2'] ?? 0)}/'
                  '${((d['workers'] as Map?)?['l3'] ?? 0)}/'
                  '${((d['workers'] as Map?)?['l4'] ?? 0)}'),
              _row(
                'Turbo',
                ((d['turbo'] as Map?)?['turboActive'] == true) ? 'ACTIVO' : 'off',
              ),
              _row('Circuit breaker',
                  '${cb['state'] ?? '—'} (trips=${cb['tripCount'] ?? 0}, wait=${cb['extraWaitMs'] ?? 0}ms)'),
              _row('RSS memoria',
                  d['rssBytes'] == null
                      ? '—'
                      : '${((d['rssBytes'] as num) / (1024 * 1024)).toStringAsFixed(1)} MB'),
              _row('SLA global',
                  '${((sla['overallCompliancePct'] as num?) ?? 0).toStringAsFixed(1)}%'),
              _row('Histórica 1h', histLine('last1h')),
              _row('Histórica 24h', histLine('last24h')),
              _row('Histórica 7d', histLine('last7d')),
              ...byEnt.entries.take(8).map((e) {
                final m = e.value as Map;
                return _row(
                  'SLA ${e.key}',
                  'P50=${m['p50Ms']} P95=${m['p95Ms']} '
                  'ok=${((m['compliancePct'] as num?) ?? 0).toStringAsFixed(0)}% '
                  'n=${m['samples']}',
                );
              }),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _diagnosticar,
                    icon: const Icon(Icons.troubleshoot_outlined),
                    label: const Text('Diagnosticar Sincronización'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _benchmark,
                    icon: const Icon(Icons.speed_outlined),
                    label: const Text('Benchmark lab'),
                  ),
                ],
              ),
              if (_diagText != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  _diagText!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ]);
          }),
        ],
        _section('Scheduler (métricas)', [
          _row(
            'Procesados crítico / fondo',
            '${sync.scheduler['criticalProcessed'] ?? 0} / '
            '${sync.scheduler['backgroundProcessed'] ?? 0}',
          ),
          _row(
            'Fails crítico / fondo',
            '${sync.scheduler['criticalFails'] ?? 0} / '
            '${sync.scheduler['backgroundFails'] ?? 0}',
          ),
          _row('Coalesced ops', '${sync.scheduler['coalescedOps'] ?? 0}'),
          _row('Turbo ticks / preempts',
              '${sync.scheduler['turboTicks'] ?? 0} / ${sync.scheduler['preemptCount'] ?? 0}'),
          _row(
            'Latencia avg crítico',
            sync.scheduler['avgCriticalLatencyMs'] == null
                ? '—'
                : '${(sync.scheduler['avgCriticalLatencyMs'] as num).toStringAsFixed(0)} ms',
          ),
          _row(
            'Latencia max crítico',
            sync.scheduler['maxCriticalLatencyMs'] == null
                ? '—'
                : '${sync.scheduler['maxCriticalLatencyMs']} ms',
          ),
          _row(
            'Ops/min crítico (aprox)',
            sync.scheduler['opsPerMinuteCritical'] == null
                ? '—'
                : (sync.scheduler['opsPerMinuteCritical'] as num)
                    .toStringAsFixed(1),
          ),
          _row(
            'Último tick',
            sync.scheduler['lastTickAt']?.toString() ?? '—',
          ),
        ]),
        if (sync.collectionStatus.isNotEmpty)
          _section(
            'Colecciones',
            sync.collectionStatus.entries
                .map((e) => _row(e.key, e.value))
                .toList(),
          ),
        _section('Integridad (Capacidad 8)', [
          _row(
            'Stock negativo permitido',
            IntegrityPolicy.instance.permitirStockNegativo ? 'sí' : 'no',
          ),
          _row(
            'Último escaneo',
            integrity?.at.toLocal().toString() ?? 'nunca',
          ),
          _row(
            'Productos / clientes chequeados',
            integrity == null
                ? '—'
                : '${integrity.productsChecked} / ${integrity.clientsChecked}',
          ),
          _row(
            'Stock negativo (conteo)',
            integrity == null ? '—' : '${integrity.negativeStockCount}',
          ),
          _row(
            'Alarmas abiertas',
            integrity == null
                ? '—'
                : (integrity.ok ? '0 (OK)' : '${integrity.alarms.length}'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _escanearIntegridad,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_scanning ? 'Escaneando…' : 'Escanear integridad'),
            ),
          ),
          if (integrity != null && integrity.alarms.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...integrity.alarms.take(40).map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText(
                      '• [${a.kindLabel}] ${a.detail}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            if (integrity.alarms.length > 40)
              Text('… y ${integrity.alarms.length - 40} más'),
          ],
        ]),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: SelectableText(value)),
          if (copyable)
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copiado')),
                );
              },
            ),
        ],
      ),
    );
  }
}
