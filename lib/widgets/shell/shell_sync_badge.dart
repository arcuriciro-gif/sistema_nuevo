import 'package:flutter/material.dart';

import '../../core/config/backend_config_service.dart';
import '../../core/firebase/firebase_auth_usuario_service.dart';
import '../../core/sync/firestore_sync_service.dart';
import '../../core/sync/sync_health.dart';
import '../../theme/app_tokens.dart';

enum ShellSyncTone { ok, syncing, offline, error }

/// Indicador visible de sync (solo lectura de estado existente).
class ShellSyncBadge extends StatefulWidget {
  const ShellSyncBadge({super.key, this.compact = false});

  final bool compact;

  @override
  State<ShellSyncBadge> createState() => _ShellSyncBadgeState();
}

class _ShellSyncBadgeState extends State<ShellSyncBadge> {
  SyncHealthSnapshot? _health;

  @override
  void initState() {
    super.initState();
    _refrescar();
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
    if (dead > 0 || lower.contains('error')) {
      return (
        tone: ShellSyncTone.error,
        title: 'Error de sync',
        subtitle: detail ?? '$dead ops con error',
      );
    }
    if (lower.contains('sincronizando') ||
        pending > 0 ||
        (_health?.inflight ?? 0) > 0) {
      return (
        tone: ShellSyncTone.syncing,
        title: 'Sincronizando',
        subtitle: pending > 0
            ? '$pending cambios pendientes'
            : (detail ?? 'Actualizando…'),
      );
    }
    final lastTxt = last == null
        ? 'Al día'
        : 'Última: ${last.hour.toString().padLeft(2, '0')}:'
            '${last.minute.toString().padLeft(2, '0')}';
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
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
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
              if (h?.lastSyncAt != null)
                Text('Última sync: ${h!.lastSyncAt}'),
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
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    e.subtitle,
                    style: TextStyle(
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
