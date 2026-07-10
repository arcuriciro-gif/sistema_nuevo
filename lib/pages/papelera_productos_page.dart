import 'package:flutter/material.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/producto.dart';
import '../services/producto_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';

class PapeleraProductosPage extends StatefulWidget {
  const PapeleraProductosPage({super.key});

  @override
  State<PapeleraProductosPage> createState() => _PapeleraProductosPageState();
}

class _PapeleraProductosPageState extends State<PapeleraProductosPage> {
  final _service = ProductoService();
  List<Producto> _items = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    DataRefreshHub.instance.addListener(_onRefresh);
    _cargar();
  }

  void _onRefresh() {
    if (mounted) _cargar();
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onRefresh);
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final items = await _service.obtenerEliminados();
    if (!mounted) return;
    setState(() {
      _items = items;
      _cargando = false;
    });
  }

  String _fmtFecha(String? raw) {
    final f = DateTime.tryParse(raw ?? '');
    if (f == null) return raw ?? '';
    return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
  }

  Future<void> _restaurar(Producto p) async {
    if (p.id == null) return;
    await _service.restaurar(p.id!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restaurado: ${p.descripcion}')),
    );
    await _cargar();
  }

  Future<void> _eliminarDefinitivo(Producto p) async {
    if (p.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar definitivamente'),
        content: Text(
          '¿Borrar "${p.descripcion}" de forma permanente? No se podrá recuperar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.eliminarDefinitivo(p.id!);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Papelera de productos',
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
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 64, color: cs.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        'La papelera está vacía',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final p = _items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(p.descripcion),
                        subtitle: Text(
                          'Cód: ${p.codigo} · Borrado: ${_fmtFecha(p.deletedAt)}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Restaurar',
                              icon: const Icon(Icons.restore_from_trash_rounded),
                              color: AppVisuals.success(cs),
                              onPressed: () => _restaurar(p),
                            ),
                            IconButton(
                              tooltip: 'Eliminar definitivo',
                              icon: const Icon(Icons.delete_forever_rounded),
                              color: AppVisuals.danger(cs),
                              onPressed: () => _eliminarDefinitivo(p),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
