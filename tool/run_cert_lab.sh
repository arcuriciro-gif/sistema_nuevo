#!/usr/bin/env bash
# Gate local de comprobación del sistema pyme (reemplaza Cert Lab legacy).
set -euo pipefail
cd "$(dirname "$0")/.."
echo "== Windows sync / anti-crash =="
flutter test \
  test/windows_sync_fast_safe_test.dart \
  test/windows_anti_crash_invariants_test.dart
echo "== Sync outbox + stock =="
flutter test \
  test/sync_outbox_pending_breakdown_test.dart \
  test/sync_outbox_reclaim_dead_test.dart \
  test/sync_stock_convergence_p0_test.dart \
  test/soft_delete_stock_lww_test.dart \
  test/garantias_g1_g6_secuencia_adversa_test.dart
echo "== Dominio local =="
flutter test \
  test/pagos_parciales_remito_test.dart \
  test/ui_modo_menu_test.dart \
  test/capacidad3_dominio_test.dart
echo "== Suite completa =="
flutter test --exclude-tags cert-lab
echo "OK — comprobación del sistema ejecutada."
