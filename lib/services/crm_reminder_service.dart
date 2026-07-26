import 'package:shared_preferences/shared_preferences.dart';

import '../core/comms/local_notification_service.dart';
import '../models/crm_seguimiento.dart';
import 'crm_seguimiento_service.dart';

/// Recordatorios locales de agenda CRM (sin sync, 1 aviso/día).
class CrmReminderService {
  CrmReminderService._();
  static final CrmReminderService instance = CrmReminderService._();

  static const _keyUltimoAviso = 'crm_reminder_last_day';
  static const _keyEnabled = 'crm_reminder_enabled';
  static const notifId = 91001;
  static const payloadSeguimiento = 'crm:seguimiento';

  bool enabled = true;
  int vencidos = 0;
  int hoy = 0;
  List<CrmSeguimiento> pendientesCercanos = [];

  Future<void> cargarPreferencia() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_keyEnabled) ?? true;
  }

  Future<void> setEnabled(bool v) async {
    enabled = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyEnabled, v);
  }

  Future<void> refrescarConteos() async {
    final lista = await CrmSeguimientoService.instance.listarPendientes();
    final now = DateTime.now();
    final inicioHoy = DateTime(now.year, now.month, now.day);
    final finHoy = inicioHoy.add(const Duration(days: 1));
    vencidos = 0;
    hoy = 0;
    pendientesCercanos = [];
    for (final s in lista) {
      if (s.fechaVencimiento.isBefore(inicioHoy)) {
        vencidos++;
        pendientesCercanos.add(s);
      } else if (s.fechaVencimiento.isBefore(finHoy)) {
        hoy++;
        pendientesCercanos.add(s);
      }
    }
  }

  /// Avisa una vez por día si hay vencidos o pendientes de hoy.
  Future<void> revisarYNotificar({bool forzar = false}) async {
    await cargarPreferencia();
    await refrescarConteos();
    if (!enabled) return;
    if (vencidos <= 0 && hoy <= 0) return;

    final hoyKey =
        '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final p = await SharedPreferences.getInstance();
    if (!forzar && p.getString(_keyUltimoAviso) == hoyKey) return;

    final partes = <String>[];
    if (vencidos > 0) partes.add('$vencidos vencido(s)');
    if (hoy > 0) partes.add('$hoy para hoy');
    final cuerpo = pendientesCercanos.isEmpty
        ? partes.join(' · ')
        : '${partes.join(' · ')} · ej: ${pendientesCercanos.first.titulo}';

    await LocalNotificationService.instance.showWithId(
      id: notifId,
      titulo: 'Seguimiento comercial',
      cuerpo: cuerpo,
      payload: payloadSeguimiento,
    );
    await p.setString(_keyUltimoAviso, hoyKey);
  }
}
