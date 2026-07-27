# CERTIFICACIÓN POR INVARIANTES — Sync Engine + Stock

**Producto:** Tata.Manager  
**Versión:** 1.4.8+76  
**Fecha:** 2026-07-27  
**Rama:** `cursor/certificacion-invariantes-stock-e44b`

> Objetivo: demostrar que las propiedades fundamentales permanecen verdaderas  
> bajo cualquier secuencia válida de eventos — no aumentar % de tests.

---

## 1. Garantías formales (Fase 1)

### Universo de eventos

```
E ::= LocalApply | LocalReplay | RemoteApply
    | UploadAttempt | AckIfApplied
    | GoOffline | GoOnline
    | CrashBeforeCommit | CrashAfterCommit
    | PoisonOutbox
```

### Predicados de estado

| Símbolo | Significado |
|---------|-------------|
| `Applied(op)` | op en `domain_events` / `stock_ops_applied` / cloud `status=applied` |
| `Outbox(op)` | fila `sync_outbox` pending\|inflight |
| `Ledger(p)` | filas `inventory_ledger` del producto p |
| `Proj(p)` | `productos.stock` |
| `Cloud(p)` | `tenants/.../productos/{codigo}.stock` |
| `Σδ(p)` | suma de deltas del ledger de p |
| `base(p)` | `stock_before` de la primera fila ledger de p |

### G1 — Una operación nunca se aplica dos veces

∀ op, ∀ secuencias S:  
`count(apply(op) que mutan proyección en S) ≤ 1`

### G2 — Una operación nunca se pierde

∀ LocalApply exitoso (commit SQLite):  
`∃ Outbox(cloudOpId) ∨ ∃ cloud status=applied`  
(salvo rechazo explícito pre-commit).

### G3 — Nunca ACK antes de `applied`

∀ transición outbox → `acked` para `entity_type=stock_op`:  
`cloudStatus(opId) = applied` en el instante previo al ACK.

### G4 — Stock reconstruible solo desde el ledger

∀ producto p con al menos una fila ledger:  
`Proj(p) = base(p) + Σδ(p)`  
y `reconstruirStock(p, base(p)) = Proj(p)`.

### G5 — Idempotencia ante reintentos

∀ secuencia S y ∀ S' obtenida insertando replays/retries de ops ya en S:  
`stock_final(S) = stock_final(S')`.

### G6 — Convergencia SQLite ↔ Firestore tras sync exitosa

Definición de *sync exitosa* para stock:  
`outbox stock_op pending∪inflight = ∅` ∧ toda op origen en cloud `applied`.

Entonces: ∀ producto p con código válido:  
`Proj_sqlite(p) = Cloud(p)`  
(eventual, tras pull del peer; en origen tras upload+ack).

### G7 — Consistencia local proyección ↔ ledger (auxiliar)

Igual que G4 en el dispositivo; se separa para distinguir  
“reconstruible” (G4) de “no divergir en caliente” (G7).

---

## 2. Mapeo a código (Fase 2)

| G | Archivos / métodos | Tablas | TX | Tipo de enforcement |
|---|-------------------|--------|----|---------------------|
| **G1** | `inventory_ledger_service.applyInTxn` L81–91; UNIQUE `domain_events`/`inventory_ledger`; `classifyStockOpCloud`; `_ajustarStockEnTransaccion`; Windows claim+batch; `stock_ops_applied` | domain_events, inventory_ledger, stock_ops_applied, stock_ops | SQLite + Firestore txn/batch | **Estructural** (UNIQUE + txn) |
| **G2** | `applyInTxn` enqueue+mark misma TX; `enqueueStockOpInTxn`; reclaim inflight; throw si codigo vacío | sync_outbox, stock_ops_applied | SQLite atómica | **Estructural** + rechazo |
| **G3** | `_ejecutarStockOpOutbox` throw sin proof / payload inválido; `stockOpCloudApplied`; purge con proof; `clearAll`/`ackYaHechas` no-op | sync_outbox, stock_ops | ACK post-throw gate | **Estructural** en path upload; `mayAckStockOp` solo tests → **parcial** |
| **G4** | `reconstruirStock`, `verificarProyeccion`, `StockIntegrityValidator`; alta seed 0; inbound stock strip | inventory_ledger, productos | — | **Estructural** si hay ledger; **NO** para legacy sin ledger |
| **G5** | G1 + deltas aditivos + stock_op no coalescible | — | — | **Estructural** vía G1 |
| **G6** | upload→applied→ack; pull→`applyRemoteStockOp`; no absolute inbound; WM hold | stock_ops, productos, watermarks | eventual | **Parcial** (eventual; dead/HOL) |
| **G7** | misma TX update stock + ledger insert | inventory_ledger, productos | SQLite | **Estructural** |

### Marcadas NO demostradas solo por convención

- `mayAckStockOp` **no** está cableado en el pump de producción (G3 depende de throws).
- G6 no es una transacción distribuida: es convergencia eventual bajo definición de sync exitosa.

---

## 3. Contraejemplos (Fase 3)

| Ataque | Garantía | Resultado | Evidencia |
|--------|----------|-----------|-----------|
| Doble retry mismo eventId | G1 | **Resistido** | `test/cert/contraejemplos_gx_test.dart` |
| Replay remoto mismo opId | G1 | **Resistido** | idem |
| Claim Windows perdedor | G1 | **Resistido** (protocolo) | policy test |
| Crash after commit | G2 | **Resistido** (outbox en TX) | contraejemplo G2 |
| Codigo vacío + enqueue | G2 | **Antes: pérdida silenciosa** → **ahora rechazo TX** | fix `applyInTxn` + test |
| Poison dead maxAttempts | G2/G6 | **Residual** — ledger OK, cloud diferido | documentado |
| ACK sin applied (modelo) | G3 | **Resistido** | ref model |
| clearAllStockOpsOutbox | G3 | **Resistido** (no-op) | outbox test |
| Legacy sin ledger | G4 | **Contraejemplo** — no reconstruible | test residual |
| Permutaciones + retry | G5 | **Resistido** | modelo + PBT |
| Offline→online drain | G6 | **Resistido** en modelo | contraejemplo G6 |
| WM adelantado / pending | G6 | **HOLD** (no avance) | pull policy |
| Absolute `incluirStockAbsoluto` | G6 | **Residual** — puede pelear con increments | mapeo §2 |

---

## 4. Property-based testing (Fase 4)

| Suite | Secuencias | Propiedad |
|-------|------------|-----------|
| `test/cert/property_based_stock_test.dart` modelo | **2000** | proyección consistente; G6 si outbox vacía |
| idem + poison | **500** | ledger consistente aunque cloud diverge |
| ref vs SQLite local | **800** | `stock_real == stock_ref` |
| ref vs SQLite peer | **400** | idem para RemoteApply + retries |

Generador: `lib/core/cert/stock_sequence_generator.dart`  
(ventas, compras, remitos, ajustes, retry, crash, offline/online, replay, ACK, delay vía offline).

Si falla: se imprime la secuencia completa (`encodeSequence`) para reproducción.

---

## 5. Modelo de referencia (Fase 5)

| Artefacto | Rol |
|-----------|-----|
| `lib/core/cert/stock_reference_model.dart` | Estado inmutable + `reduce` |
| `lib/core/cert/stock_real_harness.dart` | Aplica mismos eventos locales a SQLite |
| `lib/core/cert/stock_sequence_generator.dart` | Generador + encoder |

Misma secuencia → ref y real → comparación automática de stocks.

---

## 6. Cobertura por garantía (Fase 6)

| G | Estado | Evidencia | Límites |
|---|--------|-----------|---------|
| **G1** | **Demostrada** (local + protocolo cloud) | UNIQUE + PBT + contraejemplos; txn móvil; claim Windows | Residual teórico TOCTOU claim simultáneo pre-write |
| **G2** | **Demostrada parcialmente** | TX atómica + rechazo codigo vacío | Poison dead; HOL watermark (delay≠loss si soft-pull vive) |
| **G3** | **Demostrada** en path stock_op upload | throw sin proof; no-ops ciegos | `mayAckStockOp` no cableado; `ack()` genérico existe |
| **G4** | **Demostrada parcialmente** | validator + PBT proyección | **No** para productos legacy sin ledger |
| **G5** | **Demostrada** (bajo G1) | PBT permutaciones/retries | Nuevos eventIds = ops nuevas (correcto) |
| **G6** | **Demostrada parcialmente** | modelo drain+ack; WM hold | Eventual; dead outbox; absolute seed; Windows catch-up diferido |
| **G7** | **Demostrada** (local post-ledger) | verificarProyeccion en PBT | Misma limitación legacy que G4 |

---

## 7. Cambios realizados en esta certificación

1. **Fix G2:** `applyInTxn` rechaza TX si producto sin `codigo` al encolar (antes: ledger sí / outbox no).
2. **Modelo de referencia** + generador + harness real.
3. **Suite contraejemplos** deliberados por Gx.
4. **PBT** ≥ 3700 secuencias (modelo + real).
5. Este informe.

(Base previa 1.4.7: Windows claim+batch, payload vacío→throw, clearAll no-op.)

---

## 8. Riesgos remanentes

1. Outbox `dead` poison → G6 diferida hasta intervención humana.  
2. Productos legacy sin ledger → G4 no aplica.  
3. `incluirStockAbsoluto` en seed cloud → posible pelea con increments.  
4. G6 es eventual, no commit distribuido.  
5. Watermark HOL bajo `pending_apply` eterno.  
6. `ack(opId)` genérico no tipado — disciplina de call-site.

---

## 9. Cómo reproducir evidencia

```bash
flutter test test/cert/contraejemplos_gx_test.dart
flutter test test/cert/property_based_stock_test.dart
flutter test \
  test/garantias_g1_g3_politica_test.dart \
  test/garantias_g1_g6_secuencia_adversa_test.dart \
  test/forense_stock_ops_idempotencia_test.dart
```

---

## 10. Veredicto

El sistema **no** se declara “correcto en todo el ERP”.  
Se declara:

- **G1, G5, G7:** demostradas con evidencia estructural + PBT + contraejemplos fallidos.  
- **G3:** demostrada en el camino stock_op (upload/ACK).  
- **G2, G4, G6:** demostradas parcialmente, con residuales explícitos y un contraejemplo histórico (codigo vacío) **cerrado** en esta rama.

Eso es certificación por invariantes con evidencia, no un % de cobertura de líneas.
