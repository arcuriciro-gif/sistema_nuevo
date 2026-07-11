import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pedido_item.dart';
import '../models/proveedor.dart';
import '../services/pedido_service.dart';
import '../services/pedido_sugerido_service.dart';
import '../theme/module_app_bar.dart';
import 'pedido_form_page.dart';
import 'pedidos_page.dart';

class PedidoSugeridoPage extends StatefulWidget {
  const PedidoSugeridoPage({super.key});

  @override
  State<PedidoSugeridoPage> createState() => _PedidoSugeridoPageState();
}

class _PedidoSugeridoPageState extends State<PedidoSugeridoPage> {
  final _svc = PedidoSugeridoService();
  final _pedidoSvc = PedidoService();

  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();

  String? _proveedor;
  String? _categoria;
  String? _marca;
  String? _modelo;
  String? _color;
  String? _talle;

  List<String> _proveedores = [];
  List<String> _categorias = [];
  List<String> _marcas = [];
  List<String> _modelos = [];
  List<String> _colores = [];
  List<String> _talles = [];

  List<SugerenciaPedido> _sugerencias = [];
  final Set<int> _seleccionados = {};
  final Map<int, TextEditingController> _qtyCtrls = {};

  bool _cargandoFiltros = true;
  bool _analizando = false;
  bool _enviando = false;
  bool _soloConSugerencia = true;

  @override
  void initState() {
    super.initState();
    _cargarFiltros();
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarFiltros() async {
    final proveedores = await _svc.valoresDistintos('proveedor');
    final categorias = await _svc.valoresDistintos('categoria');
    final marcas = await _svc.valoresDistintos('marca');
    final modelos = await _svc.valoresDistintos('modelo');
    final colores = await _svc.valoresDistintos('color_producto');
    final talles = await _svc.valoresDistintos('talle');
    if (!mounted) return;
    setState(() {
      _proveedores = proveedores;
      _categorias = categorias;
      _marcas = marcas;
      _modelos = modelos;
      _colores = colores;
      _talles = talles;
      _cargandoFiltros = false;
    });
  }

  TextEditingController _ctrlPara(SugerenciaPedido s) {
    return _qtyCtrls.putIfAbsent(
      s.productoId,
      () => TextEditingController(text: '${s.cantidadSugerida}'),
    );
  }

  Future<void> _pickFecha({required bool esDesde}) async {
    final inicial = esDesde ? _desde : _hasta;
    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (esDesde) {
        _desde = picked;
        if (_desde.isAfter(_hasta)) _hasta = _desde;
      } else {
        _hasta = picked;
        if (_hasta.isBefore(_desde)) _desde = _hasta;
      }
    });
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';

  Future<void> _analizar() async {
    setState(() {
      _analizando = true;
      _seleccionados.clear();
    });
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    _qtyCtrls.clear();

    try {
      final lista = await _svc.analizar(
        desde: _desde,
        hasta: _hasta,
        proveedor: _proveedor,
        categoria: _categoria,
        marca: _marca,
        modelo: _modelo,
        color: _color,
        talle: _talle,
        soloConSugerencia: _soloConSugerencia,
      );
      if (!mounted) return;
      setState(() {
        _sugerencias = lista;
        for (final s in lista) {
          if (s.cantidadSugerida > 0) {
            _seleccionados.add(s.productoId);
          }
          _ctrlPara(s);
        }
      });
    } finally {
      if (mounted) setState(() => _analizando = false);
    }
  }

  int _qtyDe(SugerenciaPedido s) {
    final raw = _qtyCtrls[s.productoId]?.text.trim() ?? '';
    return int.tryParse(raw) ?? s.cantidadSugerida;
  }

  Future<void> _enviarAPedidos() async {
    final elegidos = _sugerencias
        .where((s) => _seleccionados.contains(s.productoId))
        .where((s) => _qtyDe(s) > 0)
        .toList();
    if (elegidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná al menos un artículo')),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      final porProveedor = <String, List<SugerenciaPedido>>{};
      for (final s in elegidos) {
        final key = s.proveedor.trim().isEmpty ? 'Varios' : s.proveedor.trim();
        porProveedor.putIfAbsent(key, () => []).add(s);
      }

      final ids = <int>[];
      for (final entry in porProveedor.entries) {
        final items = entry.value
            .map(
              (s) => PedidoItem(
                pedidoId: 0,
                productoId: s.productoId,
                articulo: s.articulo,
                cantidad: _qtyDe(s),
                color: s.color,
                observaciones:
                    'Sugerido · vendido ${s.cantidadVendida} · stock ${s.stockActual}',
              ),
            )
            .toList();
        final id = await _pedidoSvc.agregarSugeridosAProveedor(
          proveedorNombre: entry.key,
          nuevos: items,
        );
        ids.add(id);
      }

      if (!mounted) return;
      final msg = ids.length == 1
          ? 'Pedido actualizado'
          : '${ids.length} pedidos actualizados por proveedor';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      final ir = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Listo'),
          content: Text(
            '$msg.\n¿Querés abrir la planilla de pedidos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'no'),
              child: const Text('Quedarme'),
            ),
            if (ids.length == 1)
              TextButton(
                onPressed: () => Navigator.pop(context, 'form'),
                child: const Text('Abrir pedido'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'lista'),
              child: const Text('Ver pedidos'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (ir == 'lista') {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PedidosPage()),
        );
      } else if (ir == 'form' && ids.isNotEmpty) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PedidoFormPage(pedidoId: ids.first),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirComoPedidoUnico() async {
    final elegidos = _sugerencias
        .where((s) => _seleccionados.contains(s.productoId))
        .where((s) => _qtyDe(s) > 0)
        .toList();
    if (elegidos.isEmpty) return;

    final proveedorNombre = _proveedor?.trim().isNotEmpty == true
        ? _proveedor!.trim()
        : (elegidos.first.proveedor.trim().isEmpty
            ? 'Varios'
            : elegidos.first.proveedor.trim());

    final items = elegidos
        .map(
          (s) => PedidoItem(
            pedidoId: 0,
            productoId: s.productoId,
            articulo: s.articulo,
            cantidad: _qtyDe(s),
            color: s.color,
            observaciones:
                'Sugerido · vendido ${s.cantidadVendida} · stock ${s.stockActual}',
          ),
        )
        .toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PedidoFormPage(
          proveedorInicial: Proveedor(
            nombre: proveedorNombre,
            telefono: '',
            email: '',
            observaciones: '',
          ),
          lineasIniciales: items,
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value ?? '',
          isExpanded: true,
          items: [
            const DropdownMenuItem<String>(
              value: '',
              child: Text('Todos'),
            ),
            ...options.map(
              (o) => DropdownMenuItem<String>(value: o, child: Text(o)),
            ),
          ],
          onChanged: (v) => onChanged((v == null || v.isEmpty) ? null : v),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final seleccionCount = _seleccionados.length;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Pedido sugerido',
        actions: [
          IconButton(
            tooltip: 'Ver planilla',
            icon: const Icon(Icons.assignment_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PedidosPage()),
              );
            },
          ),
        ],
      ),
      body: _cargandoFiltros
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: cs.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Analiza ventas entre fechas y sugiere qué comprar '
                          '(vendido + stock mínimo − stock actual).',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickFecha(esDesde: true),
                                icon: const Icon(Icons.date_range_rounded),
                                label: Text('Desde ${_fmtFecha(_desde)}'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickFecha(esDesde: false),
                                icon: const Icon(Icons.event_rounded),
                                label: Text('Hasta ${_fmtFecha(_hasta)}'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, c) {
                            final cols = c.maxWidth >= 900
                                ? 3
                                : c.maxWidth >= 560
                                    ? 2
                                    : 1;
                            final items = [
                              _dropdown(
                                label: 'Proveedor',
                                value: _proveedor,
                                options: _proveedores,
                                onChanged: (v) =>
                                    setState(() => _proveedor = v),
                              ),
                              _dropdown(
                                label: 'Categoría',
                                value: _categoria,
                                options: _categorias,
                                onChanged: (v) =>
                                    setState(() => _categoria = v),
                              ),
                              _dropdown(
                                label: 'Marca',
                                value: _marca,
                                options: _marcas,
                                onChanged: (v) => setState(() => _marca = v),
                              ),
                              _dropdown(
                                label: 'Modelo',
                                value: _modelo,
                                options: _modelos,
                                onChanged: (v) => setState(() => _modelo = v),
                              ),
                              _dropdown(
                                label: 'Color',
                                value: _color,
                                options: _colores,
                                onChanged: (v) => setState(() => _color = v),
                              ),
                              _dropdown(
                                label: 'Talle',
                                value: _talle,
                                options: _talles,
                                onChanged: (v) => setState(() => _talle = v),
                              ),
                            ];
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final w in items)
                                  SizedBox(
                                    width: cols == 1
                                        ? c.maxWidth
                                        : (c.maxWidth - 8 * (cols - 1)) / cols,
                                    child: w,
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            'Solo artículos con cantidad sugerida > 0',
                          ),
                          value: _soloConSugerencia,
                          onChanged: (v) =>
                              setState(() => _soloConSugerencia = v),
                        ),
                        FilledButton.icon(
                          onPressed: _analizando ? null : _analizar,
                          icon: _analizando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            _analizando ? 'Analizando…' : 'Analizar ventas',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_sugerencias.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        Text(
                          '${_sugerencias.length} artículos',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _seleccionados
                                ..clear()
                                ..addAll(
                                  _sugerencias.map((s) => s.productoId),
                                );
                            });
                          },
                          child: const Text('Todos'),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _seleccionados.clear()),
                          child: const Text('Ninguno'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _analizando
                      ? const Center(child: CircularProgressIndicator())
                      : _sugerencias.isEmpty
                          ? Center(
                              child: Text(
                                'Elegí fechas y tocá Analizar',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                              itemCount: _sugerencias.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final s = _sugerencias[index];
                                final selected =
                                    _seleccionados.contains(s.productoId);
                                final qtyCtrl = _ctrlPara(s);
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: CheckboxListTile(
                                    value: selected,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _seleccionados.add(s.productoId);
                                        } else {
                                          _seleccionados.remove(s.productoId);
                                        }
                                      });
                                    },
                                    title: Text(
                                      s.articulo,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            [
                                              if (s.codigo.isNotEmpty) s.codigo,
                                              if (s.proveedor.isNotEmpty)
                                                s.proveedor,
                                              if (s.marca.isNotEmpty) s.marca,
                                              if (s.modelo.isNotEmpty) s.modelo,
                                              if (s.color.isNotEmpty) s.color,
                                              if (s.talle.isNotEmpty)
                                                'Talle ${s.talle}',
                                            ].join(' · '),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Vendido: ${s.cantidadVendida}  ·  '
                                            'Stock: ${s.stockActual}'
                                            '${s.stockMinimo > 0 ? ' (mín ${s.stockMinimo})' : ''}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            width: 120,
                                            child: TextField(
                                              controller: qtyCtrl,
                                              enabled: selected,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly,
                                              ],
                                              decoration: const InputDecoration(
                                                labelText: 'Sugerido',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
      bottomNavigationBar: seleccionCount == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _enviando ? null : _abrirComoPedidoUnico,
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Revisar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _enviando ? null : _enviarAPedidos,
                        icon: _enviando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          _enviando
                              ? 'Enviando…'
                              : 'A planilla ($seleccionCount)',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
