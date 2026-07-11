import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/utils/media_path.dart';
import '../models/chat_mensaje.dart';
import '../models/cliente.dart';
import '../services/cliente_service.dart';
import '../theme/app_visuals.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import '../widgets/cobrar_dialog.dart';
import 'cliente_form_page.dart';
import 'cliente_historial_page.dart';
import 'cuenta_corriente_cliente_page.dart';
import '../theme/module_app_bar.dart';
import '../widgets/password_confirm_dialog.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final ClienteService service = ClienteService();
  final TextEditingController buscarController = TextEditingController();

  List<Cliente> clientes = [];
  List<Cliente> filtrados = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    cargar();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    cargar(silent: true);
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    buscarController.dispose();
    super.dispose();
  }

  Future<void> cargar({bool silent = false}) async {
    if (!silent && mounted) setState(() => cargando = true);
    clientes = await service.obtenerTodos();
    final q = buscarController.text;
    if (q.isEmpty) {
      filtrados = clientes;
    } else {
      final texto = q.toLowerCase();
      filtrados = clientes.where((c) {
        return c.nombre.toLowerCase().contains(texto) ||
            c.apellido.toLowerCase().contains(texto) ||
            c.telefono.toLowerCase().contains(texto) ||
            c.direccion.toLowerCase().contains(texto);
      }).toList();
    }
    if (!mounted) return;
    setState(() => cargando = false);
  }

  void buscar(String texto) {
    texto = texto.toLowerCase();
    filtrados = clientes.where((c) {
      return c.nombre.toLowerCase().contains(texto) ||
          c.apellido.toLowerCase().contains(texto) ||
          c.telefono.toLowerCase().contains(texto) ||
          c.direccion.toLowerCase().contains(texto);
    }).toList();
    setState(() {});
  }

  Future<void> confirmarEliminar(Cliente cliente) async {
    final ok = await confirmarConClave(
      context,
      titulo: 'Eliminar cliente',
      mensaje:
          'Vas a eliminar a ${cliente.nombreCompleto}. Esta acción no se puede deshacer.\n\nIngresá tu contraseña para confirmar.',
      confirmarLabel: 'Eliminar',
    );
    if (ok && cliente.id != null) {
      await service.eliminar(cliente.id!);
      cargar();
    }
  }

  Future<void> abrirHistorial(Cliente cliente) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClienteHistorialPage(cliente: cliente),
      ),
    );
    cargar();
  }

  Future<void> abrirCuentaCorriente(Cliente cliente) async {
    if (cliente.id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CuentaCorrienteClientePage(
          clienteId: cliente.id!,
          clienteNombre: cliente.nombreCompleto,
        ),
      ),
    );
    cargar();
  }

  Future<void> _editar(Cliente c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: c)),
    );
    cargar();
  }

  Future<void> _menuAcciones(Cliente c) async {
    final cs = Theme.of(context).colorScheme;
    final accion = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Editar'),
              onTap: () => Navigator.pop(ctx, 'editar'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded),
              title: const Text('Cuenta corriente'),
              onTap: () => Navigator.pop(ctx, 'cc'),
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Historial'),
              onTap: () => Navigator.pop(ctx, 'historial'),
            ),
            ListTile(
              leading: Icon(Icons.chat_bubble_outline_rounded,
                  color: cs.tertiary),
              title: const Text('Notas internas'),
              onTap: () => Navigator.pop(ctx, 'notas'),
            ),
            ListTile(
              leading: Icon(Icons.share_rounded, color: cs.secondary),
              title: const Text('Compartir en chat'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded,
                  color: AppVisuals.danger(cs)),
              title: Text(
                'Eliminar',
                style: TextStyle(color: AppVisuals.danger(cs)),
              ),
              onTap: () => Navigator.pop(ctx, 'eliminar'),
            ),
          ],
        ),
      ),
    );
    if (accion == null || !mounted) return;
    if (accion == 'editar') {
      await _editar(c);
      return;
    }
    if (accion == 'cc') {
      await abrirCuentaCorriente(c);
      return;
    }
    if (accion == 'historial') {
      await abrirHistorial(c);
      return;
    }
    if (accion == 'notas') {
      await showComentariosInternos(
        context,
        entidadTipo: 'cliente',
        entidadId: '${c.id}',
        titulo: c.nombreCompleto,
      );
      return;
    }
    if (accion == 'share') {
      await showCompartirEnChatDialog(
        context,
        compartido: ChatCompartido(
          tipo: 'cliente',
          idRef: '${c.id}',
          titulo: c.nombreCompleto,
          subtitulo: [
            if (c.cuit.isNotEmpty) 'CUIT ${c.cuit}',
            if (c.telefono.isNotEmpty) c.telefono,
            if (c.saldo > 0) 'Saldo \$${c.saldo.toStringAsFixed(2)}',
          ].join(' · '),
          datos: {
            'telefono': c.telefono,
            'email': c.email,
            'cuit': c.cuit,
            'saldo': c.saldo,
            'foto': c.foto,
          },
        ),
      );
      return;
    }
    if (accion == 'eliminar') {
      await confirmarEliminar(c);
    }
  }

  Widget _avatar(Cliente c, ColorScheme cs) {
    final provider = imageProviderDesdePath(c.foto);
    final inicial = c.nombreCompleto.trim().isNotEmpty
        ? c.nombreCompleto.trim()[0].toUpperCase()
        : '?';
    return CircleAvatar(
      radius: 26,
      backgroundColor: cs.primaryContainer,
      backgroundImage: provider,
      child: provider == null
          ? Text(
              inicial,
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Clientes',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_clientes',
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ClienteFormPage()),
          );
          cargar();
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: buscarController,
              onChanged: buscar,
              decoration: InputDecoration(
                hintText: 'Buscar cliente...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : filtrados.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay clientes.',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                        itemCount: filtrados.length,
                        itemBuilder: (context, i) {
                          final c = filtrados[i];
                          final deuda = c.saldo > 0.009;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => abrirHistorial(c),
                              onLongPress: () => _menuAcciones(c),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _avatar(c, colorScheme),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.nombreCompleto,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            softWrap: false,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              height: 1.2,
                                            ),
                                          ),
                                          if (c.telefono.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              c.telefono,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                          if (c.direccion.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              c.direccion,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                          if (deuda) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Deuda: \$${c.saldo.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: colorEstadoPago(
                                                  'pendiente',
                                                  colorScheme,
                                                ),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Más acciones',
                                      icon: const Icon(Icons.more_vert_rounded),
                                      onPressed: () => _menuAcciones(c),
                                    ),
                                  ],
                                ),
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
