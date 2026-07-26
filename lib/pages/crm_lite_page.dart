import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/crm_seguimiento.dart';
import '../services/branding_service.dart';
import '../services/crm_lite_service.dart';
import '../services/crm_seguimiento_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/whatsapp_plantillas_service.dart';
import '../theme/app_tokens.dart';
import '../theme/module_app_bar.dart';
import '../widgets/cliente_acciones_crm.dart';
import '../widgets/crm_nuevo_seguimiento_sheet.dart';
import '../widgets/erp/erp_kpi_tile.dart';
import '../widgets/erp/erp_section_header.dart';
import 'cliente_detalle_page.dart';
import 'cuenta_corriente_cliente_page.dart';

/// Bandeja operativa de seguimiento comercial (CRM Lite).
class CrmLitePage extends StatefulWidget {
  const CrmLitePage({super.key});

  @override
  State<CrmLitePage> createState() => _CrmLitePageState();
}

class _CrmLitePageState extends State<CrmLitePage>
    with SingleTickerProviderStateMixin {
  final _svc = CrmLiteService.instance;
  final _agendaSvc = CrmSeguimientoService.instance;
  final _tpl = WhatsappPlantillasService.instance;
  late final TabController _tabs;

  CrmLiteResumen? _resumen;
  List<ClienteDeudor> _deudores = [];
  List<Map<String, dynamic>> _inactivos = [];
  List<Map<String, dynamic>> _conNotas = [];
  List<CrmSeguimiento> _agenda = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
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
    await _tpl.cargar();
    final resumen = await _svc.resumen();
    final deudores = await _svc.deudores();
    final inactivos = await _svc.inactivos();
    final notas = await _svc.conNotasRecientes();
    final agenda = await _agendaSvc.listarPendientes();
    if (!mounted) return;
    setState(() {
      _resumen = resumen;
      _deudores = deudores;
      _inactivos = inactivos;
      _conNotas = notas;
      _agenda = agenda;
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

  Future<void> _waCobro(ClienteDeudor d) async {
    final c = await _svc.obtenerCliente(d.clienteId);
    if (c == null || !mounted) return;
    final msg = _tpl.render(
      _tpl.cobro,
      nombre: c.nombre,
      monto: _money(d.saldoPendiente),
      empresa: BrandingService.instance.nombre,
    );
    await ClienteAccionesCrm.abrirWhatsApp(context, c, mensaje: msg);
  }

  Future<void> _waReactivar(int? id) async {
    if (id == null) return;
    final c = await _svc.obtenerCliente(id);
    if (c == null || !mounted) return;
    final msg = _tpl.render(
      _tpl.reactivar,
      nombre: c.nombre,
      empresa: BrandingService.instance.nombre,
    );
    await ClienteAccionesCrm.abrirWhatsApp(context, c, mensaje: msg);
  }

  Future<void> _programarDeuda(ClienteDeudor d) async {
    final c = await _svc.obtenerCliente(d.clienteId);
    if (c == null || !mounted) return;
    final ok = await showNuevoSeguimientoSheet(
      context,
      cliente: c,
      tipoInicial: 'cobro',
      tituloInicial: 'Cobrar ${_money(d.saldoPendiente)}',
      notaInicial: '${d.ventasPendientes} docs pendientes',
      diasDefault: 2,
    );
    if (ok && mounted) _cargar();
  }

  Future<void> _programarInactivo(int? id) async {
    if (id == null) return;
    final c = await _svc.obtenerCliente(id);
    if (c == null || !mounted) return;
    final ok = await showNuevoSeguimientoSheet(
      context,
      cliente: c,
      tipoInicial: 'reactivar',
      tituloInicial: 'Reactivar contacto',
      diasDefault: 1,
    );
    if (ok && mounted) _cargar();
  }

  Future<void> _editarPlantillas() async {
    await _tpl.cargar();
    if (!mounted) return;
    final cobroCtrl = TextEditingController(text: _tpl.cobro);
    final reacCtrl = TextEditingController(text: _tpl.reactivar);
    final genCtrl = TextEditingController(text: _tpl.general);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Plantillas WhatsApp'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Variables: {nombre} {monto} {empresa}',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cobroCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Cobro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reacCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reactivar',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: genCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'General',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final cobro = cobroCtrl.text;
    final reac = reacCtrl.text;
    final gen = genCtrl.text;
    cobroCtrl.dispose();
    reacCtrl.dispose();
    genCtrl.dispose();
    if (ok == true) {
      await _tpl.guardar(
        cobroTpl: cobro,
        reactivarTpl: reac,
        generalTpl: gen,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plantillas guardadas')),
      );
    }
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

  String _fmtFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/'
      '${f.month.toString().padLeft(2, '0')}/'
      '${f.year}';

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
            tooltip: 'Plantillas WhatsApp',
            icon: const Icon(Icons.sms_rounded),
            onPressed: _editarPlantillas,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _cargar,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: 'Agenda (${r?.agendaPendientes ?? _agenda.length})'),
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
                            'Agenda, cobros, reactivación y notas · local',
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
                                title: 'Agenda',
                                value: '${r?.agendaPendientes ?? 0}',
                                icon: Icons.event_available_rounded,
                                accent: cs.primary,
                                onTap: () => _tabs.animateTo(0),
                              ),
                              ErpKpiTile(
                                compact: true,
                                title: 'Vencidos',
                                value: '${r?.agendaVencidos ?? 0}',
                                icon: Icons.warning_amber_rounded,
                                accent: AppTokens.danger,
                                onTap: () => _tabs.animateTo(0),
                              ),
                              ErpKpiTile(
                                compact: true,
                                title: 'Con deuda',
                                value: '${r?.deudores ?? 0}',
                                icon: Icons.account_balance_wallet_rounded,
                                accent: AppTokens.danger,
                                onTap: () => _tabs.animateTo(1),
                              ),
                              ErpKpiTile(
                                compact: true,
                                title: 'Inactivos 30d',
                                value: '${r?.inactivos ?? 0}',
                                icon: Icons.hourglass_empty_rounded,
                                accent: AppTokens.syncWarn,
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
                      _listaAgenda(cs),
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

  Widget _listaAgenda(ColorScheme cs) {
    if (_agenda.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined, size: 56, color: cs.outline),
            const SizedBox(height: 8),
            const Text('Sin seguimientos pendientes'),
            const SizedBox(height: 4),
            Text(
              'Programalos desde Deuda o Inactivos',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _agenda.length,
      itemBuilder: (_, i) {
        final s = _agenda[i];
        final color = s.vencido
            ? AppTokens.danger
            : s.tipo == 'cobro'
                ? AppTokens.danger
                : AppTokens.syncWarn;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(
                s.tipo == 'cobro'
                    ? Icons.payments_rounded
                    : s.tipo == 'reactivar'
                        ? Icons.restart_alt_rounded
                        : Icons.event_rounded,
                color: color,
              ),
            ),
            title: Text(
              s.titulo,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${s.clienteNombre} · ${_fmtFecha(s.fechaVencimiento)}'
              '${s.vencido ? ' · VENCIDO' : ''}'
              '${s.nota.isEmpty ? '' : '\n${s.nota}'}',
            ),
            isThreeLine: s.nota.isNotEmpty,
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'hecho' && s.id != null) {
                  await _agendaSvc.marcarHecho(s.id!);
                } else if (v == 'cancel' && s.id != null) {
                  await _agendaSvc.cancelar(s.id!);
                } else if (v == 'wa') {
                  final c = await _svc.obtenerCliente(s.clienteId);
                  if (c == null || !mounted) return;
                  final msg = _tpl.render(
                    s.tipo == 'cobro'
                        ? _tpl.cobro
                        : s.tipo == 'reactivar'
                            ? _tpl.reactivar
                            : _tpl.general,
                    nombre: c.nombre,
                    empresa: BrandingService.instance.nombre,
                  );
                  await ClienteAccionesCrm.abrirWhatsApp(
                    context,
                    c,
                    mensaje: msg,
                  );
                } else if (v == 'ficha') {
                  await _abrirClienteId(s.clienteId);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'wa', child: Text('WhatsApp')),
                PopupMenuItem(value: 'hecho', child: Text('Marcar hecho')),
                PopupMenuItem(value: 'ficha', child: Text('Ver ficha')),
                PopupMenuItem(value: 'cancel', child: Text('Cancelar')),
              ],
            ),
            onTap: () => _abrirClienteId(s.clienteId),
          ),
        );
      },
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
            title: Text(
              d.nombre,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${d.ventasPendientes} documentos pendientes'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _money(d.saldoPendiente),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTokens.danger,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'wa') await _waCobro(d);
                    if (v == 'agenda') await _programarDeuda(d);
                    if (v == 'ficha') await _abrirDeudor(d);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'wa', child: Text('WhatsApp cobro')),
                    PopupMenuItem(
                      value: 'agenda',
                      child: Text('Programar seguimiento'),
                    ),
                    PopupMenuItem(value: 'ficha', child: Text('Ver ficha')),
                  ],
                ),
              ],
            ),
            onTap: () => _abrirDeudor(d),
            onLongPress: () => _waCobro(d),
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
              child: const Icon(
                Icons.schedule_rounded,
                color: AppTokens.syncWarn,
              ),
            ),
            title: Text(
              nombre,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              (m['telefono'] ?? m['whatsapp'] ?? 'Sin teléfono').toString(),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'WhatsApp',
                  icon: const Icon(Icons.chat_rounded),
                  onPressed: () => _waReactivar(id),
                ),
                IconButton(
                  tooltip: 'Programar',
                  icon: const Icon(Icons.event_rounded),
                  onPressed: () => _programarInactivo(id),
                ),
              ],
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
            title: Text(
              nombre,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('$cant nota(s) · ${m['ultimaNota'] ?? ''}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _abrirClienteId(id),
          ),
        );
      },
    );
  }
}
