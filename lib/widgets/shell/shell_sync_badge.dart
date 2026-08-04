import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/backend_config_service.dart';
import '../../core/events/data_refresh_hub.dart';
import '../../core/firebase/firebase_auth_usuario_service.dart';
import '../../core/sync/firestore_sync_service.dart';
import '../../core/sync/sync_health.dart';
import '../../theme/app_tokens.dart';

enum ShellSyncTone { ok, syncing, offline, error }

/// Indicador de sync automática (sin botón manual — tumbaba el EXE).
class ShellSyncBadge extends StatefulWidget {
  const ShellSyncBadge({super.key, this.compact = false});

  final bool compact;

  @override
  State<ShellSyncBadge> createState() => _ShellSyncBadgeState();
}

class _ShellSyncBadgeState extends State<ShellSyncBadge> {
  SyncHealthSnapshot? _health;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_refrescar);
    _refrescar();
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
      if (mounted) setState(() => _health = h);
    } catch (_) {}
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

    if (!nubeOn) {
      return (
        tone: ShellSyncTone.offline,
        title: 'Sin conexión',
        subtitle: 'Solo este dispositivo',
      );
    }
    if (!conAuth) {
      return (
        tone: ShellSyncTone.offline,
        title: 'Sin sesión',
        subtitle: 'Entrá para sincronizar',
      );
    }
    if (dead > 0) {
      return (
        tone: ShellSyncTone.error,
        title: 'Sync con errores',
        subtitle: detail ?? '$dead con error',
      );
    }
    if (pending > 0 ||
        label.toLowerCase().contains('sincroniz') ||
        label.toLowerCase().contains('iniciando') ||
        label.toLowerCase().contains('arranque')) {
      return (
        tone: ShellSyncTone.syncing,
        title: 'Sincronizando',
        subtitle: detail ??
            (pending > 0 ? '$pending por subir' : 'Automática…'),
      );
    }
    return (
      tone: ShellSyncTone.ok,
      title: 'En la nube',
      subtitle: detail ?? 'Sync automática',
    );
  }

  Color _color(ShellSyncTone t) {
    switch (t) {
      case ShellSyncTone.ok:
        return AppTokens.syncOk;
      case ShellSyncTone.syncing:
        return AppTokens.syncWarn;
      case ShellSyncTone.offline:
        return AppTokens.syncOff;
      case ShellSyncTone.error:
        return AppTokens.syncErr;
    }
  }

  IconData _icon(ShellSyncTone t) {
    switch (t) {
      case ShellSyncTone.ok:
        return Icons.cloud_done_rounded;
      case ShellSyncTone.syncing:
        return Icons.cloud_sync_rounded;
      case ShellSyncTone.offline:
        return Icons.cloud_off_rounded;
      case ShellSyncTone.error:
        return Icons.cloud_off_rounded;
    }
  }

  void _mostrarDetalle() {
    final e = _estado();
    final h = _health;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(e.subtitle),
              if (h != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Pendientes: ${h.pending} · En curso: ${h.inflight} · '
                  'Errores: ${h.dead}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                if (h.lastSyncAt != null)
                  Text(
                    'Última sync: ${h.lastSyncAt!.toLocal()}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                'Sync automática: productos, precios, ventas, comprobantes '
                'y fotos (URLs) se alinean solos entre PC y celular. '
                'No hace falta actualizar a mano.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).hintColor,
                    ),
              ),
            ],
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
        message: '${e.title}\n${e.subtitle}',
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
    return InkWell(
      onTap: _mostrarDetalle,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(e.tone), size: 18, color: c),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.title,
                    style: TextStyle(
                      color: c,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    e.subtitle,
                    style: TextStyle(
                      color: c.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
