import 'package:flutter/material.dart';

import '../models/comentario_interno.dart';
import '../services/auth_service.dart';
import '../services/comentario_interno_service.dart';

/// Abre el panel de comentarios internos de una entidad.
Future<void> showComentariosInternos(
  BuildContext context, {
  required String entidadTipo,
  required String entidadId,
  String? titulo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => ComentariosInternosSheet(
      entidadTipo: entidadTipo,
      entidadId: entidadId,
      titulo: titulo,
    ),
  );
}

/// Botón compacto para AppBar / filas.
class ComentariosInternosButton extends StatelessWidget {
  final String entidadTipo;
  final String entidadId;
  final String? titulo;
  final bool iconOnly;

  const ComentariosInternosButton({
    super.key,
    required this.entidadTipo,
    required this.entidadId,
    this.titulo,
    this.iconOnly = true,
  });

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return IconButton(
        tooltip: 'Comentarios internos',
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        onPressed: () => showComentariosInternos(
          context,
          entidadTipo: entidadTipo,
          entidadId: entidadId,
          titulo: titulo,
        ),
      );
    }
    return TextButton.icon(
      onPressed: () => showComentariosInternos(
        context,
        entidadTipo: entidadTipo,
        entidadId: entidadId,
        titulo: titulo,
      ),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
      label: const Text('Comentarios'),
    );
  }
}

class ComentariosInternosSheet extends StatefulWidget {
  final String entidadTipo;
  final String entidadId;
  final String? titulo;

  const ComentariosInternosSheet({
    super.key,
    required this.entidadTipo,
    required this.entidadId,
    this.titulo,
  });

  @override
  State<ComentariosInternosSheet> createState() =>
      _ComentariosInternosSheetState();
}

class _ComentariosInternosSheetState extends State<ComentariosInternosSheet> {
  final _svc = ComentarioInternoService.instance;
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus = FocusNode();
  List<ComentarioInterno> _items = [];
  bool _cargando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final items = await _svc.listar(
      entidadTipo: widget.entidadTipo,
      entidadId: widget.entidadId,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _cargando = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    _ctrl.clear();
    _focus.unfocus();
    try {
      await _svc.agregar(
        entidadTipo: widget.entidadTipo,
        entidadId: widget.entidadId,
        texto: texto,
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      // Si falló, devolver el texto para reintentar.
      _ctrl.text = texto;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _borrar(ComentarioInterno c) async {
    if (c.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('¿Borrar este comentario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.eliminar(c.id!);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  String _fmt(DateTime f) {
    final local = f.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  bool _puedeBorrar(ComentarioInterno c) {
    final yo = AuthService.instance.currentUser?.usuario;
    return AuthService.instance.esAdministrador() || c.usuario == yo;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = widget.titulo?.trim().isNotEmpty == true
        ? widget.titulo!
        : 'Comentarios internos';
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comentarios internos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    titulo,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _cargando
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Todavía no hay comentarios.\n'
                              'Dejá una nota para el equipo (precios, entregas, pagos…).',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final c = _items[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 8, 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: cs.primaryContainer,
                                      child: Text(
                                        c.nombre.isNotEmpty
                                            ? c.nombre[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          color: cs.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  c.nombre,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _fmt(c.fecha),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(c.texto),
                                        ],
                                      ),
                                    ),
                                    if (_puedeBorrar(c))
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () => _borrar(c),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            // Misma idea que FormSaveBar: SafeArea para no pisar gestos Android.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) {
                          if (!_enviando) _enviar();
                        },
                        decoration: const InputDecoration(
                          hintText: 'Agregar comentario...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      width: 48,
                      child: IconButton.filled(
                        onPressed: _enviando ? null : _enviar,
                        icon: _enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded),
                        tooltip: 'Agregar comentario',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
