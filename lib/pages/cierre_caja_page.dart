import 'package:flutter/material.dart';

import '../models/pago.dart';
import '../services/analytics_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';

/// Resumen del día: ventas, cobros por medio y ganancia.
class CierreCajaPage extends StatefulWidget {
  const CierreCajaPage({super.key});

  @override
  State<CierreCajaPage> createState() => _CierreCajaPageState();
}

class _CierreCajaPageState extends State<CierreCajaPage> {
  final _cc = CuentaCorrienteService();
  DateTime _dia = DateTime.now();
  bool _cargando = true;
  String? _error;

  double _ventas = 0;
  double _ganancia = 0;
  double _cobros = 0;
  List<Map<String, dynamic>> _porMedio = [];
  List<Pago> _pagos = [];

  DateTime get _desde => DateTime(_dia.year, _dia.month, _dia.day);
  DateTime get _hasta =>
      DateTime(_dia.year, _dia.month, _dia.day, 23, 59, 59, 999);

  String get _labelDia {
    final hoy = DateTime.now();
    final esHoy =
        _dia.year == hoy.year && _dia.month == hoy.month && _dia.day == hoy.day;
    final base =
        '${_dia.day.toString().padLeft(2, '0')}/${_dia.month.toString().padLeft(2, '0')}/${_dia.year}';
    return esHoy ? 'Hoy · $base' : base;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final analytics = AnalyticsService.instance;
      final ventas = await analytics.ventasTotales(desde: _desde, hasta: _hasta);
      final ganancia =
          await analytics.gananciaReal(desde: _desde, hasta: _hasta);
      final pagos = await _cc.pagosPorPeriodo(_desde, _hasta);
      final porMedio = await _cc.resumenCobrosPorMedio(_desde, _hasta);
      if (!mounted) return;
      setState(() {
        _ventas = ventas;
        _ganancia = ganancia;
        _pagos = pagos;
        _cobros = pagos.fold<double>(0, (s, p) => s + p.monto);
        _porMedio = porMedio;
      });
    } catch (e, st) {
      debugPrint('Cierre de caja: $e\n$st');
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirDia() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _dia = picked);
    await _cargar();
  }

  Widget _kpi(String titulo, String valor, IconData icono, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .15),
              child: Icon(icono, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontSize: 13)),
                  Text(
                    valor,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cuerpoError(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'No se pudo cargar el cierre de caja',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final efectivo = _porMedio
        .where((m) => (m['medioPago']?.toString() ?? '') == 'efectivo')
        .fold<double>(0, (s, m) => s + ((m['total'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Cierre de caja',
        actions: [
          IconButton(
            tooltip: 'Elegir día',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _elegirDia,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _cuerpoError(cs)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      Text(
                        _labelDia,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ventas = comprobantes del día. Cobros = dinero recibido '
                        '(puede incluir deudas anteriores).',
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      _kpi(
                        'Ventas del día',
                        '\$${_ventas.toStringAsFixed(2)}',
                        Icons.point_of_sale_rounded,
                        AppVisuals.primaryAccent(cs),
                      ),
                      _kpi(
                        'Cobros recibidos',
                        '\$${_cobros.toStringAsFixed(2)}',
                        Icons.payments_rounded,
                        AppVisuals.success(cs),
                      ),
                      _kpi(
                        'Efectivo (cobros)',
                        '\$${efectivo.toStringAsFixed(2)}',
                        Icons.payments_outlined,
                        AppVisuals.warning(cs),
                      ),
                      _kpi(
                        'Ganancia real',
                        '\$${_ganancia.toStringAsFixed(2)}',
                        Icons.trending_up_rounded,
                        AppVisuals.info(cs),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cobros por medio de pago',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (_porMedio.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12, top: 8),
                                  child: Text('Sin cobros en este día.'),
                                )
                              else
                                ..._porMedio.map((m) {
                                  final medio =
                                      m['medioPago']?.toString() ?? 'otro';
                                  final total =
                                      (m['total'] as num?)?.toDouble() ?? 0;
                                  final ops = (m['ops'] as num?)?.toInt() ?? 0;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(Pago.labelMedio(medio)),
                                    subtitle: Text(
                                      '$ops operación${ops == 1 ? '' : 'es'}',
                                    ),
                                    trailing: Text(
                                      '\$${total.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Detalle de cobros (${_pagos.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              if (_pagos.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12, top: 8),
                                  child: Text('No hay pagos registrados.'),
                                )
                              else
                                ..._pagos.take(40).map((p) {
                                  final hora =
                                      '${p.fecha.hour.toString().padLeft(2, '0')}:${p.fecha.minute.toString().padLeft(2, '0')}';
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      p.clienteNombre?.isNotEmpty == true
                                          ? p.clienteNombre!
                                          : (p.ventaNumero ?? 'Cobro'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '$hora · ${Pago.labelMedio(p.medioPago)}',
                                    ),
                                    trailing: Text(
                                      '\$${p.monto.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
