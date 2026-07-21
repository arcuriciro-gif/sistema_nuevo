import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain_event.dart';

typedef DomainEventHandler = FutureOr<void> Function(DomainEvent event);

/// Event Bus interno in-process (Capacidad 3).
/// Desacopla módulos: documentos publican; ledgers/sync/audit escuchan.
class DomainEventBus {
  DomainEventBus._();
  static final DomainEventBus instance = DomainEventBus._();

  final Map<String, List<DomainEventHandler>> _handlers = {};
  final List<DomainEventHandler> _any = [];

  void subscribe(String type, DomainEventHandler handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  void subscribeAll(DomainEventHandler handler) {
    _any.add(handler);
  }

  Future<void> publish(DomainEvent event) async {
    final typed = List<DomainEventHandler>.from(_handlers[event.type] ?? const []);
    final all = List<DomainEventHandler>.from(_any);
    for (final h in [...typed, ...all]) {
      try {
        await h(event);
      } catch (e, st) {
        debugPrint('DomainEventBus handler error ${event.type}: $e\n$st');
        rethrow;
      }
    }
  }

  @visibleForTesting
  void resetForTests() {
    _handlers.clear();
    _any.clear();
  }
}
