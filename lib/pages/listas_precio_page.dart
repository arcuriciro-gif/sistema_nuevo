import 'package:flutter/material.dart';

import '../models/lista_precio.dart';
import '../services/lista_precio_service.dart';
import '../theme/app_visuals.dart';

class ListasPrecioPage extends StatefulWidget {
  const ListasPrecioPage({super.key});

  @override
  State<ListasPrecioPage> createState() => _ListasPrecioPageState();
}

class _ListasPrecioPageState extends State<ListasPrecioPage> {
  final ListaPrecioService service = ListaPrecioService();

  List<ListaPrecio> listas = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);
    listas = await service.obtenerTodas();
    if (!mounted) return;
    setState(() => cargando = false);
  }

  Future<void> _editarLista({ListaPrecio? lista}) async {
    final nombreCtrl = TextEditingController(text: lista?.nombre ?? '');
    final porcentajeCtrl = TextEditingController(
      text: (lista?.porcentaje ?? 0).toStringAsFixed(1),
    );
    bool activa = lista?.activa ?? true;

    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(lista == null ? 'Nueva lista de precios' : 'Editar lista'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: porcentajeCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Porcentaje de ganancia',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: activa,
                onChanged: (v) => setDialogState(() => activa = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (resultado != true) return;

    final nombre = nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    final porcentaje =
        double.tryParse(porcentajeCtrl.text.replaceAll(',', '.')) ?? 0;

    if (lista == null) {
      await service.insertar(
        ListaPrecio(
          nombre: nombre,
          porcentaje: porcentaje,
          activa: activa,
          orden: listas.length,
        ),
      );
    } else {
      await service.actualizar(
        lista.copyWith(nombre: nombre, porcentaje: porcentaje, activa: activa),
      );
    }

    await _cargar();
  }

  Future<void> _eliminar(ListaPrecio lista) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text('¿Eliminar la lista "${lista.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Eliminar',
              style: TextStyle(
                color: AppVisuals.danger(Theme.of(context).colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && lista.id != null) {
      await service.eliminar(lista.id!);
      await _cargar();
    }
  }

  Future<void> _toggleActiva(ListaPrecio lista) async {
    await service.actualizar(lista.copyWith(activa: !lista.activa));
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_listas_precio',
        onPressed: () => _editarLista(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva lista'),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Listas de precios',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'El precio se calcula como: costo × (1 + porcentaje / 100)',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: listas.isEmpty
                        ? const Center(
                            child: Text('No hay listas de precios creadas.'),
                          )
                        : ListView.builder(
                            itemCount: listas.length,
                            itemBuilder: (context, i) {
                              final lista = listas[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.sell_rounded,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  title: Text(
                                    lista.nombre,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    'Ganancia: ${lista.porcentaje.toStringAsFixed(1)}%',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: lista.activa,
                                        onChanged: (_) => _toggleActiva(lista),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded),
                                        onPressed: () =>
                                            _editarLista(lista: lista),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_rounded,
                                          color: AppVisuals.danger(colorScheme),
                                        ),
                                        onPressed: () => _eliminar(lista),
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
            ),
    );
  }
}
