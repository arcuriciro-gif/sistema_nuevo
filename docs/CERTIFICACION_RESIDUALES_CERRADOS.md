# CERTIFICACIÓN STOCK — Cierre de residuales (1.4.9+77)

**Rama:** `cursor/cerrar-residuales-cert-stock-e44b`  
**Base:** certificación invariantes 1.4.8+76  

---

## Residuales cerrados

### 1. Poison / dead queue — GESTIONADA

| Mecanismo | Archivo |
|-----------|---------|
| `listDeadStockOps` | `sync_outbox.dart` |
| `forceRequeuePoisonStockOps` | reopen explícito con grace |
| `recoverDeadStockOps(proveCloudApplied)` | ACK si applied; else requeue/force |
| Auto-healer | llama force requeue poison |
| Boot Windows | `recoverDeadStockOps` en lugar de solo `ackDeadStockOps` |
| Alarma C8 | `outbox_dead_stock_op` |

**Evidencia:** `test/cert/residuales_cerrados_test.dart` R1.

### 2. Histórico → ledger — MIGRADO

| Mecanismo | Archivo |
|-----------|---------|
| `LegacyLedgerMigration.seedMissing` | snapshot `base=0, δ=stock` sin mutar proyección ni cloud |
| Idempotente | `inv:ajuste:legacy_seed:{id}` |
| C8 scan | corre seed antes de validar; alarma `legacy_without_ledger` si queda |
| Boot Windows | seed lote 300 |

**Evidencia:** R2 — stock intacto, `verificarProyeccion`, 2ª corrida = 0.

### 3. G6 convergencia eventual — DEFINIDA Y DEMOSTRADA

Definición formal: `lib/core/cert/g6_eventual_consistency.dart`

**Quiescencia:** online ∧ outbox vacía ∧ dead sin applied = 0 ∧ holds = 0 ∧ orígenes `applied`.

**G6:** en quiescencia, `S_local(p) = C(p)` ∀p.

**Evidencia:** `evaluateG6` + 300 secuencias modelo drain → `ok` (R3).

### 4. Watermark HOL — RESUELTO

| Mecanismo | Archivo |
|-----------|---------|
| Tabla `stock_ops_pull_holds` | schema **v38** |
| Park blockers → advance | `shouldAdvanceStockOpsWatermark(blockersParkedInHolds: true)` |
| Sweeper | `_sweepStockOpsHolds` tras pull + soft lane |
| Soft pull Windows | sweep adicional |

Sin park: **no** avance (no se pierden ops).  
Con park: avance + reintento aparte.

**Evidencia:** R4 + piloto `pending_apply parked SÍ avanza`.

---

## Cobertura actualizada

| G | Estado |
|---|--------|
| G1 | Demostrada |
| G2 | **Demostrada** (dead gestionada; reject codigo vacío) |
| G3 | Demostrada |
| G4 | **Demostrada** (legacy seed) |
| G5 | Demostrada |
| G6 | **Demostrada** (definición + PBT quiescencia) |
| G7 | Demostrada |

---

## Cómo verificar

```bash
flutter test test/cert/residuales_cerrados_test.dart
flutter test test/stock_ops_integridad_piloto_test.dart
flutter test test/cert/contraejemplos_gx_test.dart
```

---

## Veredicto

Los cuatro residuales que impedían declarar el módulo **certificado** están cerrados con código estructural + evidencia ejecutable.  
Riesgo operativo restante: poison que vuelve a fallar tras force-requeue requiere intervención de datos (payload corrupto) — visible por alarma C8, no silencioso.
