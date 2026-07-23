import 'package:flutter/material.dart';

import '../core/security/authorization_service.dart';
import '../models/chat_mensaje.dart';
import '../models/lista_precio.dart';
import '../models/producto.dart';
import '../theme/app_visuals.dart';
import '../theme/module_app_bar.dart';
import '../widgets/compartir_chat_dialog.dart';
import '../widgets/comentarios_internos_sheet.dart';
import '../widgets/foto_ampliada.dart';
import '../widgets/media_avatar.dart';
import 'producto_form_page.dart';

/// Ficha de producto: foto, datos, precios y acciones.
class ProductoDetallePage extends StatelessWidget {
  final Producto producto;
  final List<ListaPrecio> listasActivas;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleFavorito;

  const ProductoDetallePage({
    super.key,
    required this.producto,
    this.listasActivas = const [],
    this.onEdit,
    this.onDelete,
    this.onToggleFavorito,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = producto;
    final puedeEditar = onEdit != null ||
        AuthorizationService.instance.puedeEditarProductos;
    final puedeEliminar = onDelete != null ||
        AuthorizationService.instance.puedeEliminarProductos;

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Producto',
        actions: [
          if (onToggleFavorito != null)
            IconButton(
              tooltip: p.favorito ? 'Quitar favorito' : 'Favorito',
              icon: Icon(
                p.favorito ? Icons.star_rounded : Icons.star_outline_rounded,
                color: p.favorito ? const Color(0xFFFFB020) : null,
              ),
              onPressed: onToggleFavorito,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: GestureDetector(
              onTap: p.fotoPrincipal.trim().isEmpty
                  ? null
                  : () => showFotoAmpliada(
                        context,
                        path: p.fotoPrincipal,
                        titulo: p.descripcion,
                      ),
              child: MediaAvatar(
                path: p.fotoPrincipal,
                radius: 56,
                fallbackLetter: (p.descripcion.isNotEmpty
                        ? p.descripcion
                        : p.codigo)
                    .substring(0, 1),
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            p.descripcion,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (p.codigo.isNotEmpty) 'Cód: ${p.codigo}',
              if (p.marca.isNotEmpty) p.marca,
              if (p.categoria.isNotEmpty) p.categoria,
            ].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(cs, 'Stock ${p.stock}', Icons.inventory_2_outlined),
              _chip(
                cs,
                'Costo \$${p.costo.toStringAsFixed(2)}',
                Icons.payments_outlined,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Precios',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          _precioTile(cs, 'Lista 1', p.precio),
          if (p.precio2 > 0) _precioTile(cs, 'Lista 2', p.precio2),
          if (p.precio3 > 0) _precioTile(cs, 'Lista 3', p.precio3),
          for (final lista in listasActivas)
            _precioTile(cs, lista.nombre, lista.calcularPrecio(p.costo)),
          if (p.observaciones.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Observaciones',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(p.observaciones),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => showComentariosInternos(
                  context,
                  entidadTipo: 'producto',
                  entidadId: '${p.id}',
                  titulo: p.descripcion,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Notas'),
              ),
              OutlinedButton.icon(
                onPressed: () => showCompartirEnChatDialog(
                  context,
                  compartido: ChatCompartido(
                    tipo: 'producto',
                    idRef: '${p.id}',
                    titulo: p.descripcion,
                    subtitulo:
                        'Cód: ${p.codigo} · Stock ${p.stock} · \$${p.precio.toStringAsFixed(2)}',
                    datos: {
                      'codigo': p.codigo,
                      'stock': p.stock,
                      'precio': p.precio,
                    },
                  ),
                ),
                icon: const Icon(Icons.share_rounded),
                label: const Text('Compartir'),
              ),
              if (puedeEditar)
                FilledButton.tonalIcon(
                  onPressed: onEdit ??
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductoFormPage(producto: p),
                          ),
                        );
                        if (context.mounted) Navigator.pop(context, true);
                      },
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Editar'),
                ),
              if (puedeEliminar && onDelete != null)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    foregroundColor: AppVisuals.danger(cs),
                  ),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Papelera'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme cs, String text, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(text),
      backgroundColor: cs.surfaceContainerHighest,
    );
  }

  Widget _precioTile(ColorScheme cs, String label, double value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(
          '\$${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}
