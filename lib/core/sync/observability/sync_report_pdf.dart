import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera PDF de benchmark / certificación Sync Engine 2.1.
class SyncReportPdf {
  SyncReportPdf._();

  static Future<File> writeBenchmarkPdf({
    required String path,
    required Map<String, dynamic> report,
  }) async {
    final doc = pw.Document();
    final scenarios = (report['scenarios'] as Map?) ?? const {};
    final dash = (report['dashboard'] as Map?) ?? const {};
    final sla = (dash['sla'] as Map?) ?? const {};

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Sync Engine 2.1 — Benchmark',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text('At: ${report['at'] ?? ''}'),
          pw.Text('Note: ${report['note'] ?? ''}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'SLA compliance: ${((sla['overallCompliancePct'] as num?) ?? 0).toStringAsFixed(1)}%',
          ),
          pw.SizedBox(height: 12),
          ...scenarios.entries.map((e) {
            final m = e.value is Map ? e.value as Map : {'value': e.value};
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  e.key,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                ...m.entries.map((kv) => pw.Text('  ${kv.key}: ${kv.value}')),
                pw.SizedBox(height: 8),
              ],
            );
          }),
          pw.SizedBox(height: 16),
          pw.Text(
            'Cuellos de botella: ver P95/P99 vs SLA 2000ms en criticos. '
            'Este PDF es evidencia de laboratorio (outbox local); hop remoto requiere piloto.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(bytes));
    return file;
  }

  static Future<File> writeCertificationPdf({
    required String path,
    required Map<String, dynamic> report,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Informe de certificación Sync Engine 2.1',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Text('Versión: ${report['version']}+${report['buildNumber']}'),
          pw.Text('Schema: ${report['schemaVersion']}'),
          pw.Text('Commit: ${report['commit'] ?? 'n/a'}'),
          pw.Text('Inicio: ${report['startedAt']}'),
          pw.Text('Fin: ${report['finishedAt']}'),
          pw.SizedBox(height: 8),
          pw.Text(
            'Veredicto: ${report['verdict']}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Entorno: ${report['environment']}'),
          pw.SizedBox(height: 12),
          pw.Text(
            'NOTA: CERTIFICADO PARA PRODUCCION requiere evidencias de campo '
            'EXE/APK/Firestore (P50/P95 hop remoto). Este informe es lab/piloto.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
    final bytes = await doc.save();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(Uint8List.fromList(bytes));
    return file;
  }
}
