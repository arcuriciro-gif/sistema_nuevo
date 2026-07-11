import 'package:flutter/material.dart';

import '../models/pago.dart';
import '../models/venta.dart';
import '../services/cuenta_corriente_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cobrar_dialog.dart';
import 'venta_factura_page.dart';

class CuentaCorrienteClientePage extends StatefulWidget {
  final int clienteId;
  final String clienteNombre;

  const CuentaCorrienteClientePage({
    super.key,
    required this.clienteId,
    required this.clienteNombre,
  });

  @override
  State<CuentaCorrienteClientePage> createState() =>
      _CuentaCorrienteClientePageState();
}

class _CuentaCorrienteClientePageState extends State<CuentaCorrienteClientePage>
    with SingleTickerProviderStateMixin {
  final _service = CuentaCorrienteService();
  late final TabController _tabs;
  List<Venta> _ventas = [];
  List<Map<String, dynamic>> _remitos = [];
  List<Pago> _pagos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final ventas = await _service.ventasDeCliente(widget.clienteId);
    final remitos = await _service.remitosDeCliente(widget.clienteId);
    final pagos = await _service.pagosDeCliente(widget.clienteId);
    if (!mounted) return;
    setState(() {
      _ventas = ventas;
      _remitos = remitos;
      _pagos = pagos;
      _cargando = false;
    });
  }

  double get _saldoVentas => _ventas
      .where((v) => v.estado != 'anulada')
      .fold<double>(0, (s, v) => s + v.saldoPendiente);

  double get _saldoRemitos => _remitos.fold<double>(0, (s, r) {
        final estado = r['estado']?.toString() ?? '';
        final estadoPago = (r['estadoPago']?.toString() ?? 'pendiente');
        if (estado == 'anulado' || estadoPago == 'cobrado') return s;
        final saldo = (r['saldoPendiente'] as num?)?.toDouble();
        if (saldo != null) return s + saldo;
        return s + ((r['total'] as num?)?.toDouble() ?? 0);
      });

  double get _saldoActual => _saldoVentas + _saldoRemitos;

  String _fmtFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/'
      '${f.year}';

  Future<void> _cobrarVenta(Venta venta) async {
    final ok = await mostrarDialogoCobrar(context: context, venta: venta);
    if (ok) await _cargar();
  }

  Future<void> _cobrarRemito(Map<String, dynamic> remito) async {
    final id = remito['id'] as int?;
    if (id == null) return;
    final total = (remito['total'] as num?)?.toDouble() ?? 0;
    final saldo = (remito['saldoPendiente'] as num?)?.toDouble() ?? total;
    final numero = remito['numero']?.toString() ?? '$id';
    final ok = await mostrarDialogoCobrarRemito(
      context: context,
      remitoId: id,
      numero: numero,
      saldoPendiente: saldo,
    );
    if (ok) await _cargar();
  }

  Future<void> _cobrarCualquiera() async {
    final conSaldo =
        _ventas.where((v) => v.saldoPendiente > 0.009 && v.id != null).toList();
    final remitosPend = _remitos.where((r) {
      final estadoPago = (r['estadoPago']?.toString() ?? 'pendiente');
      final saldo = (r['saldoPendiente'] as num?)?.toDouble() ??
          ((r['total'] as num?)?.toDouble() ?? 0);
      return estadoPago != 'cobrado' && saldo > 0.009;
    }).toList();

    if (conSaldo.isEmpty && remitosPend.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay saldos pendientes')),
      );
      return;
    }

    if (conSaldo.isNotEmpty) {
      conSaldo.sort((a, b) => a.fecha.compareTo(b.fecha));
      await _cobrarVenta(conSaldo.first);
      return;
    }

    await _cobrarRemito(remitosPend.first);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Cuenta corriente',
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Ventas (${_ventas.length})'),
            Tab(text: 'Remitos (${_remitos.length})'),
            Tab(text: 'Pagos (${_pagos.length})'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _cargando ? null : _cobrarCualquiera,
            icon: const Icon(Icons.payments_rounded),
            label: const Text('Registrar pago'),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: cs.surfaceContainerHighest,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.clienteNombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Saldo actual',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        '\$${_saldoActual.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _saldoActual > 0
                              ? colorEstadoPago('pendiente', cs)
                              : colorEstadoPago('cobrado', cs),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ventas: \$${_saldoVentas.toStringAsFixed(2)} · '
                        'Remitos: \$${_saldoRemitos.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _listaVentas(cs),
                      _listaRemitos(cs),
                      _listaPagos(cs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _listaVentas(ColorScheme cs) {
    if (_ventas.isEmpty) {
      return const Center(child: Text('Sin ventas registradas'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _ventas.length,
      itemBuilder: (_, i) {
        final v = _ventas[i];
        final puedeCobrar =
            v.saldoPendiente > 0.009 && v.estado != 'anulada';
        return Card(
          child: InkWell(
            onTap: v.id == null
                ? null
                : () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VentaFacturaPage(
                          tipo: v.tipo,
                          ventaId: v.id,
                        ),
                      ),
                    );
                    await _cargar();
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${v.tipoLabel} ${v.numero}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtFecha(v.fecha),
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total \$${v.total.toStringAsFixed(2)} · '
                          'Pagado \$${v.totalPagado.toStringAsFixed(2)} · '
                          'Saldo \$${v.saldoPendiente.toStringAsFixed(2)}'
                          '${v.fechaVencimiento == null ? '' : ' · Vence ${_fmtFecha(v.fechaVencimiento!)}'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      chipEstadoPago(v.estadoPago, cs),
                      if (puedeCobrar)
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _cobrarVenta(v),
                          child: const Text('Cobrar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _listaRemitos(ColorScheme cs) {
    if (_remitos.isEmpty) {
      return const Center(child: Text('Sin remitos registrados'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _remitos.length,
      itemBuilder: (_, i) {
        final r = _remitos[i];
        final id = r['id'] as int?;
        final numero = r['numero']?.toString() ?? '';
        final total = (r['total'] as num?)?.toDouble() ?? 0;
        final saldo =
            (r['saldoPendiente'] as num?)?.toDouble() ?? total;
        final estadoPago = (r['estadoPago']?.toString() ?? 'pendiente');
        final fecha =
            DateTime.tryParse(r['fecha']?.toString() ?? '') ?? DateTime.now();
        final pendiente = estadoPago != 'cobrado' && saldo > 0.009;

        return Card(
          child: ListTile(
            title: Text(
              'Remito $numero',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${_fmtFecha(fecha)}\n'
              'Total \$${total.toStringAsFixed(2)} · '
              'Saldo \$${saldo.toStringAsFixed(2)}',
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                chipEstadoPago(estadoPago, cs),
                if (pendiente && id != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => _cobrarRemito(r),
                    child: const Text('Cobrar'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _listaPagos(ColorScheme cs) {
    if (_pagos.isEmpty) {
      return const Center(child: Text('Sin pagos registrados'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _pagos.length,
      itemBuilder: (_, i) {
        final p = _pagos[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  colorEstadoPago('cobrado', cs).withValues(alpha: .15),
              child: Icon(
                Icons.payments_rounded,
                color: colorEstadoPago('cobrado', cs),
              ),
            ),
            title: Text('\$${p.monto.toStringAsFixed(2)}'),
            subtitle: Text(
              '${_fmtFecha(p.fecha)} · ${Pago.labelMedio(p.medioPago)}\n'
              'Comp. ${p.ventaNumero ?? p.ventaId}'
              '${p.observaciones.isNotEmpty ? ' · ${p.observaciones}' : ''}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
