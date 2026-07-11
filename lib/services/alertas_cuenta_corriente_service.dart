import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'comunicaciones_service.dart';
import 'cuenta_corriente_service.dart';

/// Notificaciones internas por deudas / vencimientos de cuenta corriente.
class AlertasCuentaCorrienteService {
  AlertasCuentaCorrienteService._();
  static final AlertasCuentaCorrienteService instance =
      AlertasCuentaCorrienteService._();

  static const _prefsKey = 'alerta_cc_digest_dia';
  bool _evaluando = false;

  String get _hoy {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<int> evaluarYNotificar({bool forzar = false}) async {
    if (_evaluando) return 0;
    _evaluando = true;
    try {
      final resumen = await CuentaCorrienteService().resumenDashboard();
      final relevantes = resumen.alertas
          .where((a) {
            final l = a.toLowerCase();
            return l.contains('vencid') ||
                l.contains('vencen') ||
                l.contains('deuda');
          })
          .toList();
      if (relevantes.isEmpty && resumen.montoTotalPendiente <= 0) return 0;

      final prefs = await SharedPreferences.getInstance();
      if (!forzar && prefs.getString(_prefsKey) == _hoy) return 0;

      final yo = AuthService.instance.currentUser?.usuario;
      if (yo == null || yo.isEmpty) return 0;

      final titulo = resumen.montoTotalPendiente > 0
          ? 'Cuentas por cobrar: \$${resumen.montoTotalPendiente.toStringAsFixed(0)}'
          : 'Recordatorio de cuentas corrientes';
      final cuerpo = (relevantes.isNotEmpty ? relevantes : resumen.alertas)
          .take(4)
          .join(' · ');

      await ComunicacionesService.instance.crearNotificacion(
        usuarioDestino: yo,
        tipo: 'cobro',
        titulo: titulo,
        cuerpo: cuerpo.isEmpty
            ? '${resumen.clientesConDeuda} clientes con saldo'
            : cuerpo,
        entidadTipo: 'cuenta_corriente',
        entidadId: 'deudores',
      );
      await prefs.setString(_prefsKey, _hoy);
      return 1;
    } finally {
      _evaluando = false;
    }
  }
}
