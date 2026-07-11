import 'package:flutter/foundation.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import 'auth_service.dart';
import 'auto_backup_service.dart';
import 'comunicaciones_service.dart';
import 'permisos_service.dart';

/// Reinicia servicios internos (sync, chat, backups automáticos).
/// **Nunca** borra SQLite ni preferencias de negocio.
class SystemRestartService {
  SystemRestartService._();
  static final SystemRestartService instance = SystemRestartService._();

  bool _enCurso = false;
  bool get enCurso => _enCurso;

  void _requiereAdministrador() {
    if (!AuthService.instance.esAdministrador()) {
      throw StateError('Solo el administrador puede reiniciar el sistema.');
    }
  }

  /// Detiene y vuelve a levantar listeners/timers.
  /// No cierra sesión ni toca datos locales.
  Future<({bool ok, String mensaje})> reiniciarServicios() async {
    _requiereAdministrador();
    if (_enCurso) {
      return (ok: false, mensaje: 'Ya hay un reinicio en curso.');
    }
    _enCurso = true;
    final pasos = <String>[];
    try {
      // ── STOP ────────────────────────────────────────────────────────────
      await SyncQueueService.instance.stop();
      pasos.add('cola sync detenida');
      await FirestoreSyncService.instance.stop();
      pasos.add('listeners Firestore detenidos');
      await ComunicacionesService.instance.detener();
      pasos.add('comunicaciones detenidas');
      AutoBackupService.instance.detener();
      pasos.add('auto-backup detenido');

      // Breve pausa para liberar sockets/timers.
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // ── START ───────────────────────────────────────────────────────────
      await FirestoreSyncService.instance.start();
      pasos.add('Firestore reiniciado');
      await SyncQueueService.instance.start();
      SyncQueueService.instance.clearAuthError();
      pasos.add('cola sync reiniciada');
      await ComunicacionesService.instance.iniciar();
      pasos.add('comunicaciones reiniciadas');
      await AutoBackupService.instance.iniciar();
      pasos.add('auto-backup reiniciado');

      try {
        await PermisosService.instance.cargar();
        pasos.add('permisos recargados');
      } catch (e) {
        debugPrint('Reinicio: permisos $e');
      }

      DataRefreshHub.instance.notifyTodo();

      await AuthService.instance.registrarCambio(
        'REINICIAR_SISTEMA',
        'sistema',
        'Reinicio de servicios internos (sin borrar datos)',
        valorNuevo: pasos.join(' → '),
      );

      return (
        ok: true,
        mensaje:
            'Servicios reiniciados. Los datos locales no se modificaron.',
      );
    } catch (e, st) {
      debugPrint('Reiniciar sistema: $e\n$st');
      // Intento de recuperación parcial
      try {
        await FirestoreSyncService.instance.start();
        await SyncQueueService.instance.start();
        await ComunicacionesService.instance.iniciar();
        await AutoBackupService.instance.iniciar();
      } catch (e2) {
        debugPrint('Reinicio recuperación: $e2');
      }
      await AuthService.instance.registrarCambio(
        'REINICIAR_SISTEMA_ERROR',
        'sistema',
        'Error al reiniciar servicios: $e',
      );
      return (
        ok: false,
        mensaje: 'No se pudo completar el reinicio: $e',
      );
    } finally {
      _enCurso = false;
    }
  }
}
