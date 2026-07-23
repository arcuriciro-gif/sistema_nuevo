import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/security/authorization_service.dart';
import '../models/proveedor.dart';
import '../services/proveedor_service.dart';
import '../theme/app_visuals.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'proveedor_form_page.dart';
import '../theme/module_app_bar.dart';

class ProveedoresPage extends StatefulWidget {
  const ProveedoresPage({super.key});

  @override
  State<ProveedoresPage> createState() => _ProveedoresPageState();
}

class _ProveedoresPageState extends State<ProveedoresPage> {
  final ProveedorService service = ProveedorService();

  final TextEditingController buscarController = TextEditingController();

  List<Proveedor> proveedores = [];
  List<Proveedor> filtrados = [];

  bool cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    cargarProveedores();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    cargarProveedores();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    buscarController.dispose();
    super.dispose();
  }

  Future<void> cargarProveedores() async {
    proveedores = await service.obtenerTodos();

    filtrados = proveedores;

    if (!mounted) return;

    setState(() {
      cargando = false;
    });
  }

  void buscar(String texto) {
    texto = texto.toLowerCase();

    filtrados = proveedores.where((p) {
      return p.nombre.toLowerCase().contains(texto) ||
          p.email.toLowerCase().contains(texto) ||
          p.telefono.toLowerCase().contains(texto);
    }).toList();

    setState(() {});
  }

  Future<void> eliminar(Proveedor proveedor) async {
    if (proveedor.id == null) return;

    await service.eliminar(proveedor.id!);

    cargarProveedores();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Proveedores',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: cargarProveedores,
          ),
        ],
      ),
      floatingActionButton: AuthorizationService.instance.puede(
              AuthModules.proveedores, AuthzAction.crear)
          ? FloatingActionButton(
              heroTag: 'fab_proveedores',
              child: const Icon(Icons.add),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProveedorFormPage(),
                  ),
                );

                cargarProveedores();
              },
            )
          : null,
      body: cargando
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: TextField(
                    controller: buscarController,
                    onChanged: buscar,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: "Buscar proveedor...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: filtrados.isEmpty
                      ? const Center(
                          child: Text("No hay proveedores registrados"),
                        )
                      : ListView.builder(
                          itemCount: filtrados.length,
                          itemBuilder: (context, index) {
                            final p = filtrados[index];

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  radius: 36,
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.local_shipping_rounded,
                                    size: 28,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  p.nombre,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text("Teléfono: ${p.telefono}"),
                                    Text("Email: ${p.email}"),
                                    Text(
                                      "Estado: ${p.activo ? "Activo" : "Inactivo"}",
                                      style: TextStyle(
                                        color: p.activo
                                            ? AppVisuals.success(colorScheme)
                                            : AppVisuals.danger(colorScheme),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Comentarios internos',
                                      icon: const Icon(
                                        Icons.chat_bubble_outline_rounded,
                                      ),
                                      onPressed: () => showComentariosInternos(
                                        context,
                                        entidadTipo: 'proveedor',
                                        entidadId: '${p.id}',
                                        titulo: p.nombre,
                                      ),
                                    ),
                                    PopupMenuButton(
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 1,
                                          child: Text("Editar"),
                                        ),
                                        const PopupMenuItem(
                                          value: 2,
                                          child: Text("Eliminar"),
                                        ),
                                      ],
                                      onSelected: (value) async {
                                        if (value == 1) {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ProveedorFormPage(
                                                proveedor: p,
                                              ),
                                            ),
                                          );

                                          cargarProveedores();
                                        }

                                        if (value == 2) {
                                          eliminar(p);
                                        }
                                      },
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
