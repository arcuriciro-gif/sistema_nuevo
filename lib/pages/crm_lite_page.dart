import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../services/crm_lite_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../theme/app_tokens.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cliente_acciones_crm.dart';
import '../widgets/erp/erp_kpi_tile.dart';
import '../widgets/erp/erp_section_header.dart';
import 'cliente_detalle_page.dart';
import 'cuenta_corriente_cliente_page.dart';

/// Bandeja operativa de seguimiento comercial (CRM Lite).
/// Solo lectura de datos locales existentes.
class CrmLitePage extends StatefulWidget {
  const CrmLitePage({super.key});

  @override
  State<CrmLitePage> createState() => _CrmLitePageState();
}

class _CrmLitePageState extends State<CrmLitePage>
    with SingleTickerProviderStateMixin {
  final _svc = CrmLiteService.instance;
  late final TabController _tabs;

  CrmLiteResumen? _resumen;
  List<ClienteDeudor> _deudores = [];
  List<Map<String, dynamic>> _inactivos = [];
  List<Map<String, dynamic>> _conNotas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    DataRefreshHub.instance.addListener(_onDatos);
    _cargar();
  }

  void _onDatos() {
    if (mounted) _cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatos);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final resumen = await _svc.resumen();
    final deudores = await _svc.deudores();
    final inactivos = await _svc.inactivos();
    final notas = await _svc.conNotasRecientes();
    if (!mounted) return;
    setState(() {
      _resumen = resumen;
      _deudores = deudores;
      _inactivos = inactivos;
      _conNotas = notas;
      _cargando = false;
    });
  }

  Future<void> _abrirClienteId(int? id) async {
    if (id == null) return;
    final c = await _svc.obtenerCliente(id);
    if (c == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClienteDetallePage(cliente: c)),
    );
    if (mounted) _cargar();
  }

  Future<void> _abrirDeudor(ClienteDeudor d) async {
    final c = await _svc.obtenerCliente(d.clienteId);
    if (!mounted) return;
    if (c != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ClienteDetallePage(cliente: c)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CuentaCorrienteClientePage(
            clienteId: d.clienteId,
            clienteNombre: d.nombre,
          ),
        ),
      );
    }
    if (mounted) _cargar();
  }

  static String _money(num v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$${buf.toString()}';
  }

  String _nombreMap(Map<String, dynamic> m) {
    final ap = (m['apellido'] ?? '').toString().trim();
    final nom = (m['nombre'] ?? '').toString().trim();
    if (ap.isEmpty) return nom.isEmpty ? 'Cliente' : nom;
    return '$nom $ap'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _resumen;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Seguimiento',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Deuda'),
            Tab(text: 'Inactivos'),
            Tab(text: 'Notas'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ErpSectionHeader(
                        title: 'Seguimiento comercial',
                        subtitle:
                            'Quién cobrar, quién reactivar y notas internas',
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, c) {
                          final cols = c.maxWidth >= 900 ? 4 : 2;
                          return GridView.count(
                            crossAxisCount: cols,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: cols >= 4 ? 2.8 : 2.4,
                            children: [
                              ErpKpiTile(
                                compact: true,
                                title: 'Con deuda',
                                value: '${r?.deudores ?? 0}',
                                icon: Icons.account_balance_wallet_rounded,
                                accent: AppTokens.danger,
                                onTap: () => _tabs.animateTo(0),
                              ),
                              ErpKpiTile(
                                compact: true,
                                title: 'Deuda total',
                                value: _money(r?.deudaTotal ?? 0),
                                icon: Icons.payments_rounded,
                                accent: cs.primary,
                                onTap: () => _tabs.animateTo(0),
                              ),
                              ErpKpiTile(
                                compact: true,
                                title: 'Inactivos 30d',
                                value: '${r?.inactivos ?? 0}',
                                icon: Icons.hourglass_empty_rounded,
                                accent: AppTokens.syncWarn,
                                onTap: () => _tabs.animateTo(1),
                              ),
                              ErpKpiTile(
                                compact: true,
                                title: 'Con notas',
                                value: '${r?.conNotas ?? 0}',
                                icon: Icons.sticky_note_2_outlined,
                                accent: AppTokens.success,
                                onTap: () => _tabs.animateTo(2),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _listaDeuda(cs),
                      _listaInactivos(cs),
                      _listaNotas(cs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _listaDeuda(ColorScheme cs) {
    if (_deudores.isEmpty) {
      return const Center(child: Text('No hay clientes con deuda'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _deudores.length,
      itemBuilder: (_, i) {
        final d = _deudores[i];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTokens.danger.withValues(alpha: 0.15),
              child: const Icon(Icons.person_rounded, color: AppTokens.danger),
            ),
            title: Text(d.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${d.ventasPendientes} documentos pendientes'),
            trailing: Text(
              _money(d.saldoPendiente),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTokens.danger,
              ),
            ),
            onTap: () => _abrirDeudor(d),
            onLongPress: () async {
              final c = await _svc.obtenerCliente(d.clienteId);
              if (c == null || !mounted) return;
              await ClienteAccionesCrm.abrirWhatsApp(
                context,
                c,
                mensaje:
                    'Hola ${c.nombre}, te escribo por el saldo pendiente de ${_money(d.saldoPendiente)}.',
              );
            },
          ),
        );
      },
    );
  }

  Widget _listaInactivos(ColorScheme cs) {
    if (_inactivos.isEmpty) {
      return const Center(child: Text('No hay clientes inactivos (30 días)'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _inactivos.length,
      itemBuilder: (_, i) {
        final m = _inactivos[i];
        final id = (m['id'] as num?)?.toInt();
        final nombre = _nombreMap(m);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTokens.syncWarn.withValues(alpha: 0.18),
              child: const Icon(Icons.schedule_rounded, color: AppTokens.syncWarn),
            ),
            title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              (m['telefono'] ?? m['whatsapp'] ?? 'Sin teléfono').toString(),
            ),
            trailing: IconButton(
              tooltip: 'WhatsApp',
              icon: const Icon(Icons.chat_rounded),
              onPressed: () async {
                final c = id == null ? null : await _svc.obtenerCliente(id);
                if (c == null || !mounted) return;
                await ClienteAccionesCrm.abrirWhatsApp(
                  context,
                  c,
                  mensaje: 'Hola ${c.nombre}, ¿cómo andás? ¿Necesitás algo?',
                );
              },
            ),
            onTap: () => _abrirClienteId(id),
          ),
        );
      },
    );
  }

  Widget _listaNotas(ColorScheme cs) {
    if (_conNotas.isEmpty) {
      return const Center(child: Text('Todavía no hay notas en clientes'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _conNotas.length,
      itemBuilder: (_, i) {
        final m = _conNotas[i];
        final id = (m['id'] as num?)?.toInt();
        final nombre = _nombreMap(m);
        final cant = (m['cantidadNotas'] as num?)?.toInt() ?? 0;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.sticky_note_2_outlined, color: cs.primary),
            ),
            title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('$cant nota(s) · ${m['ultimaNota'] ?? ''}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _abrirClienteId(id),
          ),
        );
      },
    );
  }
}
