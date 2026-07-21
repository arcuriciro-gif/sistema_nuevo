import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../models/chat_mensaje.dart';
import '../models/cliente.dart';
import '../services/cliente_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import '../widgets/media_avatar.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import '../widgets/cobrar_dialog.dart';
import 'cliente_form_page.dart';
import 'cliente_detalle_page.dart';
import 'cliente_historial_page.dart';
import 'cuenta_corriente_cliente_page.dart';

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
    cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    buscarController.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    setState(() => cargando = true);
    clientes = await service.obtenerTodos();
    filtrados = clientes;
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
    final colorScheme = Theme.of(context).colorScheme;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Eliminar cliente"),
        content: Text("¿Eliminar a ${cliente.nombre}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              "Eliminar",
              style: TextStyle(
                color: AppVisuals.danger(colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && cliente.id != null) {
      await service.eliminar(cliente.id!);
      cargar();
    }
  }

  Future<void> abrirDetalle(Cliente cliente) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClienteDetallePage(cliente: cliente),
      ),
    );
    cargar();
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

  Widget _avatar(Cliente c, ColorScheme cs) {
    return MediaAvatar(
      path: c.foto,
      radius: 22,
      fallbackLetter: c.nombre.isNotEmpty ? c.nombre[0] : '?',
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
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
      floatingActionButton: AuthorizationService.instance.puede(
              AuthModules.clientes, AuthzAction.crear)
          ? FloatingActionButton(
              heroTag: 'fab_clientes',
              child: const Icon(Icons.add),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ClienteFormPage()),
                );
                cargar();
              },
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: buscarController,
              onChanged: buscar,
              decoration: InputDecoration(
                hintText: "Buscar cliente...",
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
                          "No hay clientes.",
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.only(
                          bottom: 80 + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        itemCount: filtrados.length,
                        itemBuilder: (context, i) {
                          final c = filtrados[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: InkWell(
                              onTap: () => abrirDetalle(c),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  4,
                                  10,
                                ),
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
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                          if (c.telefono.isNotEmpty)
                                            Text(
                                              c.telefono,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color:
                                                    colorScheme.onSurfaceVariant,
                                                fontSize: 13,
                                              ),
                                            ),
                                          if (c.direccion.isNotEmpty)
                                            Text(
                                              c.direccion,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color:
                                                    colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          if (c.saldo > 0.009)
                                            Text(
                                              'Deuda: \$${c.saldo.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: colorEstadoPago(
                                                  'pendiente',
                                                  colorScheme,
                                                ),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Acciones',
                                      onSelected: (value) async {
                                        switch (value) {
                                          case 'ficha':
                                            await abrirDetalle(c);
                                          case 'cc':
                                            await abrirCuentaCorriente(c);
                                          case 'hist':
                                            await abrirHistorial(c);
                                          case 'edit':
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ClienteFormPage(cliente: c),
                                              ),
                                            );
                                            cargar();
                                          case 'coment':
                                            await showComentariosInternos(
                                              context,
                                              entidadTipo: 'cliente',
                                              entidadId: '${c.id}',
                                              titulo: c.nombreCompleto,
                                            );
                                          case 'share':
                                            await showCompartirEnChatDialog(
                                              context,
                                              compartido: ChatCompartido(
                                                tipo: 'cliente',
                                                idRef: '${c.id}',
                                                titulo: c.nombreCompleto,
                                                subtitulo: [
                                                  if (c.cuit.isNotEmpty)
                                                    'CUIT ${c.cuit}',
                                                  if (c.telefono.isNotEmpty)
                                                    c.telefono,
                                                  if (c.saldo > 0)
                                                    'Saldo \$${c.saldo.toStringAsFixed(2)}',
                                                ].join(' · '),
                                                datos: {
                                                  'telefono': c.telefono,
                                                  'email': c.email,
                                                  'cuit': c.cuit,
                                                  'saldo': c.saldo,
                                                },
                                              ),
                                            );
                                          case 'del':
                                            await confirmarEliminar(c);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'ficha',
                                          child: Text('Ver ficha'),
                                        ),
                                        PopupMenuItem(
                                          value: 'cc',
                                          child: Text('Cuenta corriente'),
                                        ),
                                        PopupMenuItem(
                                          value: 'hist',
                                          child: Text('Historial'),
                                        ),
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Editar'),
                                        ),
                                        PopupMenuItem(
                                          value: 'coment',
                                          child: Text('Comentarios'),
                                        ),
                                        PopupMenuItem(
                                          value: 'share',
                                          child: Text('Compartir en chat'),
                                        ),
                                        PopupMenuItem(
                                          value: 'del',
                                          child: Text('Eliminar'),
                                        ),
                                      ],
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
