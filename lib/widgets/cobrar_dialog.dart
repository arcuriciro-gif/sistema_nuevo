import 'package:flutter/material.dart';

import '../models/pago.dart';
import '../models/venta.dart';
import '../services/cuenta_corriente_service.dart';
import '../theme/app_visuals.dart';

Future<bool> mostrarDialogoCobrar({
  required BuildContext context,
  required Venta venta,
  CuentaCorrienteService? service,
}) async {
  final cc = service ?? CuentaCorrienteService();
  final montoCtrl = TextEditingController(
    text: venta.saldoPendiente.toStringAsFixed(2),
  );
  final obsCtrl = TextEditingController();
  String medio = 'efectivo';
  final cs = Theme.of(context).colorScheme;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
          final nuevoSaldo =
              (venta.saldoPendiente - monto).clamp(0, venta.saldoPendiente);
          return AlertDialog(
            title: const Text('Cobrar'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${venta.tipoLabel} ${venta.numero}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saldo pendiente: \$${venta.saldoPendiente.toStringAsFixed(2)}',
                    style: TextStyle(color: AppVisuals.danger(cs)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: montoCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monto recibido',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: medio,
                    decoration: const InputDecoration(
                      labelText: 'Medio de pago',
                      border: OutlineInputBorder(),
                    ),
                    items: Pago.mediosPago
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(Pago.labelMedio(m)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => medio = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: obsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    monto >= venta.saldoPendiente - 0.009
                        ? 'Quedará Pagada'
                        : 'Nuevo saldo: \$${nuevoSaldo.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: monto >= venta.saldoPendiente - 0.009
                          ? AppVisuals.success(cs)
                          : AppVisuals.warning(cs),
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
                onPressed: monto <= 0
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Registrar pago'),
              ),
            ],
          );
        },
      );
    },
  );

  if (ok != true) {
    montoCtrl.dispose();
    obsCtrl.dispose();
    return false;
  }

  try {
    final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
    await cc.registrarPago(
      ventaId: venta.id!,
      monto: monto,
      medioPago: medio,
      observaciones: obsCtrl.text.trim(),
    );
    montoCtrl.dispose();
    obsCtrl.dispose();
    return true;
  } catch (e) {
    montoCtrl.dispose();
    obsCtrl.dispose();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cobrar: $e')),
      );
    }
    return false;
  }
}

/// Cobro parcial o total de un remito (deja saldo pendiente si no paga todo).
Future<bool> mostrarDialogoCobrarRemito({
  required BuildContext context,
  required Map<String, dynamic> remito,
  CuentaCorrienteService? service,
}) async {
  final cc = service ?? CuentaCorrienteService();
  final total = (remito['total'] as num?)?.toDouble() ?? 0;
  final pagado = (remito['totalPagado'] as num?)?.toDouble() ?? 0;
  final saldoRaw = (remito['saldoPendiente'] as num?)?.toDouble();
  final saldo =
      saldoRaw ?? (total - pagado).clamp(0, total).toDouble();
  if (saldo <= 0.009) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El remito ya está cobrado.')),
      );
    }
    return false;
  }

  final montoCtrl = TextEditingController(text: saldo.toStringAsFixed(2));
  final obsCtrl = TextEditingController();
  String medio = 'efectivo';
  final cs = Theme.of(context).colorScheme;
  final numero = remito['numero']?.toString() ?? '';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final monto =
              double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
          final nuevoSaldo = (saldo - monto).clamp(0, saldo);
          return AlertDialog(
            title: const Text('Cobrar remito'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remito $numero',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Total: \$${total.toStringAsFixed(2)}'),
                  Text(
                    'Saldo pendiente: \$${saldo.toStringAsFixed(2)}',
                    style: TextStyle(color: AppVisuals.danger(cs)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Podés cobrar solo una parte; el resto queda a cuenta.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: montoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Monto recibido',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () {
                          montoCtrl.text = (saldo / 2).toStringAsFixed(2);
                          setLocal(() {});
                        },
                        child: const Text('Mitad'),
                      ),
                      TextButton(
                        onPressed: () {
                          montoCtrl.text = saldo.toStringAsFixed(2);
                          setLocal(() {});
                        },
                        child: const Text('Todo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: medio,
                    decoration: const InputDecoration(
                      labelText: 'Medio de pago',
                      border: OutlineInputBorder(),
                    ),
                    items: Pago.mediosPago
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(Pago.labelMedio(m)),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setLocal(() => medio = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: obsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    monto >= saldo - 0.009
                        ? 'Quedará cobrado'
                        : 'Quedará pendiente: \$${nuevoSaldo.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: monto >= saldo - 0.009
                          ? AppVisuals.success(cs)
                          : AppVisuals.warning(cs),
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
                onPressed: monto <= 0 ? null : () => Navigator.pop(ctx, true),
                child: const Text('Registrar pago'),
              ),
            ],
          );
        },
      );
    },
  );

  if (ok != true) {
    montoCtrl.dispose();
    obsCtrl.dispose();
    return false;
  }

  try {
    final monto = double.tryParse(montoCtrl.text.replaceAll(',', '.')) ?? 0;
    final id = remito['id'] as int;
    await cc.registrarPagoRemito(
      remitoId: id,
      monto: monto,
      medioPago: medio,
      observaciones: obsCtrl.text.trim(),
    );
    montoCtrl.dispose();
    obsCtrl.dispose();
    return true;
  } catch (e) {
    montoCtrl.dispose();
    obsCtrl.dispose();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cobrar remito: $e')),
      );
    }
    return false;
  }
}

Color colorEstadoPago(String estado, ColorScheme cs) {
  switch (estado) {
    case 'cobrado':
      return AppVisuals.success(cs);
    case 'parcial':
      return AppVisuals.warning(cs);
    default:
      return AppVisuals.danger(cs);
  }
}

Widget chipEstadoPago(String estado, ColorScheme cs) {
  final color = colorEstadoPago(estado, cs);
  final label = switch (estado) {
    'cobrado' => 'Pagada',
    'parcial' => 'Pago parcial',
    _ => 'Pendiente',
  };
  return Chip(
    label: Text(label, style: TextStyle(color: color, fontSize: 12)),
    backgroundColor: color.withValues(alpha: .15),
    visualDensity: VisualDensity.compact,
    side: BorderSide.none,
  );
}
