import 'package:flutter/material.dart';
import '../models/comparacion.dart';
import '../services/comparador_service.dart';
import '../services/csv_service.dart';
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
  final TextEditingController _proveedorCtrl = TextEditingController();

  List<Comparacion> lista = [];
  bool cargando = true;
  String filtro = "TODOS";

  int aumentos = 0;
  int bajas = 0;
  int nuevos = 0;
  int iguales = 0;

  @override
  void initState() {
    super.initState();
    cargar();
  }

  @override
  void dispose() {
    _proveedorCtrl.dispose();
    super.dispose();
  }

  Future<void> cargar() async {
    setState(() {
      cargando = true;
    });
    lista = await comparadorService.obtenerComparacion();
    aumentos = await comparadorService.cantidadAumentos();
    bajas = await comparadorService.cantidadBajas();
    nuevos = await comparadorService.cantidadNuevos();
    iguales = await comparadorService.cantidadIguales();
    if (!mounted) return;
    setState(() {
      cargando = false;
    });
  }

  Future<void> analizarNuevaLista() async {
    // Pedir proveedor si está vacío
    if (_proveedorCtrl.text.trim().isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Nombre del proveedor'),
          content: TextField(
            controller: _proveedorCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Ej: Febo, Bisso, Arola...',
              labelText: 'Proveedor',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
    }

    if (!mounted) return;
    setState(() => cargando = true);
    await csvService.analizarArchivoConProveedor(_proveedorCtrl.text.trim());
    if (!mounted) return;
    await cargar();
  }

  Color colorEstado(String estado) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (estado) {
      case "SUBIO":
        return AppVisuals.danger(colorScheme);
      case "BAJO":
        return AppVisuals.success(colorScheme);
      case "NUEVO":
        return AppVisuals.info(colorScheme);
      case "IGUAL":
        return AppVisuals.neutral(colorScheme);
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  IconData iconoEstado(String estado) {
    switch (estado) {
      case "SUBIO":
        return Icons.trending_up_rounded;
      case "BAJO":
        return Icons.trending_down_rounded;
      case "NUEVO":
        return Icons.new_releases_rounded;
      case "IGUAL":
        return Icons.horizontal_rule_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  List<Comparacion> get listaFiltrada {
    if (filtro == "TODOS") {
      return lista;
    }
    return lista.where((e) => e.estado == filtro).toList();
  }

  Widget botonFiltro(String texto, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(texto),
        selected: filtro == texto,
        selectedColor: color.withValues(alpha: .20),
        onSelected: (_) {
          setState(() {
            filtro = texto;
          });
        },
      ),
    );
  }

  Future<void> actualizarCostos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Actualizar costos'),
        content: Text(
          '¿Actualizar el costo de ${lista.where((e) => e.estado != "IGUAL").length} productos?\n\n'
          'Solo se modificará el COSTO. El precio de venta, stock y demás datos no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (ok != true) {
      return;
    }

    setState(() {
      cargando = true;
    });
    await comparadorService.actualizarProductos();
    await comparadorService.limpiarComparaciones();
    _proveedorCtrl.clear();
    if (!mounted) return;
    setState(() {
      lista = [];
      aumentos = 0;
      bajas = 0;
      nuevos = 0;
      iguales = 0;
      cargando = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Costos actualizados correctamente.")),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
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
            tooltip: 'Cargar lista CSV',
            onPressed: analizarNuevaLista,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: cargar,
          ),
        ],
      ),
      floatingActionButton: lista.isNotEmpty
          ? FloatingActionButton.extended(
        heroTag: 'fab_comparacion',
              onPressed: actualizarCostos,
              icon: const Icon(Icons.save_rounded),
              label: const Text("ACTUALIZAR COSTOS"),
            )
          : null,
      body: Column(
        children: [
          // Header con proveedor actual
          if (lista.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    lista.first.proveedor.isNotEmpty
                        ? 'Lista: ${lista.first.proveedor}'
                        : 'Lista cargada',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    '${lista.length} productos',
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
                  _statChip("SUBIÓ", aumentos, colorEstado("SUBIO")),
                  _statChip("BAJÓ", bajas, colorEstado("BAJO")),
                  _statChip("NUEVO", nuevos, colorEstado("NUEVO")),
                  _statChip("IGUAL", iguales, colorEstado("IGUAL")),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                botonFiltro("TODOS", theme.colorScheme.onSurfaceVariant),
                botonFiltro("SUBIO", colorEstado("SUBIO")),
                botonFiltro("BAJO", colorEstado("BAJO")),
                botonFiltro("NUEVO", colorEstado("NUEVO")),
                botonFiltro("IGUAL", colorEstado("IGUAL")),
              ],
            ),
          ),
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
                              color:
                                  theme.colorScheme.onSurface.withValues(alpha: .3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              lista.isEmpty
                                  ? 'Cargá una lista CSV para comparar costos'
                                  : 'No hay diferencias con el filtro seleccionado.',
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
                                label: const Text('Cargar lista'),
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
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            child: ListTile(
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
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        child: Text('Código',
                                            style: theme.textTheme.labelSmall),
                                      ),
                                      Expanded(child: Text(item.codigo)),
                                    ],
                                  ),
                                  if (item.marca.isNotEmpty)
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 110,
                                          child: Text('Marca',
                                              style: theme.textTheme.labelSmall),
                                        ),
                                        Expanded(child: Text(item.marca)),
                                      ],
                                    ),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 110,
                                        child: Text('Costo anterior',
                                            style: theme.textTheme.labelSmall),
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
                                        child: Text('Costo nuevo',
                                            style: theme.textTheme.labelSmall),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '\$${item.precioNuevo.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: colorEstado(item.estado),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: item.estado == 'NUEVO'
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colorEstado('NUEVO')
                                            .withValues(alpha: .15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'NUEVO',
                                        style: TextStyle(
                                          color: colorEstado('NUEVO'),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  : item.precioViejo == 0
                                      ? null
                                      : Text(
                                          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
                                          style: TextStyle(
                                            color: colorEstado(item.estado),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
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
