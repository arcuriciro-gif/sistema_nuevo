import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../services/cliente_service.dart';
import '../services/importacion_archivo_helper.dart';
import '../services/plantilla_importacion_service.dart';
import '../theme/module_app_bar.dart';

enum _Col {
  nombre,
  apellido,
  telefono,
  whatsapp,
  email,
  direccion,
  localidad,
  provincia,
  cuit,
  condicionIva,
  descuento,
  limiteCuenta,
  observaciones,
}

const _colAliases = <_Col, Set<String>>{
  _Col.nombre: {'nombre', 'name', 'cliente'},
  _Col.apellido: {'apellido', 'lastname', 'surname'},
  _Col.telefono: {'telefono', 'tel', 'phone', 'celular'},
  _Col.whatsapp: {'whatsapp', 'wa', 'wsp'},
  _Col.email: {'email', 'mail', 'correo'},
  _Col.direccion: {'direccion', 'domicilio', 'address'},
  _Col.localidad: {'localidad', 'ciudad', 'city'},
  _Col.provincia: {'provincia', 'estado', 'state'},
  _Col.cuit: {'cuit', 'cuil', 'documento', 'dni'},
  _Col.condicionIva: {'condicioniva', 'iva', 'condicion'},
  _Col.descuento: {'descuento', 'dto', 'discount'},
  _Col.limiteCuenta: {'limitecuenta', 'limite', 'creditolimite'},
  _Col.observaciones: {'observaciones', 'obs', 'notas', 'comentario'},
};

const _ordenMapeo = [
  _Col.whatsapp,
  _Col.limiteCuenta,
  _Col.condicionIva,
  _Col.apellido,
  _Col.nombre,
  _Col.telefono,
  _Col.email,
  _Col.direccion,
  _Col.localidad,
  _Col.provincia,
  _Col.cuit,
  _Col.descuento,
  _Col.observaciones,
];

class ImportacionClientesPage extends StatefulWidget {
  const ImportacionClientesPage({super.key});

  @override
  State<ImportacionClientesPage> createState() =>
      _ImportacionClientesPageState();
}

enum _Estado { inicio, vista_previa, importando, listo }

class _ImportacionClientesPageState extends State<ImportacionClientesPage> {
  final ClienteService _svc = ClienteService();
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
      final file = await _plantillas.generarPlantillaClientes();
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
    double numCol(List<dynamic> fila, int? idx) =>
        ImportacionArchivoHelper.parsearNumero(valorCol(fila, idx));

    for (final fila in _filas) {
      final nombre = valorCol(fila, _mapeo[_Col.nombre]);
      if (nombre.isEmpty) {
        _saltados++;
        continue;
      }

      final apellido = valorCol(fila, _mapeo[_Col.apellido]);
      final telefono = valorCol(fila, _mapeo[_Col.telefono]);
      final whatsapp = valorCol(fila, _mapeo[_Col.whatsapp]);
      final email = valorCol(fila, _mapeo[_Col.email]);
      final direccion = valorCol(fila, _mapeo[_Col.direccion]);
      final localidad = valorCol(fila, _mapeo[_Col.localidad]);
      final provincia = valorCol(fila, _mapeo[_Col.provincia]);
      final cuit = valorCol(fila, _mapeo[_Col.cuit]);
      final condicionIva = valorCol(fila, _mapeo[_Col.condicionIva]);
      final observaciones = valorCol(fila, _mapeo[_Col.observaciones]);
      final descuento = numCol(fila, _mapeo[_Col.descuento]);
      final limite = numCol(fila, _mapeo[_Col.limiteCuenta]);

      Cliente? existente = await _svc.buscarPorCuit(cuit);
      existente ??= await _svc.buscarPorNombreApellido(nombre, apellido);

      if (existente == null) {
        await _svc.insertar(
          Cliente(
            nombre: nombre,
            apellido: apellido,
            telefono: telefono,
            whatsapp: whatsapp,
            email: email,
            direccion: direccion,
            localidad: localidad,
            provincia: provincia,
            cuit: cuit,
            condicionIva: condicionIva,
            observaciones: observaciones,
            descuento: descuento,
            limiteCuenta: limite,
          ),
        );
        _importados++;
      } else {
        await _svc.actualizar(
          existente.copyWith(
            apellido: apellido.isNotEmpty ? apellido : existente.apellido,
            telefono: telefono.isNotEmpty ? telefono : existente.telefono,
            whatsapp: whatsapp.isNotEmpty ? whatsapp : existente.whatsapp,
            email: email.isNotEmpty ? email : existente.email,
            direccion: direccion.isNotEmpty ? direccion : existente.direccion,
            localidad: localidad.isNotEmpty ? localidad : existente.localidad,
            provincia: provincia.isNotEmpty ? provincia : existente.provincia,
            cuit: cuit.isNotEmpty ? cuit : existente.cuit,
            condicionIva:
                condicionIva.isNotEmpty ? condicionIva : existente.condicionIva,
            observaciones: observaciones.isNotEmpty
                ? observaciones
                : existente.observaciones,
            descuento:
                _mapeo[_Col.descuento] != null ? descuento : existente.descuento,
            limiteCuenta: _mapeo[_Col.limiteCuenta] != null
                ? limite
                : existente.limiteCuenta,
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
      appBar: buildModuleAppBar(context, title: 'Importar Clientes'),
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
              Icons.people_alt_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .7),
            ),
            const SizedBox(height: 24),
            Text(
              'Importación masiva de clientes',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Si el CUIT coincide (o Nombre+Apellido), se actualiza; si no, se crea.',
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
            _ordenCard(PlantillaImportacionService.clientesHeaders, 'Nombre'),
          ],
        ),
      ),
    );
  }

  Widget _ordenCard(List<String> orden, String obligatorio) {
    return Card(
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
            ...orden.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${e.key + 1}. ${e.value}'
                      '${e.value == obligatorio ? '  (obligatorio)' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
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
                columns: _headers
                    .map((h) => DataColumn(label: Text(h)))
                    .toList(),
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
                  label: Text('Importar ${_filas.length} clientes'),
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
            Text('Creados: $_importados', style: const TextStyle(fontSize: 16)),
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
