import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/sync/sync_queue_service.dart';
import '../pages/sync_historial_page.dart';

/// Chip compacto del estado de sincronización (tap → historial).
class SyncStatusChip extends StatefulWidget {
  const SyncStatusChip({
    super.key,
    this.dense = false,
    this.dark = false,
  });

  final bool dense;
  final bool dark;

  @override
  State<SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends State<SyncStatusChip> {
  void _onSync() {
    if (!mounted) return;
    // Evita rebuild en medio del frame (rompe Tooltip/InheritedWidget).
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    SyncQueueService.instance.addListener(_onSync);
  }

  @override
  void dispose() {
    SyncQueueService.instance.removeListener(_onSync);
    super.dispose();
  }

  Color _color(SyncUiStatus status) {
    switch (status) {
      case SyncUiStatus.sincronizado:
        return const Color(0xFF16A34A);
      case SyncUiStatus.pendiente:
        return const Color(0xFFD97706);
      case SyncUiStatus.sinConexion:
        return const Color(0xFF6B7280);
      case SyncUiStatus.error:
        return const Color(0xFFDC2626);
      case SyncUiStatus.procesando:
        return const Color(0xFF2563EB);
    }
  }

  IconData _icon(SyncUiStatus status) {
    switch (status) {
      case SyncUiStatus.sincronizado:
        return Icons.cloud_done_rounded;
      case SyncUiStatus.pendiente:
        return Icons.cloud_upload_rounded;
      case SyncUiStatus.sinConexion:
        return Icons.cloud_off_rounded;
      case SyncUiStatus.error:
        return Icons.sync_problem_rounded;
      case SyncUiStatus.procesando:
        return Icons.sync_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncQueueService.instance;
    final status = sync.uiStatus;
    final color = _color(status);
    final fg = widget.dark ? Colors.white : color;
    final bg = widget.dark
        ? color.withValues(alpha: 0.22)
        : color.withValues(alpha: 0.12);
    final dense = widget.dense;

    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: sync.uiDetalle,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SyncHistorialPage()),
          );
        },
        onLongPress: () async {
          await sync.reintentarFallidos();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reintentando sincronización…'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10,
            vertical: dense ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == SyncUiStatus.procesando)
                SizedBox(
                  width: dense ? 12 : 14,
                  height: dense ? 14 : 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              else
                Icon(_icon(status), size: dense ? 14 : 16, color: fg),
              SizedBox(width: dense ? 4 : 6),
              Text(
                sync.uiLabel,
                style: TextStyle(
                  color: fg,
                  fontSize: dense ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
