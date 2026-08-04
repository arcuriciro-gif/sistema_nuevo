import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/backend_config_service.dart';
import '../../core/events/data_refresh_hub.dart';
import '../../core/firebase/firebase_auth_usuario_service.dart';
import '../../core/sync/firestore_sync_service.dart';
import '../../core/sync/stock_ops_pull_hold_store.dart';
import '../../core/sync/sync_health.dart';
import '../../theme/app_tokens.dart';

enum ShellSyncTone { ok, syncing, offline, error }

/// Indicador visible de sync + actualización manual.
class ShellSyncBadge extends StatefulWidget {
  const ShellSyncBadge({super.key, this.compact = false});

  final bool compact;

  @override
  State<ShellSyncBadge> createState() => _ShellSyncBadgeState();
}

class _ShellSyncBadgeState extends State<ShellSyncBadge> {
  SyncHealthSnapshot? _health;
  Timer? _poll;
  bool _actualizando = false;
  int _stockHolds = 0;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_refrescar);
    _refrescar();
    // Poll suave del badge (no recarga páginas).
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _refrescar());
  }

  @override
  void dispose() {
    _poll?.cancel();
    DataRefreshHub.instance.removeListener(_refrescar);
    super.dispose();
  }

  Future<void> _refrescar() async {
    try {
      final h = await SyncHealthService.instance.snapshot();
      var holds = 0;
      try {
        holds = await StockOpsPullHoldStore.instance.count();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _health = h;
          _stockHolds = holds;
        });
      }
    } catch (_) {}
  }

      Future<void> _actualizarAhora() async {
    if (_actualizando) return;
    setState(() => _actualizando = true);
    try {
      final r = await FirestoreSyncService.instance
          .actualizarAhora()
          .timeout(
            // Windows 1.4.46: solo SQLite local — no hace falta 150s.
            const Duration(seconds: 30),
            onTimeout: () => {
              'ok': false,
              'error': 'timeout_30s',
            },
          );
      if (!mounted) return;
      final ok = r['ok'] == true;
      final pushOnly = r['pushOnly'] == true;
      final localOnly = r['localOnly'] == true;
      final pendingLeft = r['pendingLeft'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (localOnly
                    ? (pendingLeft == 0
                        ? 'Pendientes limpios (${r['ms']} ms). PC estable.'
                        : 'Limpié ${r['quieted'] ?? 0} fantasmas; '
                            'quedan $pendingLeft reales (suben solos en segundo plano).')
                    : pushOnly
                        ? (pendingLeft == 0
                            ? 'Cola limpia (${r['ms']} ms). En PC solo se sube lo local.'
                            : 'Subidos ${r['drained'] ?? 0}; quedan $pendingLeft por subir.')
                        : 'Actualizado (${r['ms']} ms). Listas, clientes, ventas y stock.')
                : 'No se pudo actualizar: ${r['error'] ?? 'error'}',
          ),
        ),
      );
      await _refrescar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Actualizar ahora falló: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  ({ShellSyncTone tone, String title, String subtitle}) _estado() {
    final nubeOn = BackendConfigService.instance.firebaseEnabled;
    final conAuth = nubeOn &&
        FirebaseAuthUsuarioService.instance.disponible &&
        FirebaseAuthUsuarioService.instance.uidActual != null;
    final label = FirestoreSyncService.instance.syncStatusLabel;
    final detail = FirestoreSyncService.instance.syncStatusDetail;
    final pending = _health?.pending ?? 0;
    final dead = _health?.dead ?? 0;
    final last = _health?.lastSyncAt;

    if (!nubeOn) {
      return (
        tone: ShellSyncTone.offline,
        title: 'Sin conexión',
        subtitle: 'Solo local · Sync desactivado',
      );
    }
    if (!conAuth) {
      return (
        tone: ShellSyncTone.offline,
        title: 'Sin conexión',
        subtitle: 'Falta sesión de nube',
      );
    }
    final lower = label.toLowerCase();
    final inflight = _health?.inflight ?? 0;
    if (lower.contains('sincronizando') ||
        pending > 0 ||
        inflight > 0 ||
        _actualizando ||
        _stockHolds > 0) {
      final que = _health?.pendingBreakdownLabel ?? '';
      return (
        tone: ShellSyncTone.syncing,
        title: _actualizando ? 'Actualizando' : 'Sincronizando',
        subtitle: _actualizando
            ? 'Actualización manual…'
            : _stockHolds > 0 && pending == 0 && inflight == 0
                ? '$_stockHolds stock_ops en espera (producto faltante)'
                : pending > 0
                    ? (que.isEmpty
                        ? '$pending cambios pendientes'
                        : '$pending pendientes: $que')
                    : (detail ?? 'Actualizando…'),
      );
    }
    if (dead > 0 || lower.contains('error')) {
      return (
        tone: ShellSyncTone.error,
        title: 'Error de sync',
        subtitle: detail ?? '$dead ops con error',
      );
    }
    final local = last?.toLocal();
    final lastTxt = local == null
        ? 'Al día'
        : 'Última: ${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
    return (
      tone: ShellSyncTone.ok,
      title: 'Sincronizado',
      subtitle: detail?.isNotEmpty == true ? detail! : lastTxt,
    );
  }

  Color _color(ShellSyncTone t) {
    switch (t) {
      case ShellSyncTone.ok:
        return AppTokens.syncOk;
      case ShellSyncTone.syncing:
        return AppTokens.syncWarn;
      case ShellSyncTone.error:
        return AppTokens.syncErr;
      case ShellSyncTone.offline:
        return AppTokens.syncOff;
    }
  }

  IconData _icon(ShellSyncTone t) {
    switch (t) {
      case ShellSyncTone.ok:
        return Icons.cloud_done_rounded;
      case ShellSyncTone.syncing:
        return Icons.sync_rounded;
      case ShellSyncTone.error:
        return Icons.cloud_off_rounded;
      case ShellSyncTone.offline:
        return Icons.wifi_off_rounded;
    }
  }

  Future<void> _mostrarDetalle() async {
    await _refrescar();
    if (!mounted) return;
    final e = _estado();
    final h = _health;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon(e.tone), color: _color(e.tone)),
                    const SizedBox(width: 10),
                    Text(
                      e.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(e.subtitle),
                const SizedBox(height: 12),
                Text('Pendientes: ${h?.pending ?? 0}'),
                Text('En curso: ${h?.inflight ?? 0}'),
                Text('Con error: ${h?.dead ?? 0}'),
                if ((h?.pendingBreakdownLabel ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'De qué son',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(h!.pendingBreakdownLabel),
                ],
                if ((h?.pendingPreview ?? const []).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Detalle (máx. 20)',
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  ...h!.pendingPreview.map((op) {
                    final type = op['entity_type']?.toString() ?? '?';
                    final id = op['entity_local_id'];
                    final attempts = op['attempts'] ?? 0;
                    final err = (op['last_error']?.toString() ?? '').trim();
                    final line = id == null
                        ? '• $type (intentos $attempts)'
                        : '• $type #$id (intentos $attempts)';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        err.isEmpty ? line : '$line — $err',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    );
                  }),
                ],
                if (h?.lastSyncAt != null)
                  Text(
                    'Última sync: ${h!.lastSyncAt!.toLocal()}',
                  ),
                const SizedBox(height: 8),
                Text(
                  'Estado: ${FirestoreSyncService.instance.syncStatusLabel}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                if ((FirestoreSyncService.instance.syncStatusDetail ?? '')
                    .isNotEmpty)
                  Text(
                    FirestoreSyncService.instance.syncStatusDetail!,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _actualizando
                        ? null
                        : () async {
                            Navigator.of(ctx).pop();
                            await _actualizarAhora();
                          },
                    icon: _actualizando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync_rounded),
                    label: Text(
                      _actualizando
                          ? 'Limpiando…'
                          : 'Limpiar pendientes',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'En la PC: este botón solo limpia pendientes fantasma '
                  '(no toca la nube — eso tumbaba el EXE). '
                  'Lo nuevo se sube solo en segundo plano. '
                  'En el celular sí baja y sube todo.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).hintColor,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado();
    final c = _color(e.tone);
    if (widget.compact) {
      return Tooltip(
        message: '${e.title}\n${e.subtitle}\nTocá para actualizar',
        child: InkWell(
          onTap: _mostrarDetalle,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.withValues(alpha: 0.55)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Icon(_icon(e.tone), size: 14, color: c),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _mostrarDetalle,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: c.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: c.withValues(alpha: 0.55),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(_icon(e.tone), size: 16, color: c),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    e.subtitle,
                    style: const TextStyle(
                      color: AppTokens.mute,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 16, color: AppTokens.mute),
            ],
          ),
        ),
      ),
    );
  }
}
