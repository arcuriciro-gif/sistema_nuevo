import 'dart:async';

import 'package:flutter/material.dart';

import '../core/utils/busqueda_texto.dart';
import '../database/database_helper.dart';
import '../models/producto.dart';
import '../theme/module_app_bar.dart';
import 'kardex_page.dart';

class BusquedaGlobalPage extends StatefulWidget {
  final String? consultaInicial;

  const BusquedaGlobalPage({super.key, this.consultaInicial});

  @override
  State<BusquedaGlobalPage> createState() => _BusquedaGlobalPageState();
}

class _BusquedaGlobalPageState extends State<BusquedaGlobalPage> {
  final TextEditingController _controller = TextEditingController();
  final Map<String, List<Map<String, dynamic>>> _resultados = {
    'Productos': [],
    'Clientes': [],
    'Proveedores': [],
    'Remitos': [],
    'Compras': [],
  };

  Timer? _debounce;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    final inicial = widget.consultaInicial?.trim() ?? '';
    if (inicial.isNotEmpty) {
      _controller.text = inicial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscar(inicial));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    final query = texto.trim();
    if (query.isEmpty) {
      for (final key in _resultados.keys) {
        _resultados[key] = [];
      }
      if (mounted) setState(() => _cargando = false);
      return;
    }

    setState(() => _cargando = true);
    final db = await DatabaseHelper.instance.database;
    final tokens = BusquedaTexto.tokens(query);

    // Productos: traer candidatos amplios y filtrar por tokens (papi ⊆ papifutbol).
    final productosRaw = await db.rawQuery(
      '''
      SELECT * FROM productos
      WHERE (deleted_at IS NULL OR deleted_at = '')
      ORDER BY favorito DESC, descripcion
      LIMIT 800
      ''',
    );
    final productos = productosRaw
        .where(
          (row) => BusquedaTexto.coincideMapa(query, row, [
            'descripcion',
            'codigo',
            'codigo_barras',
            'marca',
            'categoria',
            'modelo',
            'color_producto',
            'talle',
            'proveedor',
          ]),
        )
        .take(15)
        .toList();

    String likeClause(String col) {
      if (tokens.isEmpty) return '1=1';
      return tokens.map((_) => '$col LIKE ?').join(' AND ');
    }

    List<String> likeArgs() => tokens.map((t) => '%$t%').toList();

    final clientes = await db.rawQuery(
      '''
      SELECT * FROM clientes
      WHERE (${likeClause('nombre')} OR ${likeClause('apellido')} OR ${likeClause('cuit')})
      ORDER BY nombre
      LIMIT 10
      ''',
      [...likeArgs(), ...likeArgs(), ...likeArgs()],
    );
    final proveedores = await db.rawQuery(
      '''
      SELECT * FROM proveedores
      WHERE ${likeClause('nombre')}
      ORDER BY nombre
      LIMIT 10
      ''',
      likeArgs(),
    );
    final remitos = await db.rawQuery(
      '''
      SELECT r.*, c.nombre AS clienteNombre
      FROM remitos r
      LEFT JOIN clientes c ON c.id = r.clienteId
      WHERE ${likeClause('r.numero')} OR ${likeClause('c.nombre')}
      ORDER BY datetime(r.fecha) DESC
      LIMIT 10
      ''',
      [...likeArgs(), ...likeArgs()],
    );
    final compras = await db.rawQuery(
      '''
      SELECT * FROM compras
      WHERE ${likeClause('numero')}
      ORDER BY datetime(fecha) DESC
      LIMIT 10
      ''',
      likeArgs(),
    );

    if (!mounted) return;
    setState(() {
      _resultados['Productos'] = productos;
      _resultados['Clientes'] = clientes;
      _resultados['Proveedores'] = proveedores;
      _resultados['Remitos'] = remitos;
      _resultados['Compras'] = compras;
      _cargando = false;
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _buscar(value));
  }

  Future<void> _abrirResultado(String categoria, Map<String, dynamic> item) async {
    if (categoria == 'Productos') {
      final producto = Producto.fromMap(item);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => KardexPage(producto: producto)),
      );
      return;
    }

    final titulo = switch (categoria) {
      'Clientes' => (item['apellido'] ?? '').toString().isEmpty
          ? (item['nombre'] ?? 'Cliente').toString()
          : '${item['nombre']} ${item['apellido']}',
      'Proveedores' => (item['nombre'] ?? 'Proveedor').toString(),
      'Remitos' => 'Remito ${item['numero'] ?? ''}',
      'Compras' => 'Compra ${item['numero'] ?? ''}',
      _ => categoria,
    };

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: item.entries
                .where((entry) => entry.value != null && entry.value.toString().isNotEmpty)
                .map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${entry.key}: ${entry.value}'),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Búsqueda global'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar productos, clientes, proveedores, remitos o compras...',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: _resultados.entries.map((entry) {
                      final items = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (items.isEmpty)
                                const Text('Sin resultados')
                              else
                                ...items.map(
                                  (item) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      switch (entry.key) {
                                        'Productos' => item['descripcion']?.toString() ?? '',
                                        'Clientes' => item['nombreCompleto']?.toString() ??
                                            '${item['nombre'] ?? ''} ${item['apellido'] ?? ''}'.trim(),
                                        'Proveedores' => item['nombre']?.toString() ?? '',
                                        _ => item['numero']?.toString() ?? '',
                                      },
                                    ),
                                    subtitle: Text(
                                      switch (entry.key) {
                                        'Productos' =>
                                          'Código: ${item['codigo'] ?? ''} • Marca: ${item['marca'] ?? ''}',
                                        'Clientes' =>
                                          'CUIT: ${item['cuit'] ?? '-'} • Tel: ${item['telefono'] ?? '-'}',
                                        'Proveedores' =>
                                          'Tel: ${item['telefono'] ?? '-'} • Email: ${item['email'] ?? '-'}',
                                        'Remitos' =>
                                          'Cliente: ${item['clienteNombre'] ?? 'Sin cliente'} • Total: \$${((item['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                        _ =>
                                          'Proveedor: ${item['proveedorNombre'] ?? 'Sin proveedor'} • Total: \$${((item['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                                      },
                                    ),
                                    trailing: const Icon(Icons.open_in_new_rounded),
                                    onTap: () => _abrirResultado(entry.key, item),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
