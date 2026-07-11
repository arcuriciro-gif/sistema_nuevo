import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../services/branding_service.dart';
import '../services/thermal_print_service.dart';
import '../theme/module_app_bar.dart';

/// Configura la impresora térmica Bluetooth (emparejada en el sistema).
class ImpresoraTermicaPage extends StatefulWidget {
  const ImpresoraTermicaPage({super.key});

  @override
  State<ImpresoraTermicaPage> createState() => _ImpresoraTermicaPageState();
}

class _ImpresoraTermicaPageState extends State<ImpresoraTermicaPage> {
  final _svc = ThermalPrintService.instance;
  List<BluetoothInfo> _dispositivos = [];
  bool _cargando = true;
  bool _imprimiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    await _svc.cargar();
    if (!_svc.plataformaSoportada) {
      setState(() {
        _cargando = false;
        _error = 'La impresión térmica Bluetooth no está disponible en esta plataforma.';
      });
      return;
    }
    final permisos = await _svc.asegurarPermisos();
    if (!permisos) {
      setState(() {
        _cargando = false;
        _error =
            'Falta permiso de Bluetooth. Activalo en Ajustes del celular.';
      });
      return;
    }
    final on = await _svc.bluetoothEncendido();
    if (!on) {
      setState(() {
        _cargando = false;
        _error = 'Activá el Bluetooth del dispositivo.';
      });
      return;
    }
    final list = await _svc.dispositivosEmparejados();
    if (!mounted) return;
    setState(() {
      _dispositivos = list;
      _cargando = false;
      if (list.isEmpty) {
        _error =
            'No hay impresoras emparejadas. Emparejá la térmica en Ajustes → Bluetooth y volvé.';
      }
    });
  }

  Future<void> _seleccionar(BluetoothInfo info) async {
    setState(() => _imprimiendo = true);
    final ok = await _svc.conectar(info.macAdress);
    if (ok) {
      await _svc.guardarImpresora(mac: info.macAdress, name: info.name);
    }
    if (!mounted) return;
    setState(() => _imprimiendo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Impresora guardada: ${info.name}'
              : 'No se pudo conectar a ${info.name}',
        ),
        backgroundColor: ok ? null : Colors.red,
      ),
    );
    setState(() {});
  }

  Future<void> _probar() async {
    if (!_svc.tieneImpresoraGuardada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero elegí una impresora.')),
      );
      return;
    }
    setState(() => _imprimiendo = true);
    final ok = await _svc.imprimirTicket(
      tituloDocumento: 'PRUEBA',
      numero: 'TEST',
      fechaIso: DateTime.now().toIso8601String(),
      clienteNombre: 'Prueba de impresión',
      items: [
        {
          'descripcion': 'Artículo de prueba',
          'cantidad': 1,
          'precio': 100.0,
          'subtotal': 100.0,
        },
      ],
      total: 100,
    );
    if (!mounted) return;
    setState(() => _imprimiendo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Ticket de prueba enviado.' : 'Falló la impresión.'),
        backgroundColor: ok ? null : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Impresora térmica',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _iniciar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Impresión Bluetooth ESC/POS',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Funciona con impresoras térmicas 58/80 mm emparejadas por Bluetooth. '
                    'El ancho se toma de la plantilla de impresión (Configuración). '
                    'No pide ubicación (requisito de Google Play).',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_svc.tieneImpresoraGuardada)
            Card(
              color: cs.primaryContainer.withValues(alpha: .35),
              child: ListTile(
                leading: const Icon(Icons.print_rounded),
                title: Text(_svc.printerName ?? 'Impresora'),
                subtitle: Text(_svc.printerMac ?? ''),
                trailing: IconButton(
                  tooltip: 'Olvidar',
                  onPressed: () async {
                    await _svc.olvidarImpresora();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.link_off_rounded),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 12),
          if (_cargando)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else ...[
            Text(
              'Dispositivos emparejados',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ..._dispositivos.map(
              (d) => Card(
                child: ListTile(
                  leading: Icon(
                    Icons.bluetooth_connected_rounded,
                    color: (_svc.printerMac == d.macAdress)
                        ? cs.primary
                        : cs.onSurfaceVariant,
                  ),
                  title: Text(d.name),
                  subtitle: Text(d.macAdress),
                  trailing: _imprimiendo
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => _seleccionar(d),
                          child: Text(
                            _svc.printerMac == d.macAdress
                                ? 'Usar'
                                : 'Elegir',
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _imprimiendo || !_svc.tieneImpresoraGuardada
                  ? null
                  : _probar,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Imprimir ticket de prueba'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Diálogo reutilizable: imprime ticket térmico o pide configurar impresora.
Future<bool> imprimirTicketTermico(
  BuildContext context, {
  required String tituloDocumento,
  required String numero,
  required String fechaIso,
  required String clienteNombre,
  required List<Map<String, dynamic>> items,
  required double total,
  double descuento = 0,
  String? observaciones,
  String? estadoPago,
}) async {
  final svc = ThermalPrintService.instance;
  await BrandingService.instance.cargar();
  await svc.cargar();

  if (!svc.plataformaSoportada) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresión térmica no disponible en esta plataforma.'),
        ),
      );
    }
    return false;
  }

  if (!svc.tieneImpresoraGuardada) {
    if (!context.mounted) return false;
    final ir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Impresora térmica'),
        content: const Text(
          'Todavía no hay una impresora configurada. '
          '¿Querés elegirla ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Configurar'),
          ),
        ],
      ),
    );
    if (ir == true && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImpresoraTermicaPage()),
      );
      await svc.cargar();
    }
    if (!svc.tieneImpresoraGuardada) return false;
  }

  if (!context.mounted) return false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final ok = await svc.imprimirTicket(
    tituloDocumento: tituloDocumento,
    numero: numero,
    fechaIso: fechaIso,
    clienteNombre: clienteNombre,
    items: items,
    total: total,
    descuento: descuento,
    observaciones: observaciones,
    estadoPago: estadoPago,
  );

  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Ticket enviado a la impresora.' : 'No se pudo imprimir.'),
        backgroundColor: ok ? null : Colors.red,
      ),
    );
  }
  return ok;
}
