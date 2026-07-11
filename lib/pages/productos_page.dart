import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/events/data_refresh_hub.dart';
import '../models/chat_mensaje.dart';
import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../services/lista_precio_service.dart';
import '../services/producto_service.dart';
import '../theme/app_visuals.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import 'papelera_productos_page.dart';
import 'producto_form_page.dart';
import 'scanner_page.dart';
import '../theme/module_app_bar.dart';

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

  int get _totalProductos => productos.length;
  int get _stockTotal => productos.fold(0, (s, p) => s + p.stock);
  double get _valorStock => productos.fold(0, (s, p) => s + p.precio * p.stock);
  double get _valorStockCosto =>
      productos.fold(0, (s, p) => s + p.costo * p.stock);
  int get _sinStock => productos.where((p) => p.stock == 0).length;

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
    _marcas = productos.map((p) => p.marca).where((m) => m.isNotEmpty).toSet().toList()
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

    // Favoritos primero
    filtrados.sort((a, b) {
      if (a.favorito == b.favorito) {
        return a.descripcion.compareTo(b.descripcion);
      }
      return a.favorito ? -1 : 1;
    });

    if (mounted) setState(() {});
  }

  void _mostrarSoloSinStock() {
    setState(() {
      _soloSinStock = true;
      _soloStockBajo = false;
      _soloFavoritos = false;
    });
    _aplicarFiltros();
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_productos',
        onPressed: _nuevoProducto,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo'),
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 500;
                      final cards = [
                        _KpiCard(
                          title: 'Productos',
                          value: '$_totalProductos',
                          icon: Icons.inventory_2_rounded,
                          color: const Color(0xFF8B5CF6),
                        ),
                        _KpiCard(
                          title: 'Stock total',
                          value: '$_stockTotal',
                          icon: Icons.layers_rounded,
                          color: const Color(0xFF22C55E),
                        ),
                        _KpiCard(
                          title: 'Stock a venta',
                          value: '\$${_fmtNum(_valorStock)}',
                          icon: Icons.attach_money_rounded,
                          color: const Color(0xFF3B82F6),
                        ),
                        _KpiCard(
                          title: 'Stock a costo',
                          value: '\$${_fmtNum(_valorStockCosto)}',
                          icon: Icons.price_change_rounded,
                          color: const Color(0xFF0EA5E9),
                        ),
                        _KpiCard(
                          title: 'Sin stock',
                          value: '$_sinStock',
                          icon: Icons.warning_amber_rounded,
                          color: dangerColor,
                          selected: _soloSinStock,
                          onTap: () {
                            if (_soloSinStock) {
                              setState(() => _soloSinStock = false);
                              _aplicarFiltros();
                            } else {
                              _mostrarSoloSinStock();
                            }
                          },
                        ),
                      ];
                      return narrow
                          ? GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 2.5,
                              children: cards,
                            )
                          : GridView.count(
                              crossAxisCount: constraints.maxWidth >= 1100
                                  ? 5
                                  : 3,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 2.8,
                              children: cards,
                            );
                    },
                  ),
                ),
                if (_soloSinStock || _soloStockBajo)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Material(
                      color: dangerColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: dangerColor,
                        ),
                        title: Text(
                          _soloSinStock
                              ? 'Mostrando $_sinStock producto(s) sin stock'
                              : 'Mostrando productos con stock bajo',
                          style: TextStyle(
                            color: dangerColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: _limpiarFiltros,
                          child: const Text('Ver todos'),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: buscarController,
                          onChanged: (v) {
                            _filtroBusqueda = v;
                            _aplicarFiltros();
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: 'Código, barras, nombre, marca...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            isDense: true,
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
                      if (_marcas.isNotEmpty) ...[
                        const SizedBox(width: 8),
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
                      ],
                      if (_proveedores.isNotEmpty) ...[
                        const SizedBox(width: 8),
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
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '${filtrados.length} producto${filtrados.length != 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: filtrados.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: colorScheme.outlineVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Sin resultados',
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 80),
                          itemCount: filtrados.length,
                          itemBuilder: (context, index) {
                            final p = filtrados[index];
                            final stockColor = _stockColor(p.stock);
                            return _ProductoCard(
                              producto: p,
                              stockColor: stockColor,
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
                      trailing: selected == item ? const Icon(Icons.check_rounded) : null,
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

  String _fmtNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: selected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: color, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                color: active ? cs.primary : cs.onSurfaceVariant,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    final p = producto;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.descripcion,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cód: ${p.codigo}  •  ${p.marca}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: p.favorito ? 'Quitar favorito' : 'Marcar favorito',
                  icon: Icon(
                    p.favorito ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: p.favorito
                        ? const Color(0xFFFFB020)
                        : colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onToggleFavorito,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Stock: ${p.stock}',
                    style: TextStyle(
                      color: stockColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _PriceBadge(label: 'L1', value: p.precio, cs: colorScheme),
                if (p.precio2 > 0)
                  _PriceBadge(label: 'L2', value: p.precio2, cs: colorScheme),
                if (p.precio3 > 0)
                  _PriceBadge(label: 'L3', value: p.precio3, cs: colorScheme),
                for (final lista in listasActivas)
                  _PriceBadge(
                    label: lista.nombre,
                    value: lista.calcularPrecio(p.costo),
                    cs: colorScheme,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onComment,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Notas'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.tertiary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Compartir'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.secondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Editar'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text('Papelera'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppVisuals.danger(colorScheme),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ],
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
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
      ),
    );
  }
}
