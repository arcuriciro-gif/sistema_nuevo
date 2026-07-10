import 'package:flutter/material.dart';

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
    cargar();
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
                        itemCount: filtrados.length,
                        itemBuilder: (context, i) {
                          final c = filtrados[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: ListTile(
                              onTap: () => abrirHistorial(c),
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Text(
                                  c.nombre.isNotEmpty
                                      ? c.nombre[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                c.nombreCompleto,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (c.telefono.isNotEmpty)
                                    Row(
                                      children: [
                                        const Icon(Icons.phone,
                                             size: 14),
                                        const SizedBox(width: 4),
                                        Text(c.telefono),
                                      ],
                                    ),
                                  if (c.direccion.isNotEmpty)
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on,
                                             size: 14),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(c.direccion)),
                                      ],
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
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Comentarios internos',
                                    icon: Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: colorScheme.tertiary,
                                    ),
                                    onPressed: () => showComentariosInternos(
                                      context,
                                      entidadTipo: 'cliente',
                                      entidadId: '${c.id}',
                                      titulo:
                                          '${c.nombre} ${c.apellido}'.trim(),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Compartir en chat',
                                    icon: Icon(
                                      Icons.share_rounded,
                                      color: colorScheme.secondary,
                                    ),
                                    onPressed: () => showCompartirEnChatDialog(
                                      context,
                                      compartido: ChatCompartido(
                                        tipo: 'cliente',
                                        idRef: '${c.id}',
                                        titulo:
                                            '${c.nombre} ${c.apellido}'.trim(),
                                        subtitulo: [
                                          if (c.cuit.isNotEmpty) 'CUIT ${c.cuit}',
                                          if (c.telefono.isNotEmpty) c.telefono,
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
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Cuenta corriente',
                                    icon: Icon(
                                      Icons.account_balance_wallet_rounded,
                                      color: colorScheme.primary,
                                    ),
                                    onPressed: () => abrirCuentaCorriente(c),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.history_rounded,
                                      color: colorScheme.primary,
                                    ),
                                    onPressed: () => abrirHistorial(c),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.edit_rounded,
                                      color: colorScheme.primary,
                                    ),
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ClienteFormPage(cliente: c),
                                        ),
                                      );
                                      cargar();
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_rounded,
                                      color: AppVisuals.danger(colorScheme),
                                    ),
                                    onPressed: () => confirmarEliminar(c),
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
