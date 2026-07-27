import 'dart:async';

import '../../../models/producto.dart';
import '../../../services/producto_service.dart';
import 'import_checkpoint_store.dart';

/// Resultado parcial / final de un lote de importación.
class ImportBatchResult {
  ImportBatchResult({
    required this.job,
    required this.done,
    required this.cancelled,
  });

  final ImportCheckpoint job;
  final bool done;
  final bool cancelled;
}

/// Fila a aplicar: campos opcionales respetan mapeo (no pisan con 0 vacío).
class ImportRowSpec {
  ImportRowSpec({
    required this.codigo,
    this.descripcion,
    this.marca,
    this.categoria,
    this.proveedor,
    this.costo,
    this.precio,
    this.stock,
  });

  final String codigo;
  final String? descripcion;
  final String? marca;
  final String? categoria;
  final String? proveedor;
  final double? costo;
  final double? precio;
  final int? stock;
}

/// Importación masiva por lotes con checkpoint durable.
///
/// - Nunca reinicia desde cero si hay job `running`.
/// - Yield entre lotes para no congelar UI.
/// - Sync de productos en lane **background** (no bloquea ventas).
class ImportBatchRunner {
  ImportBatchRunner({
    ProductoService? productoService,
    ImportCheckpointStore? store,
    this.batchSize = 50,
  })  : _svc = productoService ?? ProductoService(),
        _store = store ?? ImportCheckpointStore.instance;

  final ProductoService _svc;
  final ImportCheckpointStore _store;
  final int batchSize;

  bool _cancelRequested = false;

  void requestCancel() => _cancelRequested = true;

  /// Reanuda job running o crea uno nuevo.
  Future<ImportCheckpoint> ensureJob({
    required String sourceName,
    required int totalRows,
    Map<String, int?>? mapping,
  }) async {
    final running = await _store.loadRunning();
    if (running != null &&
        running.sourceName == sourceName &&
        running.totalRows == totalRows) {
      return running;
    }
    if (running != null) {
      // Otro archivo: cancelar el anterior para no mezclar.
      await _store.markCancelled(running.jobId);
    }
    return _store.startJob(
      sourceName: sourceName,
      totalRows: totalRows,
      mapping: mapping,
    );
  }

  /// Procesa filas desde [job.nextRowIndex] en lotes.
  Future<ImportBatchResult> run({
    required ImportCheckpoint job,
    required FutureOr<ImportRowSpec?> Function(int index) rowBuilder,
    void Function(ImportCheckpoint progress)? onProgress,
  }) async {
    _cancelRequested = false;
    var current = job;
    while (current.nextRowIndex < current.totalRows) {
      if (_cancelRequested) {
        await _store.markCancelled(current.jobId);
        current = ImportCheckpoint(
          jobId: current.jobId,
          sourceName: current.sourceName,
          totalRows: current.totalRows,
          nextRowIndex: current.nextRowIndex,
          imported: current.imported,
          updated: current.updated,
          skipped: current.skipped,
          status: 'cancelled',
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          mappingJson: current.mappingJson,
        );
        return ImportBatchResult(job: current, done: false, cancelled: true);
      }

      final end =
          (current.nextRowIndex + batchSize).clamp(0, current.totalRows);
      var imported = current.imported;
      var updated = current.updated;
      var skipped = current.skipped;

      for (var i = current.nextRowIndex; i < end; i++) {
        final spec = await rowBuilder(i);
        if (spec == null || spec.codigo.trim().isEmpty) {
          skipped++;
          continue;
        }
        final codigo = spec.codigo.trim();
        final existente = await _svc.buscarPorCodigo(codigo);
        if (existente == null) {
          await _svc.insertar(
            Producto(
              codigo: codigo,
              descripcion: (spec.descripcion ?? '').isNotEmpty
                  ? spec.descripcion!
                  : codigo,
              marca: spec.marca ?? '',
              categoria: spec.categoria ?? '',
              proveedor: spec.proveedor ?? '',
              ubicacion: '',
              stock: spec.stock ?? 0,
              costo: spec.costo ?? 0,
              precio: spec.precio ?? 0,
              observaciones: '',
              foto: '',
            ),
            syncBackground: true,
          );
          imported++;
        } else {
          final actualizado = existente.copyWith(
            descripcion: (spec.descripcion ?? '').isNotEmpty
                ? spec.descripcion!
                : existente.descripcion,
            marca: (spec.marca ?? '').isNotEmpty
                ? spec.marca!
                : existente.marca,
            categoria: (spec.categoria ?? '').isNotEmpty
                ? spec.categoria!
                : existente.categoria,
            proveedor: (spec.proveedor ?? '').isNotEmpty
                ? spec.proveedor!
                : existente.proveedor,
            costo: spec.costo ?? existente.costo,
            precio: spec.precio ?? existente.precio,
            stock: spec.stock ?? existente.stock,
          );
          await _svc.actualizar(actualizado, syncBackground: true);
          updated++;
        }
      }

      current = ImportCheckpoint(
        jobId: current.jobId,
        sourceName: current.sourceName,
        totalRows: current.totalRows,
        nextRowIndex: end,
        imported: imported,
        updated: updated,
        skipped: skipped,
        status: 'running',
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        mappingJson: current.mappingJson,
      );
      await _store.saveProgress(current);
      onProgress?.call(current);

      // Yield: deja respirar UI + scheduler crítico.
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    await _store.markDone(current.jobId);
    current = ImportCheckpoint(
      jobId: current.jobId,
      sourceName: current.sourceName,
      totalRows: current.totalRows,
      nextRowIndex: current.nextRowIndex,
      imported: current.imported,
      updated: current.updated,
      skipped: current.skipped,
      status: 'done',
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      mappingJson: current.mappingJson,
    );
    return ImportBatchResult(job: current, done: true, cancelled: false);
  }
}
