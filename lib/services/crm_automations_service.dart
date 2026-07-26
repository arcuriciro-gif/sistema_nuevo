import 'package:shared_preferences/shared_preferences.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/crm_seguimiento.dart';
import 'crm_lite_service.dart';
import 'crm_seguimiento_service.dart';

class CrmAutomationResult {
  final int creadosCobro;
  final int creadosReactivar;
  final bool ejecutado;

  const CrmAutomationResult({
    this.creadosCobro = 0,
    this.creadosReactivar = 0,
    this.ejecutado = false,
  });

  int get total => creadosCobro + creadosReactivar;
}

/// Reglas locales de CRM (sin sync). Crean seguimientos con dedupe diario.
class CrmAutomationsService {
  CrmAutomationsService._();
  static final CrmAutomationsService instance = CrmAutomationsService._();

  static const _kEnabled = 'crm_auto_enabled';
  static const _kDeuda = 'crm_auto_deuda';
  static const _kInactivos = 'crm_auto_inactivos';
  static const _kDiasCobro = 'crm_auto_dias_cobro';
  static const _kDiasReactivar = 'crm_auto_dias_reactivar';
  static const _kMontoMin = 'crm_auto_monto_min';
  static const _kLastRun = 'crm_auto_last_run';
  static const _kMaxPorCorrida = 'crm_auto_max_run';

  bool enabled = false;
  bool reglaDeuda = true;
  bool reglaInactivos = true;
  int diasVencimientoCobro = 2;
  int diasVencimientoReactivar = 3;
  double montoMinimoDeuda = 0;
  int maxPorCorrida = 25;

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? false;
    reglaDeuda = p.getBool(_kDeuda) ?? true;
    reglaInactivos = p.getBool(_kInactivos) ?? true;
    diasVencimientoCobro = p.getInt(_kDiasCobro) ?? 2;
    diasVencimientoReactivar = p.getInt(_kDiasReactivar) ?? 3;
    montoMinimoDeuda = p.getDouble(_kMontoMin) ?? 0;
    maxPorCorrida = p.getInt(_kMaxPorCorrida) ?? 25;
  }

  Future<void> guardar({
    bool? enabled,
    bool? reglaDeuda,
    bool? reglaInactivos,
    int? diasVencimientoCobro,
    int? diasVencimientoReactivar,
    double? montoMinimoDeuda,
    int? maxPorCorrida,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (enabled != null) {
      this.enabled = enabled;
      await p.setBool(_kEnabled, enabled);
    }
    if (reglaDeuda != null) {
      this.reglaDeuda = reglaDeuda;
      await p.setBool(_kDeuda, reglaDeuda);
    }
    if (reglaInactivos != null) {
      this.reglaInactivos = reglaInactivos;
      await p.setBool(_kInactivos, reglaInactivos);
    }
    if (diasVencimientoCobro != null) {
      this.diasVencimientoCobro = diasVencimientoCobro.clamp(0, 60);
      await p.setInt(_kDiasCobro, this.diasVencimientoCobro);
    }
    if (diasVencimientoReactivar != null) {
      this.diasVencimientoReactivar = diasVencimientoReactivar.clamp(0, 60);
      await p.setInt(_kDiasReactivar, this.diasVencimientoReactivar);
    }
    if (montoMinimoDeuda != null) {
      this.montoMinimoDeuda = montoMinimoDeuda < 0 ? 0 : montoMinimoDeuda;
      await p.setDouble(_kMontoMin, this.montoMinimoDeuda);
    }
    if (maxPorCorrida != null) {
      this.maxPorCorrida = maxPorCorrida.clamp(1, 100);
      await p.setInt(_kMaxPorCorrida, this.maxPorCorrida);
    }
  }

  String _hoyKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<bool> _yaCorrioHoy() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastRun) == _hoyKey();
  }

  Future<void> _marcarCorridaHoy() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastRun, _hoyKey());
  }

  /// Ejecuta reglas. Por defecto 1 vez/día; [forzar] ignora el límite diario.
  Future<CrmAutomationResult> ejecutar({bool forzar = false}) async {
    await cargar();
    if (!enabled) {
      return const CrmAutomationResult(ejecutado: false);
    }
    if (!forzar && await _yaCorrioHoy()) {
      return const CrmAutomationResult(ejecutado: false);
    }

    final agenda = CrmSeguimientoService.instance;
    final lite = CrmLiteService.instance;
    final conPendiente = await agenda.clienteIdsConPendiente();

    var creadosCobro = 0;
    var creadosReactivar = 0;
    var cupo = maxPorCorrida;

    if (reglaDeuda && cupo > 0) {
      final deudores = await lite.deudores(limite: 200);
      for (final d in deudores) {
        if (cupo <= 0) break;
        if (conPendiente.contains(d.clienteId)) continue;
        if (d.saldoPendiente < montoMinimoDeuda) continue;
        final cuando = DateTime.now().add(Duration(days: diasVencimientoCobro));
        await agenda.crear(
          CrmSeguimiento(
            clienteId: d.clienteId,
            clienteNombre: d.nombre,
            titulo: 'Cobrar \$${d.saldoPendiente.toStringAsFixed(0)}',
            nota: 'Creado por automatización · ${d.ventasPendientes} docs',
            tipo: 'cobro',
            fechaVencimiento: DateTime(
              cuando.year,
              cuando.month,
              cuando.day,
              18,
            ),
            creadoEn: DateTime.now(),
          ),
          silent: true,
        );
        conPendiente.add(d.clienteId);
        creadosCobro++;
        cupo--;
      }
    }

    if (reglaInactivos && cupo > 0) {
      final inactivos = await lite.inactivos(limite: 200);
      for (final m in inactivos) {
        if (cupo <= 0) break;
        final id = (m['id'] as num?)?.toInt();
        if (id == null || conPendiente.contains(id)) continue;
        final ap = (m['apellido'] ?? '').toString().trim();
        final nom = (m['nombre'] ?? '').toString().trim();
        final nombre = ap.isEmpty ? (nom.isEmpty ? 'Cliente' : nom) : '$nom $ap';
        final cuando =
            DateTime.now().add(Duration(days: diasVencimientoReactivar));
        await agenda.crear(
          CrmSeguimiento(
            clienteId: id,
            clienteNombre: nombre.trim(),
            titulo: 'Reactivar contacto',
            nota: 'Creado por automatización · sin compras 30 días',
            tipo: 'reactivar',
            fechaVencimiento: DateTime(
              cuando.year,
              cuando.month,
              cuando.day,
              18,
            ),
            creadoEn: DateTime.now(),
          ),
          silent: true,
        );
        conPendiente.add(id);
        creadosReactivar++;
        cupo--;
      }
    }

    await _marcarCorridaHoy();
    if (creadosCobro + creadosReactivar > 0) {
      DataRefreshHub.instance.notifyTodo();
    }
    return CrmAutomationResult(
      creadosCobro: creadosCobro,
      creadosReactivar: creadosReactivar,
      ejecutado: true,
    );
  }
}
