import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../theme/module_app_bar.dart';

class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key});

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  List<Map<String, dynamic>> registros = [];
  List<Map<String, dynamic>> filtrados = [];
  bool cargando = true;

  String? filtroUsuario;
  String? filtroAccion;
  DateTimeRange? filtroRango;

  List<String> get usuarios =>
      registros.map((r) => (r['usuario'] ?? '').toString()).toSet().toList()
        ..sort();

  List<String> get acciones =>
      registros.map((r) => (r['accion'] ?? '').toString()).toSet().toList()
        ..sort();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => cargando = true);
    final db = await DatabaseHelper.instance.database;
    registros = await db.query(
      'audit_log',
      orderBy: 'datetime(fecha) DESC, id DESC',
    );
    _aplicarFiltros();
    if (!mounted) return;
    setState(() => cargando = false);
  }

  void _aplicarFiltros() {
    filtrados = registros.where((r) {
      final usuarioOk =
          filtroUsuario == null || r['usuario'] == filtroUsuario;
      final accionOk = filtroAccion == null || r['accion'] == filtroAccion;
      var fechaOk = true;
      if (filtroRango != null) {
        final fecha = DateTime.tryParse(r['fecha']?.toString() ?? '');
        if (fecha != null) {
          final inicio = DateTime(filtroRango!.start.year,
              filtroRango!.start.month, filtroRango!.start.day);
          final fin = DateTime(filtroRango!.end.year, filtroRango!.end.month,
              filtroRango!.end.day, 23, 59, 59);
          fechaOk = !fecha.isBefore(inicio) && !fecha.isAfter(fin);
        }
      }
      return usuarioOk && accionOk && fechaOk;
    }).toList();
    if (mounted) setState(() {});
  }

  String _formatearFecha(String? texto) {
    final fecha = DateTime.tryParse(texto ?? '');
    if (fecha == null) return texto ?? '';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _elegirRango() async {
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: filtroRango,
    );
    if (rango != null) {
      setState(() => filtroRango = rango);
      _aplicarFiltros();
    }
  }

  void _limpiarFiltros() {
    setState(() {
      filtroUsuario = null;
      filtroAccion = null;
      filtroRango = null;
    });
    _aplicarFiltros();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Auditoría'),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auditoría',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String>(
                              initialValue: filtroUsuario,
                              decoration: const InputDecoration(
                                labelText: 'Usuario',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('Todos')),
                                ...usuarios.map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() => filtroUsuario = v);
                                _aplicarFiltros();
                              },
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              initialValue: filtroAccion,
                              decoration: const InputDecoration(
                                labelText: 'Acción',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('Todas')),
                                ...acciones.map(
                                  (a) => DropdownMenuItem(
                                    value: a,
                                    child: Text(a),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                setState(() => filtroAccion = v);
                                _aplicarFiltros();
                              },
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _elegirRango,
                            icon: const Icon(Icons.date_range_rounded),
                            label: Text(
                              filtroRango == null
                                  ? 'Rango de fechas'
                                  : '${_formatearFecha(filtroRango!.start.toIso8601String())} - ${_formatearFecha(filtroRango!.end.toIso8601String())}',
                            ),
                          ),
                          if (filtroUsuario != null ||
                              filtroAccion != null ||
                              filtroRango != null)
                            TextButton.icon(
                              onPressed: _limpiarFiltros,
                              icon: const Icon(Icons.close_rounded),
                              label: const Text('Limpiar filtros'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtrados.isEmpty
                      ? const Center(child: Text('No hay registros.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: filtrados.length,
                          itemBuilder: (context, i) {
                            final r = filtrados[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Icon(
                                    Icons.history_edu_rounded,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                title: Text(
                                  (r['accion'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        (r['detalle'] ?? '').toString()),
                                    Text(
                                      'Usuario: ${r['usuario']}  •  ${_formatearFecha(r['fecha']?.toString())}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
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
