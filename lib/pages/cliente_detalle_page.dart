import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../services/cliente_service.dart';
import '../services/remito_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import '../widgets/foto_ampliada.dart';
import '../widgets/media_avatar.dart';
import 'cliente_form_page.dart';
import 'cliente_historial_page.dart';
import 'cuenta_corriente_cliente_page.dart';

/// Ficha de lectura del cliente: datos, foto, descuento e historial reciente.
class ClienteDetallePage extends StatefulWidget {
  final Cliente cliente;

  const ClienteDetallePage({super.key, required this.cliente});

  @override
  State<ClienteDetallePage> createState() => _ClienteDetallePageState();
}

class _ClienteDetallePageState extends State<ClienteDetallePage> {
  late Cliente _cliente;
  final RemitoService _remitoService = RemitoService();
  List<Map<String, dynamic>> _remitos = [];
  bool _cargandoHist = true;

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHist = true);
    final id = _cliente.id ?? 0;
    final todos = id == 0
        ? <Map<String, dynamic>>[]
        : await _remitoService.obtenerPorCliente(id);
    if (!mounted) return;
    setState(() {
      _remitos = todos.take(8).toList();
      _cargandoHist = false;
    });
  }

  Future<void> _abrirEdicion() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: _cliente)),
    );
    if (!mounted) return;
    // El listado padre recarga al volver.
    Navigator.pop(context, true);
  }

  String _fmtFecha(String? raw) {
    final f = DateTime.tryParse(raw ?? '');
    if (f == null) return '-';
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/'
        '${f.year}';
  }

  Widget _fila(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _cliente;
    final direccionFull = [
      c.direccion,
      if (c.localidad.isNotEmpty) c.localidad,
      if (c.provincia.isNotEmpty) c.provincia,
    ].where((e) => e.trim().isNotEmpty).join(', ');

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Ficha del cliente',
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_rounded),
            onPressed: _abrirEdicion,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: c.foto.trim().isEmpty
                      ? null
                      : () => showFotoAmpliada(
                            context,
                            path: c.foto,
                            titulo: c.nombreCompleto,
                          ),
                  child: MediaAvatar(
                    path: c.foto,
                    radius: 52,
                    fallbackLetter:
                        c.nombre.isNotEmpty ? c.nombre[0] : '?',
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  c.nombreCompleto,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (c.foto.trim().isNotEmpty)
                  Text(
                    'Tocá la foto para ampliar',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contacto',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fila(Icons.phone_rounded, 'Teléfono', c.telefono),
                  _fila(Icons.chat_rounded, 'WhatsApp', c.whatsapp),
                  _fila(Icons.email_outlined, 'Email', c.email),
                  _fila(Icons.home_outlined, 'Dirección', direccionFull),
                  _fila(Icons.badge_outlined, 'CUIT', c.cuit),
                  _fila(
                    Icons.receipt_long_outlined,
                    'Condición IVA',
                    c.condicionIva,
                  ),
                  _fila(Icons.notes_rounded, 'Observaciones', c.observaciones),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comercial',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _fila(
                    Icons.percent_rounded,
                    'Descuento / lista',
                    c.descuento > 0
                        ? '${c.descuento.toStringAsFixed(1)} %'
                        : 'Sin descuento',
                  ),
                  _fila(
                    Icons.account_balance_wallet_outlined,
                    'Saldo cuenta corriente',
                    '\$ ${c.saldo.toStringAsFixed(2)}',
                  ),
                  _fila(
                    Icons.credit_card_outlined,
                    'Límite de cuenta',
                    c.limiteCuenta > 0
                        ? '\$ ${c.limiteCuenta.toStringAsFixed(2)}'
                        : 'Sin límite',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: c.id == null
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CuentaCorrienteClientePage(
                              clienteId: c.id!,
                              clienteNombre: c.nombreCompleto,
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text('Cuenta corriente'),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClienteHistorialPage(cliente: c),
                    ),
                  );
                  _cargarHistorial();
                },
                icon: const Icon(Icons.history_rounded),
                label: const Text('Historial completo'),
              ),
              OutlinedButton.icon(
                onPressed: _abrirEdicion,
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Editar'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Últimos remitos',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (!_cargandoHist && _remitos.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClienteHistorialPage(cliente: c),
                      ),
                    );
                  },
                  child: const Text('Ver todos'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cargandoHist)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_remitos.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Todavía no hay remitos para este cliente.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            ..._remitos.map((r) {
              final estado = (r['estado'] ?? 'pendiente').toString();
              final total = (r['total'] as num?)?.toDouble() ?? 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(
                    r['numero']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(_fmtFecha(r['fecha']?.toString())),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$ ${total.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppVisuals.primaryAccent(cs),
                        ),
                      ),
                      Text(
                        estado,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClienteHistorialPage(cliente: c),
                      ),
                    );
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}
