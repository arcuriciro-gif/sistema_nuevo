import 'package:flutter/material.dart';

import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../theme/module_app_bar.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final BackupService backupService = BackupService();
  final AutoBackupService autoBackup = AutoBackupService.instance;

  bool procesando = false;
  bool autoHabilitado = false;
  int autoIntervaloHoras = 24;
  DateTime? ultimoAutoBackup;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    autoHabilitado = await autoBackup.habilitado;
    autoIntervaloHoras = await autoBackup.intervaloHoras;
    ultimoAutoBackup = await autoBackup.ultimoBackup;
    if (mounted) setState(() {});
  }

  Future<void> exportarBackup() async {
    setState(() => procesando = true);
    try {
      await backupService.compartirBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup listo para compartir')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar backup: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => procesando = false);
      }
    }
  }

  Future<void> restaurarBackup() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: const Text(
          'Se validará el archivo (integrity check) antes de reemplazar la base. '
          'La app se debe reiniciar después de restaurar. ¿Querés continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => procesando = true);
    try {
      final ok = await backupService.restaurarBackup();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se seleccionó ningún archivo')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restaurado. Reiniciá la app.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al restaurar: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => procesando = false);
      }
    }
  }

  Future<void> _ejecutarAutoAhora() async {
    setState(() => procesando = true);
    try {
      await autoBackup.ejecutarAhora();
      ultimoAutoBackup = await autoBackup.ultimoBackup;
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup automático ejecutado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => procesando = false);
    }
  }

  String _formatFecha(DateTime? fecha) {
    if (fecha == null) return 'Nunca';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}  '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Backup'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Manual ──────────────────────────────────────────────────────
            const Text(
              'Backup manual',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: procesando ? null : exportarBackup,
                icon: const Icon(Icons.backup),
                label: const Text('Exportar / Compartir backup'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: procesando ? null : restaurarBackup,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar desde archivo'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'El backup es un archivo .db que podés guardar en Google Drive o compartir por WhatsApp.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Divider(height: 32),
            // ── Automático ──────────────────────────────────────────────────
            const Text(
              'Backup automático',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activar backup automático'),
              subtitle: const Text(
                'Guarda una copia local en segundo plano según el intervalo configurado.',
              ),
              value: autoHabilitado,
              onChanged: procesando
                  ? null
                  : (v) async {
                      await autoBackup.setHabilitado(v);
                      await _cargarConfig();
                    },
            ),
            if (autoHabilitado) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Intervalo: '),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: autoIntervaloHoras,
                    items: const [
                      DropdownMenuItem(value: 6, child: Text('Cada 6 horas')),
                      DropdownMenuItem(
                        value: 12,
                        child: Text('Cada 12 horas'),
                      ),
                      DropdownMenuItem(value: 24, child: Text('Cada 24 horas')),
                      DropdownMenuItem(value: 48, child: Text('Cada 2 días')),
                      DropdownMenuItem(
                        value: 168,
                        child: Text('Cada semana'),
                      ),
                    ],
                    onChanged: procesando
                        ? null
                        : (v) async {
                            if (v != null) {
                              await autoBackup.setIntervaloHoras(v);
                              await _cargarConfig();
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Último backup automático: ${_formatFecha(ultimoAutoBackup)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: procesando ? null : _ejecutarAutoAhora,
                icon: const Icon(Icons.schedule_rounded),
                label: const Text('Ejecutar ahora'),
              ),
            ],
            if (procesando) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

