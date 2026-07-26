import 'package:flutter/material.dart';

import '../services/crm_automations_service.dart';

Future<void> showCrmAutomationsSheet(BuildContext context) async {
  final svc = CrmAutomationsService.instance;
  await svc.cargar();

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Automatizaciones',
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    'Reglas locales · crean seguimientos sin sync',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activar automatizaciones'),
                    subtitle: const Text('Se ejecutan 1 vez al día al abrir la app'),
                    value: svc.enabled,
                    onChanged: (v) async {
                      await svc.guardar(enabled: v);
                      setLocal(() {});
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Deuda sin agenda'),
                    subtitle: const Text(
                      'Si hay saldo y no hay seguimiento pendiente, programa cobro',
                    ),
                    value: svc.reglaDeuda,
                    onChanged: svc.enabled
                        ? (v) async {
                            await svc.guardar(reglaDeuda: v);
                            setLocal(() {});
                          }
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inactivos sin agenda'),
                    subtitle: const Text(
                      'Clientes sin compras 30 días → seguimiento reactivar',
                    ),
                    value: svc.reglaInactivos,
                    onChanged: svc.enabled
                        ? (v) async {
                            await svc.guardar(reglaInactivos: v);
                            setLocal(() {});
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Días hasta el contacto (cobro): ${svc.diasVencimientoCobro}',
                  ),
                  Slider(
                    value: svc.diasVencimientoCobro.toDouble(),
                    min: 0,
                    max: 14,
                    divisions: 14,
                    label: '${svc.diasVencimientoCobro}',
                    onChanged: svc.enabled
                        ? (v) async {
                            await svc.guardar(diasVencimientoCobro: v.round());
                            setLocal(() {});
                          }
                        : null,
                  ),
                  Text(
                    'Días hasta el contacto (reactivar): ${svc.diasVencimientoReactivar}',
                  ),
                  Slider(
                    value: svc.diasVencimientoReactivar.toDouble(),
                    min: 0,
                    max: 21,
                    divisions: 21,
                    label: '${svc.diasVencimientoReactivar}',
                    onChanged: svc.enabled
                        ? (v) async {
                            await svc.guardar(
                              diasVencimientoReactivar: v.round(),
                            );
                            setLocal(() {});
                          }
                        : null,
                  ),
                  TextFormField(
                    initialValue: svc.montoMinimoDeuda.toStringAsFixed(0),
                    decoration: const InputDecoration(
                      labelText: 'Monto mínimo de deuda',
                      border: OutlineInputBorder(),
                      prefixText: '\$ ',
                      isDense: true,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    enabled: svc.enabled,
                    onChanged: (v) async {
                      final n = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      await svc.guardar(montoMinimoDeuda: n);
                    },
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: !svc.enabled
                        ? null
                        : () async {
                            final r = await svc.ejecutar(forzar: true);
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  r.total == 0
                                      ? 'Sin cambios (ya estaban al día o sin casos)'
                                      : 'Creados: ${r.creadosCobro} cobro · ${r.creadosReactivar} reactivar',
                                ),
                              ),
                            );
                            Navigator.pop(ctx);
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Ejecutar ahora'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
