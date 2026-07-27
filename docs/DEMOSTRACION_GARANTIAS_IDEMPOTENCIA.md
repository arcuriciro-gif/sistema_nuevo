# DEMOSTRACIÓN FORMAL — Garantías de idempotencia y consistencia de stock

**Producto:** Tata.Manager  
**Versión objetivo:** 1.4.7+75  
**Fecha:** 2026-07-27  
**Rama:** `cursor/demo-garantias-idempotencia-e44b`

---

## Enunciado

Para cualquier secuencia finita de:

- ventas, compras, remitos, ajustes;
- cierres inesperados (kill mid-path);
- reconexiones;
- reintentos y reordenamientos de la cola outbox / pull;

se cumplen:

| # | Garantía |
|---|----------|
| **G1** | Ninguna operación se aplica dos veces |
| **G2** | Ninguna operación se pierde |
| **G3** | Ningún ACK se emite antes de `status=applied` |
| **G4** | Ledger y proyección de stock permanecen consistentes |
| **G5** | El stock siempre puede reconstruirse únicamente desde el ledger |
| **G6** | El resultado final es independiente del orden de reintentos |

---

## Modelo

### Autoridades

| Capa | Autoridad |
|------|-----------|
| Local historial | `domain_events` + `inventory_ledger` (append-only) |
| Local proyección | `productos.stock` ← **solo** vía `InventoryLedgerService.applyInTxn` |
| Nube historial | `stock_ops/{opId}` con `status ∈ {pending_apply, claimed, applied}` |
| Nube proyección | `productos.stock` vía `FieldValue.increment` **una vez** por opId |
| Inbound producto | **nunca** pisa stock local |

### Identidad de operación

- Local: `event_id` (UNIQUE en `domain_events` / `inventory_ledger.event_id`)
- Cloud / peer: `opId = "${eventId}_${productoId}"` (estable, determinista)
- Outbox: `op_id = "stock_op:$opId"`

---

## Lemas y pruebas

### Lema L1 — Idempotencia local por `event_id` (G1 local)

**Hipótesis:** `applyInTxn` consulta `domain_events` por `event_id` y retorna `false` sin mutar si existe.

**Evidencia:** `inventory_ledger_service.dart` (early return) + UNIQUE en schema.

**Conclusión:** ∀ secuencia que repite el mismo `event_id`, la proyección cambia a lo sumo una vez.

### Lema L2 — Atomicidad ledger ⇔ outbox ⇔ applied-store (G2 local)

**Hipótesis:** En origen local, dentro de la **misma** TX SQLite:

1. insert `domain_events` + `inventory_ledger` + update `productos.stock`
2. `enqueueStockOpInTxn`
3. `StockOpsAppliedStore.markInTxn(origin=local)`

**Evidencia:** `applyInTxn` con `enqueueOutboundStockOps: true`.

**Conclusión:** Si el commit sobrevive al kill, la op **existe** en outbox. Si el kill es pre-commit, **nada** quedó parcial (rollback SQLite). No hay estado “ledger sí / outbox no”.

### Lema L3 — ACK ⇒ `status=applied` (G3)

**Hipótesis:**

1. `mayAckStockOp(cloudAppliedProven: false) ≡ false`
2. `_ejecutarStockOpOutbox` lanza si no hay `stockOpCloudApplied(opId)`
3. Payload vacío/inválido **lanza** (no return silencioso)
4. `ackStockOpsYaHechas` y `clearAllStockOpsOutbox` son **no-op**
5. `purgeStuckStockOps` solo ACK con `proveCloudApplied == true`

**Conclusión:** El caller `ack(opId)` solo corre tras return exitoso de `_ejecutarStockOpOutbox`, que exige proof. No hay camino de ACK ciego para stock_op.

### Lema L4 — Consistencia proyección (G4)

**Hipótesis:** En cada apply exitoso, `stock_after = stock_before + delta` se escribe en la misma TX que el UPDATE de proyección.

**Corolario:** `verificarProyeccion` / `StockIntegrityValidator`:

```
stock == first(stock_before) + Σ delta
```

si y solo si nadie escribió stock fuera del ledger (contrato de autoridad).

### Lema L5 — Reconstrucción (G5)

**Definición:** `reconstruirStock(id, stockInicial: base) = base + Σ delta`.

Tomando `base = stock_before` de la primera fila del ledger, G4 ⇒ reconstrucción = proyección.

Alta de producto: inserta stock 0 + ajuste ledger (no write absoluto). Peer: seed 0 + replay de stock_ops.

### Lema L6 — Conmutatividad de deltas distintos (G6)

Los deltas son enteros aditivos. Para un conjunto de opIds **distintos** aplicados a lo sumo una vez (G1):

```
stock_final = stock_0 + Σ_{op ∈ S} delta(op)
```

independiente del orden de S. Reintentos de opIds ya aplicados son no-ops (G1) ⇒ mismo resultado.

### Lema L7 — Cloud: `status=applied` terminal (G1 cloud)

`classifyStockOpCloud`: si `status == applied` → `appliedComplete` → `stockOpNeedsIncrement = false`.  
Reconciler solo escanea `pending_apply` / `claimed`.  
`ultimaStockOp` del producto **se ignora** (no prueba de ops históricas).

### Lema L8 — Cloud móvil: txn atómica (G1+G3 cloud fuerte)

`_ajustarStockEnTransaccion`: claim/increment/applied en una sola `runTransaction`.  
Dos writers concurrentes: uno gana; el otro ve `applied` y no-op.

### Lema L9 — Cloud Windows: claim + WriteBatch (G1 cloud)

Protocolo (`stock_ops_windows_apply_protocol.dart`):

1. Si `applied` → done  
2. Si `incrementApplied` → solo sellar `applied`  
3. Escribir `claim` propio; re-leer  
4. Si claim ≠ propio → `retryLater` (throw; outbox pending; **no ACK**)  
5. Si propio → **WriteBatch** `{product.increment, op.status=applied, incrementApplied=true}`

**Propiedad concurrente:** tras la fase de claim, a lo sumo un writer tiene `claim == nuestro` ⇒ a lo sumo un batch de increment. El perdedor reintenta y o bien ve `applied` / `incrementApplied`, o vuelve a competir.

**Batch atómico:** no existe estado durable “incrementó y status≠applied” observable entre commits (cierra la ventana que permitía ACK incompleto o doble retry).

---

## Teorema principal

Bajo el modelo de autoridad y los lemas L1–L9, para toda secuencia finita de eventos comerciales + fallos + reintentos:

1. **G1** por L1 + L7 + L8/L9  
2. **G2** por L2 + L3 (outbox no se ACK-ea prematuro) + reclaim de inflight  
3. **G3** por L3  
4. **G4** por L4  
5. **G5** por L5  
6. **G6** por L1 + L6  

∎

---

## Riesgos residuales (honestos)

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Poison `dead` tras `maxAttempts` sin cloud applied | G2 diferido hasta intervención | Panel técnico / `ackDeadStockOps` recuperable; poison no se reabre solo |
| Watermark HOL si `pending_apply` eterno en cursor | G2 delay | Soft pull reciente + reconciler; hold correcto > avance incorrecto |
| Windows: dos writers que pasan claim-check **antes** de que cualquiera escriba claim | G1 teórico | OpIds son origin-scoped; reconciler + outbox compiten raro; claim re-read reduce ventana |
| Watermark no-stock en otras colecciones | fuera de stock | Documentado en auditoría 1.4.5 |

Estos residuales **no** invalidan G1–G6 para el camino certificado (ledger local + ACK con proof + applied terminal). Invalidan solo la afirmación “cero bugs en todo el ERP”.

---

## Evidencia ejecutable (tests)

| Suite | Qué demuestra |
|-------|----------------|
| `test/garantias_g1_g3_politica_test.dart` | L7, L9 (claim), L3 (ACK policy) |
| `test/garantias_g1_g6_secuencia_adversa_test.dart` | G1–G6 locales: venta/compra/remito, crash post-commit, permutaciones |
| `test/forense_stock_ops_idempotencia_test.dart` | applied terminal |
| `test/forense_stock_stress_ledger_test.dart` | G1/G4 a escala |
| `test/sync_outbox_reclaim_dead_test.dart` | ACK ciego deshabilitado |

Correr:

```bash
flutter test \
  test/garantias_g1_g3_politica_test.dart \
  test/garantias_g1_g6_secuencia_adversa_test.dart \
  test/forense_stock_ops_idempotencia_test.dart \
  test/sync_outbox_reclaim_dead_test.dart
```

---

## Cambios de código que cierran huecos de la demostración

1. **Windows claim + WriteBatch** — elimina TOCTOU increment-antes-de-applied y doble increment por reconciler concurrente sin dueño de claim.  
2. **Payload vacío → throw** — elimina ACK silencioso (rompía G3).  
3. **`clearAllStockOpsOutbox` → no-op** — elimina ACK masivo ciego.
