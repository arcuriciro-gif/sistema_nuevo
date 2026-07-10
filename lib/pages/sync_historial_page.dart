import 'package:flutter/material.dart';

import '../core/sync/sync_queue_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final sync = SyncQueueService.instance;
    final cs = Theme.of(context).colorScheme;

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
                    subtitle: Text(
                      sync.lastError?.isNotEmpty == true
                          ? sync.lastError!
                          : sync.lastSuccessAt != null
                              ? 'Último OK: ${sync.lastSuccessAt!.toLocal()}'
                              : 'Sin envíos confirmados aún',
                    ),
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
        final error = r['error']?.toString() ??
            r['lastError']?.toString() ??
            '';
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
