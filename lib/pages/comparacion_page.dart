import 'package:flutter/material.dart';
import '../models/comparacion.dart';
import '../models/proveedor.dart';
import '../services/comparador_service.dart';
import '../services/csv_service.dart';
import '../services/proveedor_service.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';

class ComparacionPage extends StatefulWidget {
  const ComparacionPage({super.key});

  @override
  State<ComparacionPage> createState() => _ComparacionPageState();
}

class _ComparacionPageState extends State<ComparacionPage> {
  final CsvService csvService = CsvService();
  final ComparadorService comparadorService = ComparadorService();
  final ProveedorService proveedorService = ProveedorService();
  final TextEditingController _proveedorCtrl = TextEditingController();

  List<Comparacion> lista = [];
  List<Proveedor> _proveedores = [];
  bool cargando = true;
  String filtro = 'TODOS';
  bool _ultimoFuePdf = false;

  int aumentos = 0;
  int bajas = 0;
  int nuevos = 0;
  int iguales = 0;

  @override
  void initState() {
    super.initState();
    cargar();
    _cargarProveedores();
  }

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProveedores() async {
    try {
      await proveedorService.cargarProveedoresIniciales();
      final todos = await proveedorService.obtenerTodos();
      if (!mounted) return;
      setState(() => _proveedores = todos);
    } catch (_) {}
  }

  Future<void> cargar() async {
    setState(() => cargando = true);
    lista = await comparadorService.obtenerComparacion();
    aumentos = await comparadorService.cantidadAumentos();
    bajas = await comparadorService.cantidadBajas();
    nuevos = await comparadorService.cantidadNuevos();
    iguales = await comparadorService.cantidadIguales();
    if (!mounted) return;
    setState(() => cargando = false);
  }

  Future<bool> _pedirProveedor() async {
    final nombres = _proveedores
        .map((p) => p.nombre.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Proveedor de la lista'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Elegí el proveedor para buscar en tu stock. '
                  'Sirve Excel/CSV o PDF de presupuesto/remito (ej. Cuero Sur).',
                ),
                const SizedBox(height: 12),
                if (nombres.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: nombres.contains(_proveedorCtrl.text.trim())
                        ? _proveedorCtrl.text.trim()
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Proveedor cargado',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final n in nombres)
                        DropdownMenuItem(value: n, child: Text(n)),
                    ],
                    onChanged: (v) {
                      if (v != null) _proveedorCtrl.text = v;
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('O escribí otro nombre:'),
                  const SizedBox(height: 6),
                ],
                TextField(
                  controller: _proveedorCtrl,
                  autofocus: nombres.isEmpty,
                  decoration: const InputDecoration(
                    hintText: 'Ej: Cuero Sur, Febo, Leal...',
                    labelText: 'Proveedor',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Elegir archivo'),
            ),
          ],
        );
      },
    );
    return ok == true && _proveedorCtrl.text.trim().isNotEmpty;
  }

  Future<void> analizarNuevaLista() async {
    final listo = await _pedirProveedor();
    if (!listo || !mounted) return;

    setState(() => cargando = true);
    final meta = await csvService.analizarArchivoConProveedor(
      _proveedorCtrl.text.trim(),
    );
    if (!mounted) return;
    _ultimoFuePdf = meta.desdePdf;
    await cargar();
    if (!mounted) return;
    if (meta.leidas == 0 && meta.validas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se leyó el archivo (cancelado, vacío o PDF sin ítems).',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          meta.desdePdf
              ? 'PDF: ${meta.validas} productos leídos · Informe: ${meta.informe}. '
                  'Revisá SUBIÓ/BAJÓ. Nada se actualiza sin tu confirmación.'
              : 'Archivo: ${meta.leidas} filas leídas, ${meta.validas} válidas. '
                  'Informe: ${meta.informe} líneas. '
                  'Los NUEVO no se crean solos.',
        ),
      ),
    );
  }

  Color colorEstado(String estado) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (estado) {
      case 'SUBIO':
        return AppVisuals.danger(colorScheme);
      case 'BAJO':
        return AppVisuals.success(colorScheme);
      case 'NUEVO':
        return AppVisuals.info(colorScheme);
      case 'IGUAL':
        return AppVisuals.neutral(colorScheme);
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  IconData iconoEstado(String estado) {
    switch (estado) {
      case 'SUBIO':
        return Icons.trending_up_rounded;
      case 'BAJO':
        return Icons.trending_down_rounded;
      case 'NUEVO':
        return Icons.new_releases_rounded;
      case 'IGUAL':
        return Icons.horizontal_rule_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _etiquetaFiltro(String estado) {
    switch (estado) {
      case 'SUBIO':
        return 'SUBIÓ';
      case 'BAJO':
        return 'BAJÓ';
      case 'NUEVO':
        return 'NUEVO';
      case 'IGUAL':
        return 'IGUAL';
      case 'TODOS':
        return 'TODOS';
      default:
        return estado;
    }
  }

  List<Comparacion> get listaFiltrada {
    if (filtro == 'TODOS') return lista;
    return lista.where((e) => e.estado == filtro).toList();
  }

  int _countFor(String estado) {
    switch (estado) {
      case 'TODOS':
        return lista.length;
      case 'SUBIO':
        return aumentos;
      case 'BAJO':
        return bajas;
      case 'NUEVO':
        return nuevos;
      case 'IGUAL':
        return iguales;
      default:
        return 0;
    }
  }

  Future<void> exportarInforme() async {
    if (lista.isEmpty) return;
    final filas = listaFiltrada.map((e) {
      final pct = e.precioViejo > 0
          ? ((e.precioNuevo - e.precioViejo) / e.precioViejo) * 100
          : 0.0;
      return [
        e.codigo,
        e.descripcion,
        e.marca,
        e.proveedor,
        e.estado,
        e.precioViejo.toStringAsFixed(2),
        e.precioNuevo.toStringAsFixed(2),
        pct.toStringAsFixed(1),
      ];
    }).toList();

    final archivo = await csvService.exportarCsv(
      'informe_comparacion_${DateTime.now().millisecondsSinceEpoch}.csv',
      [
        'TuCodigo',
        'Descripcion',
        'Marca',
        'Proveedor',
        'Estado',
        'CostoAnterior',
        'CostoNuevo',
        'VariacionPct',
      ],
      filas,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Informe guardado: ${archivo.path}')),
    );
  }

  Future<void> actualizarCostos() async {
    final aActualizar = lista
        .where((e) => e.estado != 'IGUAL' && e.estado != 'NUEVO')
        .length;

    // Hermanos de talle (mismo modelo+color) solo si vino de PDF y hay candidatos.
    List<Comparacion> hermanos = const [];
    if (_ultimoFuePdf && aActualizar > 0) {
      hermanos = await comparadorService.sugerirHermanosTalle();
    }

    if (!mounted) return;
    var incluirHermanos = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Actualizar costos'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aActualizar == 0
                          ? 'No hay costos para actualizar (solo iguales o nuevos sin alta).'
                          : '¿Actualizar el costo de $aActualizar productos del informe?\n\n'
                              'Solo se modifica el COSTO.\n'
                              'Tus códigos NO se cambian.\n'
                              'Nada se aplica sin tu OK.',
                    ),
                    if (hermanos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: incluirHermanos,
                        onChanged: (v) =>
                            setLocal(() => incluirHermanos = v ?? false),
                        title: Text(
                          'También actualizar ${hermanos.length} talles hermanos '
                          'que no vinieron en el PDF',
                        ),
                        subtitle: Text(
                          hermanos
                              .take(8)
                              .map((h) => '· ${h.descripcion.split('  ←  ').first}')
                              .join('\n'),
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                if (aActualizar > 0)
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Confirmar'),
                  ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    setState(() => cargando = true);
    if (incluirHermanos && hermanos.isNotEmpty) {
      await comparadorService.agregarComparaciones(hermanos);
    }
    await comparadorService.actualizarProductos();
    // Dejamos los NUEVO en el informe por si querés crearlos después;
    // limpiamos el resto.
    final quedanNuevos = lista.where((e) => e.estado == 'NUEVO').toList();
    await comparadorService.limpiarComparaciones();
    for (final n in quedanNuevos) {
      await comparadorService.guardarComparacion(n);
    }
    if (quedanNuevos.isEmpty) {
      _proveedorCtrl.clear();
      _ultimoFuePdf = false;
    }
    if (!mounted) return;
    await cargar();
    if (!mounted) return;
    final extra = incluirHermanos && hermanos.isNotEmpty
        ? ' (+${hermanos.length} hermanos)'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          quedanNuevos.isEmpty
              ? 'Costos actualizados correctamente$extra.'
              : 'Costos actualizados$extra. Quedan ${quedanNuevos.length} NUEVO '
                  'para crear o ignorar.',
        ),
      ),
    );
  }

  Future<void> _ignorarNuevo(Comparacion item) async {
    await comparadorService.eliminarComparacionPorCodigo(item.codigo);
    if (!mounted) return;
    await cargar();
  }

  Future<void> _crearNuevo(Comparacion item) async {
    final sugerido = await comparadorService.sugerirCodigoNuevo();
    if (!mounted) return;

    final codigoCtrl = TextEditingController(text: sugerido);
    final descCtrl = TextEditingController(text: item.descripcion.trim());
    final colorCtrl = TextEditingController();
    final talleCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Crear en mi lista'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Solo crealo si lo vas a vender. Si no te interesa, cancelá e ignorá.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codigoCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Tu código',
                    helperText: 'Sugerido: $sugerido (podés cambiarlo)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / artículo',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: colorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Color (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: talleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Talle (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Costo: \$${item.precioNuevo.toStringAsFixed(2)}'
                  '${item.proveedor.isNotEmpty ? ' · ${item.proveedor}' : ''}',
                  style: Theme.of(ctx).textTheme.labelLarge,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );

    final codigo = codigoCtrl.text;
    final desc = descCtrl.text;
    final color = colorCtrl.text;
    final talle = talleCtrl.text;
    codigoCtrl.dispose();
    descCtrl.dispose();
    colorCtrl.dispose();
    talleCtrl.dispose();

    if (confirmar != true || !mounted) return;

    final error = await comparadorService.crearProductoDesdeNuevo(
      comp: item,
      codigo: codigo,
      descripcion: desc,
      color: color,
      talle: talle,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Creado: $codigo')),
    );
  }

  /// Chip de conteo = filtro: un solo control para ver la lista.
  Widget _filtroChip({
    required String estado,
    required String label,
    required int count,
    required Color color,
  }) {
    final selected = filtro == estado;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        showCheckmark: false,
        avatar: CircleAvatar(
          backgroundColor: selected ? color : color.withValues(alpha: .85),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        label: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? color : null,
          ),
        ),
        selectedColor: color.withValues(alpha: .18),
        side: BorderSide(
          color: selected ? color : color.withValues(alpha: .35),
        ),
        onSelected: (_) => setState(() => filtro = estado),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Comparador de Costos',
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Cargar Excel/CSV/PDF del proveedor',
            onPressed: analizarNuevaLista,
          ),
          if (lista.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Exportar informe CSV',
              onPressed: exportarInforme,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: cargar,
          ),
        ],
      ),
      floatingActionButton: lista.any(
            (e) => e.estado == 'SUBIO' || e.estado == 'BAJO',
          )
          ? FloatingActionButton.extended(
              heroTag: 'fab_comparacion',
              onPressed: actualizarCostos,
              icon: const Icon(Icons.save_rounded),
              label: const Text('ACTUALIZAR COSTOS'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              'Excel/CSV o PDF de presupuesto/remito. '
              'Elegí el proveedor, revisá el informe y confirmá antes de actualizar. '
              'Los NUEVO no se crean solos.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .65),
                height: 1.35,
              ),
            ),
          ),
          if (lista.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_rounded, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      lista.first.proveedor.isNotEmpty
                          ? 'Lista: ${lista.first.proveedor}'
                          : 'Lista cargada',
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    filtro == 'TODOS'
                        ? '${lista.length} líneas'
                        : '${listaFiltrada.length} · ${_etiquetaFiltro(filtro)}',
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          if (!cargando && lista.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _filtroChip(
                    estado: 'TODOS',
                    label: 'TODOS',
                    count: _countFor('TODOS'),
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  _filtroChip(
                    estado: 'SUBIO',
                    label: 'SUBIÓ',
                    count: aumentos,
                    color: colorEstado('SUBIO'),
                  ),
                  _filtroChip(
                    estado: 'BAJO',
                    label: 'BAJÓ',
                    count: bajas,
                    color: colorEstado('BAJO'),
                  ),
                  _filtroChip(
                    estado: 'NUEVO',
                    label: 'NUEVO',
                    count: nuevos,
                    color: colorEstado('NUEVO'),
                  ),
                  _filtroChip(
                    estado: 'IGUAL',
                    label: 'IGUAL',
                    count: iguales,
                    color: colorEstado('IGUAL'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : listaFiltrada.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.compare_arrows_rounded,
                              size: 64,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              lista.isEmpty
                                  ? 'Cargá Excel, CSV o PDF del proveedor\n'
                                      '(ej. presupuesto/remito de Cuero Sur)'
                                  : 'No hay ítems con el filtro ${_etiquetaFiltro(filtro)}.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .5),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (lista.isEmpty) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: analizarNuevaLista,
                                icon: const Icon(Icons.upload_file_rounded),
                                label: const Text('Cargar Excel/CSV/PDF'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: listaFiltrada.length,
                        itemBuilder: (context, index) {
                          final item = listaFiltrada[index];
                          final pct = item.precioViejo > 0
                              ? ((item.precioNuevo - item.precioViejo) /
                                      item.precioViejo) *
                                  100
                              : 0.0;
                          final esNuevo = item.estado == 'NUEVO';
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: colorEstado(item.estado)
                                          .withValues(alpha: .15),
                                      child: Icon(
                                        iconoEstado(item.estado),
                                        color: colorEstado(item.estado),
                                      ),
                                    ),
                                    title: Text(
                                      item.descripcion,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 110,
                                              child: Text(
                                                esNuevo
                                                    ? 'Ref. proveedor'
                                                    : 'Tu código',
                                                style: theme
                                                    .textTheme.labelSmall,
                                              ),
                                            ),
                                            Expanded(child: Text(item.codigo)),
                                          ],
                                        ),
                                        if (item.marca.isNotEmpty)
                                          Row(
                                            children: [
                                              SizedBox(
                                                width: 110,
                                                child: Text(
                                                  'Marca',
                                                  style: theme
                                                      .textTheme.labelSmall,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(item.marca),
                                              ),
                                            ],
                                          ),
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 110,
                                              child: Text(
                                                'Costo anterior',
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                item.precioViejo == 0
                                                    ? '—'
                                                    : '\$${item.precioViejo.toStringAsFixed(2)}',
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 110,
                                              child: Text(
                                                'Costo nuevo',
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                '\$${item.precioNuevo.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      colorEstado(item.estado),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: esNuevo
                                        ? null
                                        : item.precioViejo == 0
                                            ? null
                                            : Text(
                                                '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                                                style: TextStyle(
                                                  color: colorEstado(
                                                    item.estado,
                                                  ),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                  ),
                                  if (esNuevo)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        4,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _ignorarNuevo(item),
                                              child: const Text('Ignorar'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: () =>
                                                  _crearNuevo(item),
                                              icon: const Icon(
                                                Icons.add_rounded,
                                                size: 18,
                                              ),
                                              label: const Text(
                                                'Crear en mi lista',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
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
