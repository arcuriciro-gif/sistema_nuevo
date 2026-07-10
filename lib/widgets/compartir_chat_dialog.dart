import 'package:flutter/material.dart';

import '../models/chat_mensaje.dart';
import '../models/usuario.dart';
import '../services/comunicaciones_service.dart';

/// Diálogo para elegir destinatario y enviar un elemento compartido al chat.
Future<bool> showCompartirEnChatDialog(
  BuildContext context, {
  required ChatCompartido compartido,
}) async {
  final svc = ComunicacionesService.instance;
  await svc.refrescar();
  final usuarios = await svc.usuariosDisponibles();
  if (!context.mounted) return false;

  if (usuarios.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay otros usuarios para compartir')),
    );
    return false;
  }

  final result = await showModalBottomSheet<_ShareTarget>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CompartirSheet(
      usuarios: usuarios,
      compartido: compartido,
    ),
  );

  if (result == null || !context.mounted) return false;

  try {
    final conv = await svc.abrirOCrearDm(result.usuario);
    await svc.enviarCompartido(
      conversacionId: conv.id,
      compartido: compartido,
      comentario: result.comentario,
    );
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Compartido con ${result.usuario.nombre}')),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo compartir: $e')),
    );
    return false;
  }
}

class _ShareTarget {
  final Usuario usuario;
  final String? comentario;

  _ShareTarget({required this.usuario, this.comentario});
}

class _CompartirSheet extends StatefulWidget {
  final List<Usuario> usuarios;
  final ChatCompartido compartido;

  const _CompartirSheet({
    required this.usuarios,
    required this.compartido,
  });

  @override
  State<_CompartirSheet> createState() => _CompartirSheetState();
}

class _CompartirSheetState extends State<_CompartirSheet> {
  final _comentarioCtrl = TextEditingController();
  String _filtro = '';

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtrados = widget.usuarios
        .where((u) =>
            u.nombre.toLowerCase().contains(_filtro) ||
            u.usuario.toLowerCase().contains(_filtro))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compartir en Comunicaciones',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.compartido.titulo,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _comentarioCtrl,
              decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _filtro = v.toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Buscar usuario...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in filtrados)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primary,
                        child: Text(
                          u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : '?',
                          style: TextStyle(color: cs.onPrimary),
                        ),
                      ),
                      title: Text(u.nombre),
                      subtitle: Text(u.usuario),
                      onTap: () => Navigator.pop(
                        context,
                        _ShareTarget(
                          usuario: u,
                          comentario: _comentarioCtrl.text.trim(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
