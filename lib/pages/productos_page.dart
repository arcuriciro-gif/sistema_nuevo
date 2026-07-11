import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/events/data_refresh_hub.dart';
import '../core/utils/media_path.dart';
import '../models/chat_mensaje.dart';
import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../services/lista_precio_service.dart';
import '../services/producto_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'papelera_productos_page.dart';
import 'producto_form_page.dart';
import 'scanner_page.dart';

class ProductosPage extends StatefulWidget {
  /// Si es true, abre la lista ya filtrada a productos sin stock.
  final bool soloSinStockInicial;

  /// Si es true, abre filtrado a stock bajo / crítico (incluye sin stock).
  final bool soloStockBajoInicial;

  const ProductosPage({
    super.key,
    this.soloSinStockInicial = false,
    this.soloStockBajoInicial = false,
  });

  @override
  State<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends State<ProductosPage> {
  static const int _stockNivelAlto = 10;

  final ProductoService service = ProductoService();
  final ListaPrecioService listaPrecioService = ListaPrecioService();
  final TextEditingController buscarController = TextEditingController();

  List<Producto> productos = [];
  List<Producto> filtrados = [];
  List<ListaPrecio> listasActivas = [];
  bool cargando = true;

  String _filtroBusqueda = '';
  String? _filtroMarca;
  String? _filtroProveedor;
  bool _soloFavoritos = false;
  bool _soloSinStock = false;
  bool _soloStockBajo = false;

  List<String> _marcas = [];
  List<String> _proveedores = [];

  @override
  void initState() {
    super.initState();
    _soloSinStock = widget.soloSinStockInicial;
    _soloStockBajo = widget.soloStockBajoInicial;
    DataRefreshHub.instance.addListener(_onDatosActualizados);
    cargarProductos();
  }

  void _onDatosActualizados() {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) cargarProductos();
    });
  }

  @override
  void dispose() {
    DataRefreshHub.instance.removeListener(_onDatosActualizados);
    buscarController.dispose();
    super.dispose();
  }

  Future<void> cargarProductos() async {
    setState(() => cargando = true);
    productos = await service.obtenerTodos();
    listasActivas = await listaPrecioService.obtenerActivas();
    _marcas = productos
        .map((p) => p.marca)
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _proveedores = productos
        .map((p) => p.proveedor)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    _aplicarFiltros();

    if (!mounted) return;
    setState(() => cargando = false);
  }

  void _aplicarFiltros() {
    final query = _filtroBusqueda.toLowerCase();
    filtrados = productos.where((p) {
      final matchBusqueda = query.isEmpty ||
          p.descripcion.toLowerCase().contains(query) ||
          p.codigo.toLowerCase().contains(query) ||
          p.codigoBarras.toLowerCase().contains(query) ||
          p.marca.toLowerCase().contains(query) ||
          p.categoria.toLowerCase().contains(query) ||
          p.proveedor.toLowerCase().contains(query);

      final matchMarca = _filtroMarca == null || p.marca == _filtroMarca;
      final matchProveedor =
          _filtroProveedor == null || p.proveedor == _filtroProveedor;
      final matchFavorito = !_soloFavoritos || p.favorito;
      final matchSinStock = !_soloSinStock || p.stock == 0;
      final matchStockBajo = !_soloStockBajo ||
          p.stock == 0 ||
          (p.stockMinimo > 0 ? p.stock <= p.stockMinimo : p.stock <= 5);

      return matchBusqueda &&
          matchMarca &&
          matchProveedor &&
          matchFavorito &&
          matchSinStock &&
          matchStockBajo;
    }).toList();

    filtrados.sort((a, b) {
      if (a.favorito == b.favorito) {
        return a.descripcion.compareTo(b.descripcion);
      }
      return a.favorito ? -1 : 1;
    });

    if (mounted) setState(() {});
  }

  void _limpiarFiltros() {
    setState(() {
      _filtroBusqueda = '';
      _filtroMarca = null;
      _filtroProveedor = null;
      _soloFavoritos = false;
      _soloSinStock = false;
      _soloStockBajo = false;
      buscarController.clear();
    });
    _aplicarFiltros();
  }

  Future<void> _escanearCodigo() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (codigo == null || codigo.trim().isEmpty || !mounted) return;
    buscarController.text = codigo;
    setState(() => _filtroBusqueda = codigo);
    _aplicarFiltros();
  }

  Future<void> eliminar(Producto producto) async {
    if (producto.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enviar a papelera'),
        content: Text(
          '¿Mover "${producto.descripcion}" a la papelera? Podés recuperarlo después.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await service.eliminar(producto.id!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto enviado a la papelera')),
      );
    }
    await cargarProductos();
  }

  Future<void> _toggleFavorito(Producto producto) async {
    await service.toggleFavorito(producto);
    await cargarProductos();
  }

  Color _stockColor(int stock) {
    final cs = Theme.of(context).colorScheme;
    if (stock > _stockNivelAlto) return AppVisuals.success(cs);
    if (stock > 0) return AppVisuals.warning(cs);
    return AppVisuals.danger(cs);
  }

  Future<void> _editarProducto(Producto producto) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductoFormPage(producto: producto)),
    );
    await cargarProductos();
  }

  Future<void> _nuevoProducto() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductoFormPage()),
    );
    await cargarProductos();
  }

  void _showFilterSheet({
    required String title,
    required List<String> items,
    required String? selected,
    required ValueChanged<String?> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          ListTile(
            title: const Text('Todos'),
            leading: const Icon(Icons.clear_all_rounded),
            selected: selected == null,
            onTap: () {
              onSelect(null);
              Navigator.pop(context);
            },
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: items
                  .map(
                    (item) => ListTile(
                      title: Text(item),
                      selected: selected == item,
                      trailing: selected == item
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () {
                        onSelect(item);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dangerColor = AppVisuals.danger(colorScheme);

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Productos',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: cargarProductos,
          ),
          IconButton(
            tooltip: _soloFavoritos ? 'Ver todos' : 'Solo favoritos',
            icon: Icon(
              _soloFavoritos ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            onPressed: () {
              setState(() => _soloFavoritos = !_soloFavoritos);
              _aplicarFiltros();
            },
          ),
          IconButton(
            tooltip: 'Papelera',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PapeleraProductosPage()),
              );
              await cargarProductos();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_productos',
        onPressed: _nuevoProducto,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: buscarController,
              onChanged: (v) {
                _filtroBusqueda = v;
                _aplicarFiltros();
              },
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                suffixIcon: (_filtroBusqueda.isNotEmpty ||
                        _filtroMarca != null ||
                        _filtroProveedor != null ||
                        _soloSinStock ||
                        _soloStockBajo)
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Limpiar filtros',
                        onPressed: _limpiarFiltros,
                      )
                    : IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        tooltip: 'Escanear código',
                        onPressed: _escanearCodigo,
                      ),
              ),
            ),
          ),
          if (_marcas.isNotEmpty || _proveedores.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  if (_marcas.isNotEmpty)
                    _FilterChipButton(
                      label: _filtroMarca ?? 'Marca',
                      icon: Icons.label_outline_rounded,
                      active: _filtroMarca != null,
                      onTap: () => _showFilterSheet(
                        title: 'Filtrar por marca',
                        items: _marcas,
                        selected: _filtroMarca,
                        onSelect: (v) {
                          setState(() => _filtroMarca = v);
                          _aplicarFiltros();
                        },
                      ),
                    ),
                  if (_marcas.isNotEmpty && _proveedores.isNotEmpty)
                    const SizedBox(width: 8),
                  if (_proveedores.isNotEmpty)
                    _FilterChipButton(
                      label: _filtroProveedor ?? 'Proveedor',
                      icon: Icons.local_shipping_outlined,
                      active: _filtroProveedor != null,
                      onTap: () => _showFilterSheet(
                        title: 'Filtrar por proveedor',
                        items: _proveedores,
                        selected: _filtroProveedor,
                        onSelect: (v) {
                          setState(() => _filtroProveedor = v);
                          _aplicarFiltros();
                        },
                      ),
                    ),
                ],
              ),
            ),
          if (_soloSinStock || _soloStockBajo)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Material(
                color: dangerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: dangerColor,
                    size: 20,
                  ),
                  title: Text(
                    _soloSinStock
                        ? 'Mostrando productos sin stock'
                        : 'Mostrando productos con stock bajo',
                    style: TextStyle(
                      color: dangerColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _limpiarFiltros,
                    child: const Text('Ver todos'),
                  ),
                ),
              ),
            ),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : filtrados.isEmpty
                    ? const Center(
                        child: Text(
                          'No hay productos.',
                          style: TextStyle(fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: filtrados.length,
                        itemBuilder: (context, index) {
                          final p = filtrados[index];
                          return _ProductoCard(
                            producto: p,
                            stockColor: _stockColor(p.stock),
                            colorScheme: colorScheme,
                            listasActivas: listasActivas,
                            onEdit: () => _editarProducto(p),
                            onDelete: () => eliminar(p),
                            onToggleFavorito: () => _toggleFavorito(p),
                            onShare: () => showCompartirEnChatDialog(
                              context,
                              compartido: ChatCompartido(
                                tipo: 'producto',
                                idRef: '${p.id}',
                                titulo: p.descripcion,
                                subtitulo:
                                    'Cód: ${p.codigo} · Stock ${p.stock} · \$${p.precio.toStringAsFixed(2)}',
                                datos: {
                                  'codigo': p.codigo,
                                  'stock': p.stock,
                                  'precio': p.precio,
                                  'costo': p.costo,
                                  'foto': p.fotoPrincipal,
                                },
                              ),
                            ),
                            onComment: () => showComentariosInternos(
                              context,
                              entidadTipo: 'producto',
                              entidadId: p.codigo.isNotEmpty
                                  ? p.codigo
                                  : '${p.id}',
                              titulo: p.descripcion,
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

class _FilterChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? cs.primary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductoCard extends StatelessWidget {
  final Producto producto;
  final Color stockColor;
  final ColorScheme colorScheme;
  final List<ListaPrecio> listasActivas;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorito;
  final VoidCallback onShare;
  final VoidCallback onComment;

  const _ProductoCard({
    required this.producto,
    required this.stockColor,
    required this.colorScheme,
    required this.listasActivas,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorito,
    required this.onShare,
    required this.onComment,
  });

  List<({String label, double value})> get _preciosSistema {
    final p = producto;
    if (listasActivas.isEmpty) {
      if (p.precio <= 0) return const [];
      return [(label: 'Precio', value: p.precio)];
    }
    final ordenadas = [...listasActivas]
      ..sort((a, b) {
        final byOrden = a.orden.compareTo(b.orden);
        if (byOrden != 0) return byOrden;
        return a.prioridad.compareTo(b.prioridad);
      });
    final out = <({String label, double value})>[];
    for (var i = 0; i < ordenadas.length; i++) {
      final lista = ordenadas[i];
      final id = lista.id?.toString() ?? '';
      double value =
          p.preciosListas[id] ?? p.preciosListas[lista.nombre] ?? 0;
      if (value <= 0) {
        if (i == 0) {
          value = p.precio;
        } else if (i == 1) {
          value = p.precio2;
        } else if (i == 2) {
          value = p.precio3;
        }
      }
      if (value <= 0 && p.costo > 0) {
        value = lista.calcularPrecio(p.costo);
      }
      if (value > 0) {
        out.add((label: lista.nombre, value: value));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final p = producto;
    final foto = imageProviderDesdePath(p.fotoPrincipal);
    final precios = _preciosSistema;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: colorScheme.primaryContainer,
                    backgroundImage: foto,
                    child: foto == null
                        ? Text(
                            p.descripcion.isNotEmpty
                                ? p.descripcion[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.descripcion,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cód: ${p.codigo}'
                          '${p.marca.isNotEmpty ? '  ·  ${p.marca}' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: p.favorito ? 'Quitar favorito' : 'Marcar favorito',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      p.favorito
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: p.favorito
                          ? const Color(0xFFFFB020)
                          : colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onPressed: onToggleFavorito,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Stock: ${p.stock}',
                      style: TextStyle(
                        color: stockColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              if (precios.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: precios
                      .map(
                        (e) => _PriceBadge(
                          label: e.label,
                          value: e.value,
                          cs: colorScheme,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Notas',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: colorScheme.tertiary,
                    ),
                    onPressed: onComment,
                  ),
                  IconButton(
                    tooltip: 'Compartir',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.share_rounded,
                      size: 18,
                      color: colorScheme.secondary,
                    ),
                    onPressed: onShare,
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Papelera',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: AppVisuals.danger(colorScheme),
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  final String label;
  final double value;
  final ColorScheme cs;

  const _PriceBadge({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        '$label: \$${value.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
    );
  }
}
