/// Laboratorio de Certificación ERP — modelos e informe de fallos.
///
/// **No forma parte del Sync Engine.** Solo oráculo / escenarios / reportes.
library;

/// Nodo lógico del laboratorio.
enum CertLabNodeId { windows, android, firestore }

/// Entidades cubiertas por el oráculo.
enum CertLabEntity {
  producto,
  stock,
  precio,
  cliente,
  proveedor,
  compra,
  venta,
  remito,
  cuentaCorriente,
  movimiento,
  configuracion,
  stockOp,
}

/// Evento de laboratorio (trazabilidad del primer divergente).
class CertLabEvent {
  CertLabEvent({
    required this.seq,
    required this.at,
    required this.node,
    required this.kind,
    required this.entity,
    required this.payload,
  });

  final int seq;
  final DateTime at;
  final CertLabNodeId node;
  final String kind;
  final CertLabEntity entity;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'at': at.toIso8601String(),
        'node': node.name,
        'kind': kind,
        'entity': entity.name,
        'payload': payload,
      };
}

/// Snapshot comparable de un nodo (o de la nube).
class CertLabSnapshot {
  CertLabSnapshot({
    required this.node,
    required this.at,
    required this.counts,
    required this.stockByCodigo,
    required this.precioByCodigo,
    required this.saldoByCliente,
    required this.docIds,
    required this.stockOpIds,
    this.extra = const {},
  });

  final CertLabNodeId node;
  final DateTime at;
  final Map<String, int> counts;
  final Map<String, int> stockByCodigo;
  final Map<String, double> precioByCodigo;
  final Map<String, double> saldoByCliente;
  final Map<String, Set<String>> docIds;
  final Set<String> stockOpIds;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'node': node.name,
        'at': at.toIso8601String(),
        'counts': counts,
        'stockByCodigo': stockByCodigo,
        'precioByCodigo': precioByCodigo,
        'saldoByCliente': saldoByCliente,
        'docIds': {
          for (final e in docIds.entries) e.key: e.value.toList()..sort(),
        },
        'stockOpIds': (stockOpIds.toList()..sort()),
        'extra': extra,
      };
}

/// Hallazgo de divergencia (obligatorio en rojo).
class CertLabFailure {
  CertLabFailure({
    required this.scenarioId,
    required this.entity,
    required this.where,
    required this.message,
    this.firstDivergentEvent,
    this.expected,
    this.actual,
    this.file,
    this.clazz,
    this.method,
    this.firestorePath,
    this.sql,
    this.stackTrace,
    this.hint,
  });

  final String scenarioId;
  final CertLabEntity entity;
  final String where;
  final String message;
  final CertLabEvent? firstDivergentEvent;
  final Object? expected;
  final Object? actual;
  final String? file;
  final String? clazz;
  final String? method;
  final String? firestorePath;
  final String? sql;
  final String? stackTrace;
  final String? hint;

  Map<String, dynamic> toJson() => {
        'scenarioId': scenarioId,
        'entity': entity.name,
        'where': where,
        'message': message,
        'firstDivergentEvent': firstDivergentEvent?.toJson(),
        'expected': expected?.toString(),
        'actual': actual?.toString(),
        'file': file,
        'class': clazz,
        'method': method,
        'firestorePath': firestorePath,
        'sql': sql,
        'stackTrace': stackTrace,
        'hint': hint,
      };

  String toHuman() {
    final b = StringBuffer()
      ..writeln('FAIL scenario=$scenarioId entity=${entity.name}')
      ..writeln('  where: $where')
      ..writeln('  message: $message');
    if (firstDivergentEvent != null) {
      b.writeln(
        '  firstEvent: #${firstDivergentEvent!.seq} '
        '${firstDivergentEvent!.kind} @ ${firstDivergentEvent!.node.name}',
      );
    }
    if (expected != null) b.writeln('  expected: $expected');
    if (actual != null) b.writeln('  actual: $actual');
    if (file != null) b.writeln('  file: $file');
    if (clazz != null) b.writeln('  class: $clazz');
    if (method != null) b.writeln('  method: $method');
    if (firestorePath != null) b.writeln('  firestore: $firestorePath');
    if (sql != null) b.writeln('  sql: $sql');
    if (hint != null) b.writeln('  hint: $hint');
    if (stackTrace != null) b.writeln('  stack:\n$stackTrace');
    return b.toString();
  }
}

/// Resultado de un escenario.
class CertLabScenarioResult {
  CertLabScenarioResult({
    required this.scenarioId,
    required this.title,
    required this.ok,
    required this.durationMs,
    this.failure,
    this.notes = const [],
  });

  final String scenarioId;
  final String title;
  final bool ok;
  final int durationMs;
  final CertLabFailure? failure;
  final List<String> notes;

  Map<String, dynamic> toJson() => {
        'scenarioId': scenarioId,
        'title': title,
        'ok': ok,
        'durationMs': durationMs,
        'failure': failure?.toJson(),
        'notes': notes,
      };
}

/// Informe completo de una corrida de batería.
class CertLabReport {
  CertLabReport({
    required this.at,
    required this.commit,
    required this.ok,
    required this.results,
    required this.events,
  });

  final DateTime at;
  final String? commit;
  final bool ok;
  final List<CertLabScenarioResult> results;
  final List<CertLabEvent> events;

  int get passed => results.where((r) => r.ok).length;
  int get failed => results.where((r) => !r.ok).length;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'commit': commit,
        'ok': ok,
        'passed': passed,
        'failed': failed,
        'results': results.map((r) => r.toJson()).toList(),
        'events': events.map((e) => e.toJson()).toList(),
        'verdict': ok
            ? 'CERT_LAB_GREEN'
            : 'CERT_LAB_RED — prohibido merge / APK / EXE de sync',
      };

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Cert Lab Report')
      ..writeln()
      ..writeln('- at: ${at.toIso8601String()}')
      ..writeln('- commit: ${commit ?? '—'}')
      ..writeln('- verdict: ${ok ? 'GREEN' : 'RED'}')
      ..writeln('- passed/failed: $passed / $failed')
      ..writeln();
    for (final r in results) {
      b.writeln('## ${r.ok ? 'PASS' : 'FAIL'} ${r.scenarioId}');
      b.writeln('- ${r.title} (${r.durationMs} ms)');
      if (r.failure != null) {
        b.writeln('```');
        b.writeln(r.failure!.toHuman());
        b.writeln('```');
      }
      for (final n in r.notes) {
        b.writeln('- note: $n');
      }
      b.writeln();
    }
    return b.toString();
  }
}
