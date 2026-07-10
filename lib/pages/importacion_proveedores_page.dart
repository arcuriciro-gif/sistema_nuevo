import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/proveedor.dart';
import '../services/importacion_archivo_helper.dart';
import '../services/plantilla_importacion_service.dart';
import '../services/proveedor_service.dart';
import '../theme/module_app_bar.dart';

enum _Col {
  nombre,
  contacto,
  telefono,
  whatsapp,
  email,
  web,
  cuit,
  condiciones,
  tiempoEntrega,
  observaciones,
}

const _colAliases = <_Col, Set<String>>{
  _Col.nombre: {'nombre', 'proveedor', 'name', 'razonsocial'},
  _Col.contacto: {'contacto', 'contact', 'responsable'},
  _Col.telefono: {'telefono', 'tel', 'phone', 'celular'},
  _Col.whatsapp: {'whatsapp', 'wa', 'wsp'},
  _Col.email: {'email', 'mail', 'correo'},
  _Col.web: {'web', 'sitio', 'website', 'url'},
  _Col.cuit: {'cuit', 'cuil'},
  _Col.condiciones: {
    'condicionescomerciales',
    'condiciones',
    'condicion',
    'pago',
  },
  _Col.tiempoEntrega: {'tiempoentrega', 'entrega', 'plazo', 'demora'},
  _Col.observaciones: {'observaciones', 'obs', 'notas', 'comentario'},
};

const _ordenMapeo = [
  _Col.whatsapp,
  _Col.tiempoEntrega,
  _Col.condiciones,
  _Col.contacto,
  _Col.nombre,
  _Col.telefono,
  _Col.email,
  _Col.web,
  _Col.cuit,
  _Col.observaciones,
];

class ImportacionProveedoresPage extends StatefulWidget {
  const ImportacionProveedoresPage({super.key});

  @override
  State<ImportacionProveedoresPage> createState() =>
      _ImportacionProveedoresPageState();
}

enum _Estado { inicio, vista_previa, importando, listo }

class _ImportacionProveedoresPageState
    extends State<ImportacionProveedoresPage> {
  final ProveedorService _svc = ProveedorService();
  final _plantillas = PlantillaImportacionService.instance;

  _Estado _estado = _Estado.inicio;
  List<String> _headers = [];
  List<List<dynamic>> _filas = [];
  Map<_Col, int> _mapeo = {};
  int _importados = 0;
  int _actualizados = 0;
  int _saltados = 0;
  String _mensajeError = '';
  bool _descargando = false;

  Future<void> _descargarPlantilla() async {
    setState(() => _descargando = true);
    try {
      final file = await _plantillas.generarPlantillaProveedores();
      await _plantillas.compartirArchivo(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plantilla guardada en:\n${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la plantilla: $e')),
      );
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  Future<void> _seleccionarArchivo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final data =
          await ImportacionArchivoHelper.leerArchivo(result.files.single.path!);
      if (data.headers.isEmpty) {
        setState(() => _mensajeError = 'El archivo está vacío.');
        return;
      }
      final mapeo = ImportacionArchivoHelper.mapearColumnas<_Col>(
        headers: data.headers,
        aliases: _colAliases,
        ordenPrioridad: _ordenMapeo,
      );
      if (!mounted) return;
      setState(() {
        _headers = data.headers;
        _filas = data.filas;
        _mapeo = mapeo;
        _estado = _Estado.vista_previa;
        _mensajeError = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensajeError = 'Error al leer el archivo: $e');
    }
  }

  Future<void> _importar() async {
    if (_mapeo[_Col.nombre] == null) {
      setState(() => _mensajeError = 'Falta la columna Nombre.');
      return;
    }

    setState(() {
      _estado = _Estado.importando;
      _importados = 0;
      _actualizados = 0;
      _saltados = 0;
    });

    String valorCol(List<dynamic> fila, int? idx) =>
        (idx != null && idx < fila.length) ? fila[idx].toString().trim() : '';

    for (final fila in _filas) {
      final nombre = valorCol(fila, _mapeo[_Col.nombre]);
      if (nombre.isEmpty) {
        _saltados++;
        continue;
      }

      final contacto = valorCol(fila, _mapeo[_Col.contacto]);
      final telefono = valorCol(fila, _mapeo[_Col.telefono]);
      final whatsapp = valorCol(fila, _mapeo[_Col.whatsapp]);
      final email = valorCol(fila, _mapeo[_Col.email]);
      final web = valorCol(fila, _mapeo[_Col.web]);
      final cuit = valorCol(fila, _mapeo[_Col.cuit]);
      final condiciones = valorCol(fila, _mapeo[_Col.condiciones]);
      final tiempo = valorCol(fila, _mapeo[_Col.tiempoEntrega]);
      final observaciones = valorCol(fila, _mapeo[_Col.observaciones]);

      Proveedor? existente = await _svc.buscarPorCuit(cuit);
      existente ??= await _svc.buscarPorNombre(nombre);

      if (existente == null) {
        await _svc.insertar(
          Proveedor(
            nombre: nombre,
            contacto: contacto,
            telefono: telefono,
            whatsapp: whatsapp,
            email: email,
            web: web,
            cuit: cuit,
            condicionesComerciales: condiciones,
            tiempoEntrega: tiempo,
            observaciones: observaciones,
          ),
        );
        _importados++;
      } else {
        await _svc.actualizar(
          existente.copyWith(
            contacto: contacto.isNotEmpty ? contacto : existente.contacto,
            telefono: telefono.isNotEmpty ? telefono : existente.telefono,
            whatsapp: whatsapp.isNotEmpty ? whatsapp : existente.whatsapp,
            email: email.isNotEmpty ? email : existente.email,
            web: web.isNotEmpty ? web : existente.web,
            cuit: cuit.isNotEmpty ? cuit : existente.cuit,
            condicionesComerciales: condiciones.isNotEmpty
                ? condiciones
                : existente.condicionesComerciales,
            tiempoEntrega:
                tiempo.isNotEmpty ? tiempo : existente.tiempoEntrega,
            observaciones: observaciones.isNotEmpty
                ? observaciones
                : existente.observaciones,
          ),
        );
        _actualizados++;
      }
    }

    if (!mounted) return;
    setState(() => _estado = _Estado.listo);
  }

  void _reiniciar() {
    setState(() {
      _estado = _Estado.inicio;
      _headers = [];
      _filas = [];
      _mapeo = {};
      _mensajeError = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Importar Proveedores'),
      body: switch (_estado) {
        _Estado.inicio => _buildInicio(),
        _Estado.vista_previa => _buildVistaPrevia(),
        _Estado.importando => const Center(child: CircularProgressIndicator()),
        _Estado.listo => _buildListo(),
      },
    );
  }

  Widget _buildInicio() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .7),
            ),
            const SizedBox(height: 24),
            Text(
              'Importación masiva de proveedores',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Si el Nombre o CUIT coincide, se actualiza; si no, se crea.',
              textAlign: TextAlign.center,
            ),
            if (_mensajeError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _mensajeError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _seleccionarArchivo,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Seleccionar archivo'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _descargando ? null : _descargarPlantilla,
              icon: const Icon(Icons.download_rounded),
              label: const Text('Descargar plantilla Excel'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(220, 46)),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orden de columnas de la plantilla:',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    ...PlantillaImportacionService.proveedoresHeaders
                        .asMap()
                        .entries
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${e.key + 1}. ${e.value}'
                              '${e.value == 'Nombre' ? '  (obligatorio)' : ''}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVistaPrevia() {
    final ok = _mapeo.containsKey(_Col.nombre);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Columnas detectadas: ${_mapeo.length}/${_Col.values.length}'
                '${ok ? '' : '\n⚠ Falta Nombre'}',
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns:
                    _headers.map((h) => DataColumn(label: Text(h))).toList(),
                rows: _filas
                    .take(5)
                    .map(
                      (fila) => DataRow(
                        cells: List.generate(
                          _headers.length,
                          (i) => DataCell(
                            Text(i < fila.length ? fila[i].toString() : ''),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              OutlinedButton(onPressed: _reiniciar, child: const Text('Volver')),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: ok ? _importar : null,
                  icon: const Icon(Icons.upload_rounded),
                  label: Text('Importar ${_filas.length} proveedores'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            Text('Creados: $_importados'),
            Text('Actualizados: $_actualizados'),
            Text('Saltados: $_saltados'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _reiniciar,
              child: const Text('Importar otro archivo'),
            ),
          ],
        ),
      ),
    );
  }
}
