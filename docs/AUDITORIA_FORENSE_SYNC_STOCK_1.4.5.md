# AUDITORÍA FORENSE SYNC ENGINE + STOCK — Tata.Manager 1.4.5+73

Fecha: 2026-07-27  
Rama: `cursor/sync-engine-forensic-rebuild-e44b`

## 1. Modelo de autoridad (verificado)

| Capa | Autoridad |
|------|-----------|
| Local proyección | `productos.stock` ← solo vía `InventoryLedgerService.applyInTxn` |
| Local historial | `inventory_ledger` append-only + `domain_events` |
| Nube stock | `stock_ops/{opId}` (status por op) + `FieldValue.increment` en producto |
| Nube producto.stock | cache derivado; inbound **nunca** pisa proyección local |

## 2. Bugs P0 encontrados y corregidos

### P0-1 — Idempotencia cloud rota (`ultimaStockOp`)
- **Causa:** `classifyStockOpCloud` trataba `status=applied` + `ultimaStockOp≠opId` como incompleto → re-increment.
- **Evidencia:** `stock_ops_windows_policy.dart`, `reconcilizarStockOpsPendientes` escaneaba `applied`.
- **Fix:** `status=applied` es **terminal** por opId. Reconciler solo `pending_apply`/`claimed`.
- **Archivos:** `stock_ops_windows_policy.dart`, `firestore_producto_repository.dart`

### P0-2 — ACK outbox sin prueba en nube
- **Causa:** `ackStockOpsYaHechas(_stockOpsHechas)` + marca hechas **antes** del write cloud.
- **Fix:** `ackStockOpsYaHechas` → no-op. ACK solo tras `stockOpCloudApplied(opId)` (`status=applied`).
- **Archivos:** `sync_outbox.dart`, `firestore_sync_service.dart`

### P0-3 — Ledger commit ≠ outbox enqueue (no atómico)
- **Causa:** `enqueueCloudAfterApply` post-commit; kill mid-path → op perdida.
- **Fix:** `enqueueStockOpInTxn` + `stock_ops_applied` en la **misma TX** que el ledger.
- **Archivos:** `inventory_ledger_service.dart`, `sync_outbox.dart`, schema v37

### P0-4 — Self-echo volátil (prefs cap 500)
- **Causa:** `_stockOpsHechas` SharedPreferences; rewind 14d reaplicaba ops locales.
- **Fix:** tabla durable `stock_ops_applied` (origin local|remote).
- **Archivos:** `stock_ops_applied_store.dart`, `database_helper.dart` v37

### P0-5 — Windows lost-claim → return success → ACK
- **Fix:** si claim perdido y status≠applied → `StateError` (outbox queda pending).
- **Archivos:** `firestore_producto_repository.dart`

### P0-6 — Fallback create: exists pending → return sin increment
- **Fix:** si existe y no applied → throw (no ACK).
- **Archivos:** `firestore_producto_repository.dart`

## 3. Bugs P1/P2 corregidos o mitigados

| ID | Issue | Fix |
|----|-------|-----|
| P1 | Dead stock_op requeue storm (`attempts=0`) | Requeue sin reset; poison si `attempts>=max` |
| P2 | Integrity scan silent UPDATE stock | Ahora emite `stockProjection` alarm; no muta |
| P1 | Product seed double-count | Ya en 1.4.4 (seed=0); conservado |

## 4. Riesgos remanentes (honestos)

1. **Watermark global HOL** si un `pending_apply` eterno pincha el cursor — mitigated by recent pull + reconciler; ideal: per-op cursor table (no en este corte).
2. **`_pullPaginaPorDocId` avanza watermark antes de apply** (clientes/ventas/…) — riesgo pérdida docs no-stock; stock_ops path ya hold-correct.
3. **Outbox ACK sin claim generation** en upserts coalesced — no stock_op específico.
4. **Windows sin Firestore transactions** — camino safe + prueba applied; no ACID cloud perfecto.
5. **Escala 500k productos / 2M movimientos** — no ejecutable en CI; stress local 10k movimientos PASS.
6. **FCM push** (comunicacio­nes app cerrada) sigue requiriendo deploy Cloud Functions (rama previa).

## 5. Pruebas ejecutadas

| Suite | Resultado |
|-------|-----------|
| `forense_stock_ops_idempotencia_test` | PASS |
| `stock_ops_integridad_piloto_test` | PASS (updated) |
| `forense_stock_stress_ledger_test` (10k mov) | PASS |
| `windows_sync_fast_safe_test` | PASS |
| `capacidad8_reconciliacion_test` | PASS (alarma proyección) |

## 6. Validador

`StockIntegrityValidator`: para cada producto con ledger  
`stock == stock_before[first] + SUM(delta)`  
Si difiere ≥1: reporta `primerEventId`, `ultimoEventId`, delta.

## 7. Benchmark / consumo

| Métrica | Antes (cualitativo) | Después |
|---------|---------------------|---------|
| Doble increment post-reconcile | posible (P0-1) | imposible si status=applied |
| Lost ACK EXE→APK | posible (P0-2) | bloqueado sin cloud proof |
| Kill mid-commit stock cloud | op perdida (P0-3) | outbox en misma TX |
| CI stress 10k ledger | N/A | ~segundos, proyección OK |

CPU/RAM/Firestore cuantitativo de campo: requiere EXE↔APK hop; no medido en este entorno cloud.

## 8. Conclusión

Los caminos que **duplicaban o perdían stock** por diseño incorrecto de idempotencia/ACK/atomicidad fueron reemplazados por reglas estructurales.  
No se garantiza “cero bugs en todo el ERP” (watermarks no-stock, coalesced upserts, escala 2M).  
Sí se garantiza: **una stock_op applied no se re-incrementa**; **no hay ACK sin status=applied**; **outbox stock nace en la TX del ledger**.
