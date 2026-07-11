import 'package:flutter/material.dart';

import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/sync/sync_queue_service.dart';
import '../services/auth_service.dart';

/// Historial técnico de sincronización + cola pendiente.
class SyncHistorialPage extends StatefulWidget {
  const SyncHistorialPage({super.key});

  @override
  State<SyncHistorialPage> createState() => _SyncHistorialPageState();
}

class _SyncHistorialPageState extends State<SyncHistorialPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<Map<String, dynamic>> _cola = [];
  List<Map<String, dynamic>> _historial = [];
  bool _loading = true;
  bool _conectando = false;
  bool _subiendoCatalogo = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    SyncQueueService.instance.addListener(_onSync);
    _cargar();
  }

  @override
  void dispose() {
    SyncQueueService.instance.removeListener(_onSync);
    _tabs.dispose();
    super.dispose();
  }

  void _onSync() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    final cola = await SyncQueueService.instance.listarCola();
    final hist = await SyncQueueService.instance.listarHistorial(limit: 200);
    if (!mounted) return;
    setState(() {
      _cola = cola;
      _historial = hist;
      _loading = false;
    });
  }

  Future<void> _conectarNube() async {
    final passCtrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Conectar a la nube'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresá la contraseña de este usuario (la misma en PC y celular).',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, passCtrl.text),
              child: const Text('Conectar'),
            ),
          ],
        );
      },
    );
    passCtrl.dispose();
    if (pass == null || pass.trim().isEmpty || !mounted) return;

    setState(() => _conectando = true);
    final ok = await AuthService.instance.reconectarNube(password: pass.trim());
    if (!mounted) return;
    setState(() => _conectando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Conectado a la nube. Ya podés sincronizar.'
              : (AuthService.instance.lastFirebaseError ??
                  'No se pudo conectar.'),
        ),
        duration: const Duration(seconds: 5),
      ),
    );
    await _cargar();
  }

  Future<void> _subirCatalogo() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subir catálogo local'),
        content: const Text(
          'Va a subir todos los productos de ESTE dispositivo a la nube '
          'para que el celular/PC se igualen. Puede tardar un poco.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Subir'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _subiendoCatalogo = true);
    try {
      final n =
          await FirestoreSyncService.instance.subirCatalogoLocalCompleto();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se subieron $n productos a la nube.'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo subir el catálogo: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _subiendoCatalogo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncQueueService.instance;
    final cs = Theme.of(context).colorScheme;
    final sinNube = FirebaseAuthUsuarioService.instance.uidActual == null &&
        FirebaseAuthUsuarioService.instance.disponible;
    final conNube = FirebaseAuthUsuarioService.instance.uidActual != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronización'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: 'Pendientes (${sync.pendingCount})'),
            const Tab(text: 'Historial'),
          ],
        ),
        actions: [
          if (sinNube)
            TextButton.icon(
              onPressed: _conectando ? null : _conectarNube,
              icon: _conectando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_rounded),
              label: const Text('Conectar'),
            ),
          if (conNube)
            IconButton(
              tooltip: 'Subir catálogo local a la nube',
              onPressed: _subiendoCatalogo ? null : _subirCatalogo,
              icon: _subiendoCatalogo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
            ),
          IconButton(
            tooltip: 'Reintentar fallidos',
            onPressed: () async {
              await sync.reintentarFallidos();
              await _cargar();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: ListTile(
                    leading: Icon(
                      Icons.info_outline_rounded,
                      color: cs.primary,
                    ),
                    title: Text(sync.uiLabel),
                    subtitle: Text(sync.uiDetalle),
                    trailing: sinNube
                        ? FilledButton(
                            onPressed: _conectando ? null : _conectarNube,
                            child: const Text('Conectar a la nube'),
                          )
                        : conNube
                            ? FilledButton.tonal(
                                onPressed:
                                    _subiendoCatalogo ? null : _subirCatalogo,
                                child: Text(
                                  _subiendoCatalogo
                                      ? 'Subiendo…'
                                      : 'Subir catálogo',
                                ),
                              )
                            : null,
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildLista(
                        _cola,
                        empty: 'No hay operaciones pendientes',
                        isQueue: true,
                      ),
                      _buildLista(
                        _historial,
                        empty: 'Sin historial todavía',
                        isQueue: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLista(
    List<Map<String, dynamic>> rows, {
    required String empty,
    required bool isQueue,
  }) {
    if (rows.isEmpty) {
      return Center(child: Text(empty));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final type = r['entityType']?.toString() ?? '';
        final op = r['operation']?.toString() ?? '';
        final id = r['entityId']?.toString() ?? '';
        final status = r['status']?.toString() ?? '';
        final error =
            r['error']?.toString() ?? r['lastError']?.toString() ?? '';
        final when = isQueue
            ? (r['updatedAt']?.toString() ?? r['createdAt']?.toString() ?? '')
            : (r['finishedAt']?.toString() ?? '');
        final attempts = r['attempts'];

        return ListTile(
          dense: true,
          leading: Icon(_iconFor(status)),
          title: Text('$type · $op · $id'),
          subtitle: Text(
            [
              'Estado: $status',
              if (attempts != null) 'Intentos: $attempts',
              if (when.isNotEmpty) when,
              if (error.isNotEmpty) error,
            ].join('\n'),
          ),
          isThreeLine: error.isNotEmpty,
        );
      },
    );
  }

  IconData _iconFor(String status) {
    switch (status) {
      case 'success':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      case 'retry':
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'processing':
        return Icons.sync_rounded;
      default:
        return Icons.circle_outlined;
    }
  }
}
