import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/integrity/integrity_policy.dart';
import '../core/integrity/integrity_reconcile_service.dart';
import '../core/ops/technical_health_service.dart';
import '../core/security/authorization_service.dart';
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
  String? _error;
  bool _loading = true;
  bool _scanning = false;

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
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _integrity = last;
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
          _row('Pending / Inflight / Dead',
              '${sync.pending} / ${sync.inflight} / ${sync.dead}'),
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
          _row('Firebase listo', sync.firebaseReady ? 'sí' : 'no'),
          _row('Puede escribir', sync.canWrite ? 'sí' : 'no'),
          _row('Último error', sync.lastError ?? '—'),
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
