import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/cliente.dart';
import 'comentarios_internos_sheet.dart';

/// Acciones rápidas de cliente (teléfono / WhatsApp deeplink / notas).
class ClienteAccionesCrm extends StatelessWidget {
  const ClienteAccionesCrm({
    super.key,
    required this.cliente,
    this.onCuentaCorriente,
    this.onHistorial,
    this.compact = false,
  });

  final Cliente cliente;
  final VoidCallback? onCuentaCorriente;
  final VoidCallback? onHistorial;
  final bool compact;

  static String digitosTelefono(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  static String? canalWhatsApp(Cliente c) {
    for (final raw in [c.whatsapp, c.telefono]) {
      final d = digitosTelefono(raw);
      if (d.length >= 8) return d;
    }
    return null;
  }

  static Future<void> abrirWhatsApp(
    BuildContext context,
    Cliente cliente, {
    String? mensaje,
  }) async {
    final digits = canalWhatsApp(cliente);
    if (digits == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este cliente no tiene WhatsApp ni teléfono'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      mensaje == null || mensaje.trim().isEmpty
          ? 'https://wa.me/$digits'
          : 'https://wa.me/$digits?text=${Uri.encodeComponent(mensaje)}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  static Future<void> llamar(BuildContext context, Cliente cliente) async {
    final raw = cliente.telefono.trim().isNotEmpty
        ? cliente.telefono
        : cliente.whatsapp;
    final digits = digitosTelefono(raw);
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este cliente no tiene teléfono')),
      );
      return;
    }
    final uri = Uri.parse('tel:$digits');
    final ok = await launchUrl(uri);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la llamada a $digits')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = cliente.id;
    final acciones = <Widget>[
      FilledButton.tonalIcon(
        onPressed: () => abrirWhatsApp(context, cliente),
        icon: const Icon(Icons.chat_rounded, size: 18),
        label: Text(compact ? 'WA' : 'WhatsApp'),
      ),
      FilledButton.tonalIcon(
        onPressed: () => llamar(context, cliente),
        icon: const Icon(Icons.phone_rounded, size: 18),
        label: const Text('Llamar'),
      ),
      if (id != null)
        FilledButton.tonalIcon(
          onPressed: () => showComentariosInternos(
            context,
            entidadTipo: 'cliente',
            entidadId: '$id',
            titulo: cliente.nombreCompleto,
          ),
          icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
          label: const Text('Notas'),
        ),
      if (onCuentaCorriente != null)
        FilledButton.tonalIcon(
          onPressed: onCuentaCorriente,
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: Text(compact ? 'CC' : 'Cuenta corriente'),
        ),
      if (onHistorial != null)
        OutlinedButton.icon(
          onPressed: onHistorial,
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('Historial'),
        ),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: acciones);
  }
}
