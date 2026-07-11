import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/pago.dart';
import '../services/cuenta_corriente_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cobrar_dialog.dart';
import 'cuenta_corriente_cliente_page.dart';

class ClientesDeudoresPage extends StatefulWidget {
  const ClientesDeudoresPage({super.key});

  @override
  State<ClientesDeudoresPage> createState() => _ClientesDeudoresPageState();
}

class _ClientesDeudoresPageState extends State<ClientesDeudoresPage> {
  final _service = CuentaCorrienteService();
  List<ClienteDeudor> _deudores = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    _cargar();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    _cargar(silent: true);
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    super.dispose();
  }

  Future<void> _cargar({bool silent = false}) async {
    if (!silent && mounted) setState(() => _cargando = true);
    final lista = await _service.clientesDeudores();
    if (!mounted) return;
    setState(() {
      _deudores = lista;
      _cargando = false;
    });
  }

  String _fmtFecha(DateTime? f) {
    if (f == null) return '-';
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/'
        '${f.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total =
        _deudores.fold<double>(0, (s, d) => s + d.saldoPendiente);

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Clientes con deuda',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
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
                    color: cs.primaryContainer.withValues(alpha: .35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total adeudado',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorEstadoPago('pendiente', cs),
                        ),
                      ),
                      Text('${_deudores.length} clientes'),
                    ],
                  ),
                ),
                Expanded(
                  child: _deudores.isEmpty
                      ? const Center(child: Text('No hay clientes con deuda'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _deudores.length,
                          itemBuilder: (_, i) {
                            final d = _deudores[i];
                            return Card(
                              child: ListTile(
                                title: Text(
                                  d.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${d.telefono.isEmpty ? 'Sin teléfono' : d.telefono}\n'
                                  '${d.ventasPendientes} venta(s) · Última: ${_fmtFecha(d.ultimaCompra)}',
                                ),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\$${d.saldoPendiente.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorEstadoPago('pendiente', cs),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        await Navigator.push<void>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CuentaCorrienteClientePage(
                                              clienteId: d.clienteId,
                                              clienteNombre: d.nombre,
                                            ),
                                          ),
                                        );
                                        await _cargar();
                                      },
                                      child: const Text('Ver'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

/// Helper export for pages that need Pago labels without importing model.
typedef MedioPagoLabels = Pago;
