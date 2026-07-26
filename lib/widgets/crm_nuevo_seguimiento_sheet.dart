import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/crm_seguimiento.dart';
import '../services/crm_seguimiento_service.dart';

Future<bool> showNuevoSeguimientoSheet(
  BuildContext context, {
  required Cliente cliente,
  String tipoInicial = 'otro',
  String tituloInicial = '',
  String notaInicial = '',
  int diasDefault = 3,
}) async {
  if (cliente.id == null) return false;
  final tituloCtrl = TextEditingController(
    text: tituloInicial.isEmpty ? 'Contactar a ${cliente.nombre}' : tituloInicial,
  );
  final notaCtrl = TextEditingController(text: notaInicial);
  var tipo = tipoInicial;
  var fecha = DateTime.now().add(Duration(days: diasDefault));

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nuevo seguimiento',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  cliente.nombreCompleto,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Tipo', style: Theme.of(ctx).textTheme.labelLarge),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cobro', label: Text('Cobro')),
                    ButtonSegment(value: 'reactivar', label: Text('Reactivar')),
                    ButtonSegment(value: 'otro', label: Text('Otro')),
                  ],
                  selected: {tipo},
                  onSelectionChanged: (s) => setLocal(() => tipo = s.first),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de contacto'),
                  subtitle: Text(
                    '${fecha.day.toString().padLeft(2, '0')}/'
                    '${fecha.month.toString().padLeft(2, '0')}/'
                    '${fecha.year}',
                  ),
                  trailing: const Icon(Icons.calendar_month_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: fecha,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setLocal(() => fecha = picked);
                  },
                ),
                TextField(
                  controller: notaCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () async {
                    final titulo = tituloCtrl.text.trim();
                    if (titulo.isEmpty) return;
                    await CrmSeguimientoService.instance.crear(
                      CrmSeguimiento(
                        clienteId: cliente.id!,
                        clienteNombre: cliente.nombreCompleto,
                        titulo: titulo,
                        nota: notaCtrl.text.trim(),
                        tipo: tipo,
                        fechaVencimiento: DateTime(
                          fecha.year,
                          fecha.month,
                          fecha.day,
                          18,
                        ),
                        creadoEn: DateTime.now(),
                      ),
                    );
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.event_available_rounded),
                  label: const Text('Guardar seguimiento'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  tituloCtrl.dispose();
  notaCtrl.dispose();
  return ok == true;
}
