/// Flight recorder: historial circular de eventos (sin crecer sin límite).
class SyncFlightEvent {
  SyncFlightEvent({
    required this.at,
    required this.kind,
    required this.message,
    this.opId,
    this.entityType,
    this.data = const {},
  });

  final DateTime at;
  final String kind;
  final String message;
  final String? opId;
  final String? entityType;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'kind': kind,
        'message': message,
        'opId': opId,
        'entityType': entityType,
        'data': data,
      };
}

class SyncFlightRecorder {
  SyncFlightRecorder._();
  static final SyncFlightRecorder instance = SyncFlightRecorder._();

  static const capacity = 1000;
  final List<SyncFlightEvent> _buf = [];

  void record({
    required String kind,
    required String message,
    String? opId,
    String? entityType,
    Map<String, dynamic>? data,
  }) {
    _buf.add(
      SyncFlightEvent(
        at: DateTime.now().toUtc(),
        kind: kind,
        message: message,
        opId: opId,
        entityType: entityType,
        data: data ?? const {},
      ),
    );
    while (_buf.length > capacity) {
      _buf.removeAt(0);
    }
  }

  List<SyncFlightEvent> last({int n = 100}) {
    if (_buf.length <= n) return List.unmodifiable(_buf);
    return List.unmodifiable(_buf.sublist(_buf.length - n));
  }

  List<Map<String, dynamic>> dumpJson({int n = 200}) =>
      last(n: n).map((e) => e.toJson()).toList();

  void resetForTests() => _buf.clear();
}
