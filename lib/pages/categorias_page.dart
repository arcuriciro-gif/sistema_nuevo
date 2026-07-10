import 'package:flutter/material.dart';

import '../models/categoria.dart';
import '../services/categoria_service.dart';
import '../theme/app_visuals.dart';

class CategoriasPage extends StatefulWidget {
  const CategoriasPage({super.key});

  @override
  State<CategoriasPage> createState() => _CategoriasPageState();
}

class _CategoriasPageState extends State<CategoriasPage> {
  final CategoriaService _service = CategoriaService();
  final TextEditingController _buscarCtrl = TextEditingController();

  List<Categoria> _todas = [];
  List<Categoria> _filtradas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    _todas = await _service.obtenerTodas();
    _aplicarFiltro(_buscarCtrl.text);
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  void _aplicarFiltro(String texto) {
    final q = texto.toLowerCase();
    _filtradas = q.isEmpty
        ? List.of(_todas)
        : _todas.where((c) => c.nombre.toLowerCase().contains(q)).toList();
    setState(() {});
  }

  Future<void> _abrirFormulario([Categoria? categoria]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CategoriaDialog(categoria: categoria),
    );
    await _cargar();
  }

  Future<void> _confirmarEliminar(Categoria categoria) async {
    final colorScheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${categoria.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Eliminar',
              style: TextStyle(color: AppVisuals.danger(colorScheme)),
            ),
          ),
        ],
      ),
    );
    if (ok == true && categoria.id != null) {
      await _service.eliminar(categoria.id!);
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _abrirFormulario(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _buscarCtrl,
              decoration: const InputDecoration(
                hintText: 'Buscar categoría...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _aplicarFiltro,
            ),
          ),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filtradas.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No hay categorías. Presioná + para agregar.'),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _filtradas.length,
                itemBuilder: (context, i) {
                  final cat = _filtradas[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          cat.nombre.isNotEmpty
                              ? cat.nombre[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(cat.nombre),
                      subtitle: cat.descripcion.isNotEmpty
                          ? Text(cat.descripcion)
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cat.activa == 0)
                            const Chip(
                              label: Text('Inactiva'),
                              visualDensity: VisualDensity.compact,
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: () => _abrirFormulario(cat),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_rounded),
                            onPressed: () => _confirmarEliminar(cat),
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

// ---------------------------------------------------------------------------
// Dialog para crear / editar
// ---------------------------------------------------------------------------
class _CategoriaDialog extends StatefulWidget {
  final Categoria? categoria;
  const _CategoriaDialog({this.categoria});

  @override
  State<_CategoriaDialog> createState() => _CategoriaDialogState();
}

class _CategoriaDialogState extends State<_CategoriaDialog> {
  final CategoriaService _service = CategoriaService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _descCtrl;
  bool _activa = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl =
        TextEditingController(text: widget.categoria?.nombre ?? '');
    _descCtrl =
        TextEditingController(text: widget.categoria?.descripcion ?? '');
    _activa = (widget.categoria?.activa ?? 1) == 1;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final cat = Categoria(
      id: widget.categoria?.id,
      nombre: _nombreCtrl.text.trim(),
      descripcion: _descCtrl.text.trim(),
      activa: _activa ? 1 : 0,
    );
    if (cat.id == null) {
      await _service.crear(cat);
    } else {
      await _service.actualizar(cat);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.categoria == null;
    return AlertDialog(
      title: Text(isNew ? 'Nueva categoría' : 'Editar categoría'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: _activa,
                onChanged: (v) => setState(() => _activa = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
