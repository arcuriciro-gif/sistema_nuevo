import 'package:flutter/material.dart';

import '../models/chat_conversacion.dart';
import '../models/notificacion_interna.dart';
import '../models/producto.dart';
import '../services/producto_service.dart';
import '../services/comunicaciones_service.dart';
import '../theme/module_app_bar.dart';
import 'chat_page.dart';
import 'producto_form_page.dart';
import 'stock_page.dart';

class NotificacionesPage extends StatefulWidget {
  const NotificacionesPage({super.key});

  @override
  State<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends State<NotificacionesPage> {
  final _svc = ComunicacionesService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChange);
    _svc.refrescar();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _svc.removeListener(_onChange);
    super.dispose();
  }

  IconData _icon(String tipo) => switch (tipo) {
        'mensaje' || 'archivo' => Icons.chat_bubble_rounded,
        'stock' => Icons.inventory_2_rounded,
        'cobro' => Icons.payments_rounded,
        'venta' => Icons.point_of_sale_rounded,
        'remito' => Icons.local_shipping_rounded,
        'presupuesto' => Icons.request_quote_rounded,
        'cliente' => Icons.person_rounded,
        _ => Icons.notifications_rounded,
      };

  Color _color(String tipo, ColorScheme cs) => switch (tipo) {
        'mensaje' || 'archivo' => cs.primary,
        'stock' => Colors.orange,
        'cobro' => Colors.green,
        'venta' => Colors.blue,
        'remito' => Colors.teal,
        'presupuesto' => Colors.indigo,
        'cliente' => Colors.purple,
        _ => cs.onSurfaceVariant,
      };

  String _fmt(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} '
      '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

  Future<void> _abrir(NotificacionInterna n) async {
    await _svc.marcarNotificacionLeida(n.id);
    if (!mounted) return;
    if (n.conversacionId != null && n.conversacionId!.isNotEmpty) {
      final conv = _svc.conversaciones
          .where((c) => c.id == n.conversacionId)
          .cast<ChatConversacion?>()
          .firstWhere((c) => c != null, orElse: () => null);
      if (conv != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatPage(conversacion: conv)),
        );
      }
      return;
    }
    if (n.tipo == 'stock' || n.entidadTipo == 'stock') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StockPage()),
      );
      return;
    }
    if (n.entidadTipo == 'producto' && (n.entidadId ?? '').isNotEmpty) {
      final id = int.tryParse(n.entidadId!);
      if (id != null) {
        final productos = await ProductoService().obtenerTodos();
        Producto? prod;
        for (final p in productos) {
          if (p.id == id) {
            prod = p;
            break;
          }
        }
        if (prod != null && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProductoFormPage(producto: prod)),
          );
          return;
        }
      }
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StockPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _svc.notificaciones;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Notificaciones',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _svc.refrescar(),
          ),
          if (_svc.notifSinLeer > 0)
            TextButton(
              onPressed: () => _svc.marcarTodasNotificacionesLeidas(),
              child: const Text('Marcar todas'),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 48,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sin notificaciones',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_svc.mensajesSinLeer > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tenés ${_svc.mensajesSinLeer} mensaje(s) de chat sin leer. '
                        'Abrilos desde Comunicaciones.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                final color = _color(n.tipo, cs);
                return ListTile(
                  tileColor: n.leida
                      ? null
                      : cs.primaryContainer.withValues(alpha: 0.25),
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(_icon(n.tipo), color: color),
                  ),
                  title: Text(
                    n.titulo,
                    style: TextStyle(
                      fontWeight: n.leida ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text('${n.cuerpo}\n${_fmt(n.fecha)}'),
                  isThreeLine: true,
                  onTap: () => _abrir(n),
                );
              },
            ),
    );
  }
}
