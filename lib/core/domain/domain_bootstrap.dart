import 'package:flutter/foundation.dart';

import 'event_bus.dart';
import 'inventory_ledger_service.dart';
import 'money_ledger_service.dart';

/// Registra handlers de dominio una sola vez al arrancar la app.
class DomainBootstrap {
  DomainBootstrap._();
  static bool _done = false;

  static void ensureInitialized() {
    if (_done) return;
    _done = true;
    InventoryLedgerService.instance.registerHandlers();
    MoneyLedgerService.instance.registerHandlers();
  }

  @visibleForTesting
  static void resetForTests() {
    _done = false;
    DomainEventBus.instance.resetForTests();
    InventoryLedgerService.instance.resetForTests();
    MoneyLedgerService.instance.resetForTests();
  }
}
