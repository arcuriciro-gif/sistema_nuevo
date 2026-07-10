import 'package:flutter/material.dart';

import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/comunicaciones_service.dart';
import '../theme/module_app_bar.dart';
import 'chat_page.dart';
import 'notificaciones_page.dart';

class ComunicacionesPage extends StatefulWidget {
  const ComunicacionesPage({super.key});

  @override
  State<ComunicacionesPage> createState() => _ComunicacionesPageState();
}

class _ComunicacionesPageState extends State<ComunicacionesPage> {
  final _svc = ComunicacionesService.instance;
  String _busqueda = '';

  String get _yo => AuthService.instance.currentUser?.usuario ?? '';

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChange);
    _svc.iniciar();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _svc.removeListener(_onChange);
    super.dispose();
  }

  Future<void> _nuevaConversacion() async {
    final usuarios = await _svc.usuariosDisponibles();
    if (!mounted) return;
    if (usuarios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay otros usuarios activos')),
      );
      return;
    }

    final elegido = await showModalBottomSheet<Usuario>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Nueva conversación',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final u in usuarios)
              ListTile(
                leading: CircleAvatar(
                  child: Text(
                    u.nombre.isNotEmpty ? u.nombre[0].toUpperCase() : '?',
                  ),
                ),
                title: Text(u.nombre),
                subtitle: Text('${u.usuario} · ${u.rol}'),
                onTap: () => Navigator.pop(ctx, u),
              ),
          ],
        ),
      ),
    );
    if (elegido == null || !mounted) return;
    final conv = await _svc.abrirOCrearDm(elegido);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatPage(conversacion: conv)),
    );
    await _svc.refrescar();
  }

  Future<void> _nuevoGrupo() async {
    final usuarios = await _svc.usuariosDisponibles();
    if (!mounted) return;
    final seleccion = <String>{};
    final tituloCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo grupo'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del grupo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in usuarios)
                        CheckboxListTile(
                          value: seleccion.contains(u.usuario),
                          title: Text(u.nombre),
                          subtitle: Text(u.usuario),
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                seleccion.add(u.usuario);
                              } else {
                                seleccion.remove(u.usuario);
                              }
                            });
                          },
                        ),
                    ],
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
            FilledButton(
              onPressed: seleccion.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      tituloCtrl.dispose();
      return;
    }
    final miembros =
        usuarios.where((u) => seleccion.contains(u.usuario)).toList();
    final conv = await _svc.crearGrupo(
      titulo: tituloCtrl.text,
      miembros: miembros,
    );
    tituloCtrl.dispose();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatPage(conversacion: conv)),
    );
  }

  String _fmtHora(DateTime? f) {
    if (f == null) return '';
    final now = DateTime.now();
    if (f.year == now.year && f.month == now.month && f.day == now.day) {
      return '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
    }
    return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lista = _svc.conversaciones.where((c) {
      if (_busqueda.isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return c.tituloPara(_yo).toLowerCase().contains(q) ||
          c.ultimoMensaje.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Comunicaciones',
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _svc.refrescar(),
          ),
          IconButton(
            tooltip: 'Notificaciones',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificacionesPage()),
              );
            },
            icon: Badge(
              isLabelVisible: _svc.notifSinLeer > 0,
              label: Text('${_svc.notifSinLeer}'),
              child: const Icon(Icons.notifications_rounded),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'dm') _nuevaConversacion();
              if (v == 'grupo') _nuevoGrupo();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dm', child: Text('Nueva conversación')),
              PopupMenuItem(value: 'grupo', child: Text('Nuevo grupo')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_comunicaciones',
        onPressed: _nuevaConversacion,
        icon: const Icon(Icons.chat_rounded),
        label: const Text('Nuevo chat'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: const InputDecoration(
                hintText: 'Buscar conversaciones...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 64, color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'Todavía no hay conversaciones',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _nuevaConversacion,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Empezar a chatear'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
                    itemCount: lista.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = lista[i];
                      final unread = c.noLeidosDe(_yo);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: c.tipo == 'grupo'
                              ? cs.secondaryContainer
                              : cs.primaryContainer,
                          child: c.tipo == 'grupo'
                              ? Icon(Icons.groups_rounded,
                                  color: cs.onSecondaryContainer)
                              : Text(
                                  c.inicialPara(_yo),
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        title: Text(
                          c.tituloPara(_yo),
                          style: TextStyle(
                            fontWeight:
                                unread > 0 ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          c.ultimoMensaje.isEmpty
                              ? 'Sin mensajes'
                              : c.ultimoMensaje,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _fmtHora(c.ultimoMensajeAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (unread > 0) ...[
                              const SizedBox(height: 4),
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: cs.primary,
                                child: Text(
                                  '$unread',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(conversacion: c),
                            ),
                          );
                          await _svc.refrescar();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
