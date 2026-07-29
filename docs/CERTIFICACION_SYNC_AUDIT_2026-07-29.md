# CERTIFICACIÓN TOTAL DEL MOTOR DE SYNC — AUDITORÍA (sin código)

| Campo | Valor |
|---|---|
| Fecha | 2026-07-29 |
| Rama auditada | `cursor/fix-stock-parity-e44b` @ `98e8508` (1.4.26+94) |
| Postura | **No se asume que el código sea correcto.** Se exige evidencia. |
| Entrega | **Solo auditoría + plan.** Sin cambios de producto en este documento. |
| Regla | Comprender → medir → instrumentar → probar → demostrar → **recién entonces** modificar. |

---

## 0. VEREDICTO

### **NO CERTIFICADO**

No se puede afirmar:

> Windows = Firestore = Android

para stock, ni para el ERP completo.

| Criterio de terminado (pedido) | Estado |
|---|---|
| Windows = Android = Firestore | **FALLA** (campo) |
| Sin diferencias de stock | **FALLA** (pruebq, 1127) |
| EXE estable horas con sync | **NO DEMOSTRADO** (freeze evita crash; no hay soak) |
| Sin pérdidas / duplicados / ops eternas | **PARCIAL lab** / **NO E2E** |
| Toda la matriz automática verde | **NO** |
| Evidencia reproducible por resultado | **NO** |

**Nivel actual:** motor con invariantes locales fuertes + sync multi-dispositivo **condicional / manual / asimétrico**.

**Nivel pedido:** ERP vendido, convergencia automática certificable.

La distancia entre ambos es estructural, no un “último bug”.

---

## 1. EVIDENCIA DE CAMPO (bloqueante)

Medición del usuario (2026-07-28/29), mismos productos, nube verde:

| SKU | Android | Windows | Δ |
|---|---:|---:|---:|
| `pruebq` | 33 | 43 | 10 |
| `1127` | 4 | −2 | 6 |

Observaciones simultáneas:

- Badge **Sincronizado** / nube verde con stock distinto.
- Panel: Pending 500 tras Benchmark lab (basura lab; remedado en 1.4.25).
- EXE se cerraba ~2 min → `freezeBackgroundForStability=true` (1.4.24).

**Interpretación (demostrada en código, no opinión):**

1. Autoridad de stock entre nodos = **`stock_ops`** (deltas), no `productos.stock` remoto (R6/R7).
2. Con freeze, Windows **no** tiene listeners ni soft-pull: **no baja** `stock_ops` solo.
3. “Sincronizado” = outbox local vacío / label estable ≠ paridad de ledger entre dispositivos.
4. Por construcción, **Windows ≠ Android** puede persistir hasta `Actualizar ahora` (y aún así, micro-rondas ≤40 ops/gesto).

Mientras freeze=true sin canal inbound automático seguro, **la certificación plena es imposible**.

---

## 2. ARQUITECTURA REAL (no la deseada)

```
Android                          Firestore                         Windows (freeze ON)
───────                          ─────────                         ───────────────────
ledger local ──push outbox──► stock_ops / docs ──?──►            outbox push OK
listeners + pull 45s ◄──────── stock_ops / docs                   inbound OFF
Actualizar ahora (agresivo)                                       Actualizar ahora
                                                                  = push + ≤40 apply
```

| Pieza | Archivo / símbolo | Rol real |
|---|---|---|
| Hub | `lib/core/sync/firestore_sync_service.dart` | Monolito start/pull/push/apply |
| Política Windows | `lib/core/sync/windows_sync_policy.dart` | freeze, budgets, soft-pull OFF |
| Outbox | `lib/core/sync/sync_outbox.dart` | pending→inflight→acked/dead |
| Lanes | `scheduler/sync_priority.dart` | L1..L4 |
| Ledger | `lib/core/domain/inventory_ledger_service.dart` | proyección local |
| Holds | `StockOpsPullHoldStore` | anti-HOL |
| Watermark | `sync_watermarks` / `pull_stock_ops_doc` | cursor + rewind one-shot |
| Badge | `shell_sync_badge.dart` | UI salud (engañosa hasta 1.4.26) |

### Verdad de stock

1. Local: `inventory_ledger` → proyecta `productos.stock`.
2. Nube entre dispositivos: `stock_ops/{opId}` (applied).
3. `productos/{codigo}.stock` en Firestore = proyección; **peers no la usan para convergencia**.

### Deuda activa (healers / workarounds)

No son “features”; son deuda que la certificación debe o eliminar o justificar:

1. `freezeBackgroundForStability=true`
2. Cuarentena post-login
3. `SyncAutoHealer` + reclaim/purge/recover dead
4. `forceClose` circuit en boot / Actualizar ahora
5. Rewinds watermark v142…v154 (one-shot prefs)
6. Hold store + sweeper
7. `ackLabBenchmarkGarbage`
8. Caps anti-crash (maxApply ≤2/4; histórico crash ≥50)
9. Windows stock sin txn (`_ajustarStockWindowsSafe`)
10. `repararProyeccionesDivergentes` post-manual

**Prohibición del brief:** no agregar más capas. Primero demostrar; luego **reducir** esta lista.

---

## 3. MATRIZ DE COBERTURA vs PEDIDO

Leyenda: **C** = covered lab · **P** = partial · **M** = missing · **F** = field fail

| Área | Estado | Evidencia / gap |
|---|---|---|
| Productos CRUD mientras sync | **P** | Aceptación/convergencia simulada; sin race 2 writers E2E |
| Stock venta/compra/remito/ajuste | **P** | Lab G1–G6 / capacidad6; **transferencia M** |
| Stock multi-dispositivo real | **F/M** | Campo falla; tests son twin-SQLite o aritmética |
| Clientes / Proveedores | **P** | Upsert lab; delete/conflicto 2 devices abierto (C2) |
| Ventas/Compras/Remitos offline | **P** | Offline enqueue lab; hop Firebase no automatizado |
| Concurrencia dual + kill + reconnect | **P/M** | Simulado; checklist C2 campo **sin check** |
| Stress 10k productos / 50k stock_ops sync | **M** | Ledger 10k local ≠ sync; bench “10k” clamp 500 |
| Perf CPU/RAM/Firestore R/W | **M** | Solo latencias claim locales |
| Fallos crash mid push/pull + red flaky | **P/M** | Mid-apply lab; no Firebase real |
| Validador Win=APK=Firestore automático | **M** | No existe harness E2E |
| Integridad orphans/FK/holds/watermark | **C** (lab) | Aceptación + residuales + hardening |
| EXE soak horas | **M** | Solo unit de política freeze |
| Benchmark lab | **C*** | Limpia basura (1.4.25); **no certifica hop** |

\*Lab verde **no** implica sync de campo (demostrado: Pending 500 + SLA lab OK).

Docs internos ya lo admitían:

- `docs/capacidades/C2_…`: **CERTIFICADA CONDICIONALMENTE**; checks de campo abiertos.
- `docs/AUDITORIA_CERTIFICACION_2026-07.md`: **No certificar** como ERP multi-dispositivo.

---

## 4. TOP 10 GAPS QUE BLOQUEAN CERTIFICACIÓN

1. **Sin triple-hop automatizado** Windows ↔ Firestore ↔ Android.
2. **freeze=true** elimina inbound Windows → convergencia no puede ser automática.
3. **Badge/health históricos mienten** (parcialmente corregido en copy 1.4.26; métrica de paridad ausente).
4. **`sync_stock_parity_campo_test`** no mide nodos reales.
5. **Sin soak EXE** (horas) con sync real.
6. **Sin stress sync** 10k SKU / 50k ops con prueba de no-pérdida.
7. **Sin métricas** Firestore R/W + CPU/RAM en CI.
8. **Checklist C2 campo** sin cerrar (kill mid-sync, 2 editors, 0 pérdida).
9. **Transferencia de stock** ausente en matriz.
10. **Healers acumulados** sin prueba de que no enmascaran pérdida (ACK/orphan/forceClose).

---

## 5. QUÉ SÍ ESTÁ DEMOSTRADO (lab)

Útil, insuficiente:

- Idempotencia ledger / no double-apply (G1) en tests.
- ACK stock con proof cloud en caminos instrumentados (G3/C6) — lab.
- Outbox reclaim / dead / backoff — unit.
- Anti-HOL holds + watermark policy — unit.
- FK remitos / orphans productos — forense lab.
- Presupuestos anti-crash Windows (maxApply techos) — unit.
- Cleanup Benchmark lab — unit (post 1.4.25).

**Ninguno de estos cierra el veredicto de campo.**

---

## 6. PLAN DE CERTIFICACIÓN (orden obligatorio)

### Fase 0 — Congelar el tren de fixes (ahora)

- **No** más PRs de “un SKU / un crash / un healer” como camino a certificación.
- PR #104 queda como **rama de estabilización de emergencia**, no como certificación.
- Cualquier cambio futuro exige: fallo reproducible + test que falle en rojo + causa raíz citada (archivo/método/línea).

### Fase 1 — Definir el oráculo (sin tocar motor)

Contrato único de paridad:

```
para cada entidad E, para cada nodo N ∈ {Win, Android, Firestore-proyección}:
  count(E,N) iguales
  para stock: Σ ledger(N,codigo) == stock(N,codigo)
  para cada codigo: stock(Win)==stock(Android)==proyección_derivable(Firestore stock_ops)
```

Entregable: especificación + queries SQL/Firestore del oráculo. **Cero cambios de sync.**

### Fase 2 — Instrumentación mínima (medir, no curar)

Solo telemetría ya existente o extensión **read-only**:

- Contadores: push/pull/apply/ack/fail, watermark cursor, holds, pending por tipo.
- Export JSON por corrida de piloto.
- Prohibido: nuevos schedulers/managers/caches.

### Fase 3 — Harness de certificación (tests primero)

Orden de construcción de evidencia:

1. **Emulator / proyecto piloto** Firebase dedicado (no producción `tata_stock` del cliente).
2. Runner que levanta **2 DBs** + aplica ops vía APIs de dominio + fuerza drain/pull **explícitos**.
3. Matriz reducida **P0** (abajo) hasta verde 10/10.
4. Ampliar a P1/P2.

No generar APK/EXE de “certificados” hasta P0 verde.

### Fase 4 — Matriz P0 (bloqueante comercial)

Mínimo para no mentir al comprador:

| ID | Caso | Pasa si |
|---|---|---|
| P0-1 | Venta en Android → stock Win | mismo stock codigo |
| P0-2 | Venta en Win → stock Android | mismo stock |
| P0-3 | Carga/ajuste stock ambos sentidos | igual |
| P0-4 | Remito ambos sentidos | igual |
| P0-5 | Offline Android + reconnect | 0 pérdida, igual |
| P0-6 | Offline Win + reconnect | 0 pérdida, igual |
| P0-7 | Kill mid-push + reopen | cola recupera, igual |
| P0-8 | 100 stock_ops ráfaga | Win=Android=Σ ops |
| P0-9 | Tenant mismatch detectado | no “Sincronizado” falso |
| P0-10 | EXE 30 min idle+sync | sin cierre solo |

Si **uno** falla: DETENER. Causa raíz. Sin parches.

### Fase 5 — Decisión de arquitectura (solo con P0 rojo o verde)

Solo **después** de P0:

- Si freeze impide P0-1/2: **rediseñar inbound Windows** con presupuesto duro medido (no reactivar soft-pull a ciegas).
- Si healers ocultan pérdida: **quitar** healer y arreglar camino feliz.
- Optimizar **solo** con métricas de Fase 2.

### Fase 6 — P1/P2 (completitud del brief)

Clientes/proveedores/conflictos, compras, deletes, 1k/10k, soak 4–8 h, perf Firestore, transferencia, CC saldos, etc.  
Misma regla: rojo → causa raíz → fix justificado.

---

## 7. REGLA DE REGRESIÓN (aceptada)

Antes de cerrar cualquier PR de sync:

1. Toda la batería P0 (y la que ya exista en CI) en verde.
2. Si una falla: **no merge, no APK, no EXE “certificado”.**
3. Artefacto: JSON oráculo + log de corrida + commit SHA.

El Benchmark lab **no** cuenta como P0.

---

## 8. RESPUESTA DIRECTA AL BRIEF

| Pedido | Respuesta |
|---|---|
| Motor estable/rápido/confiable hoy | **No demostrado** a nivel vendible multi-dispositivo |
| ¿Más fixes aislados? | **No.** Congelar. Auditar → oráculo → P0 |
| ¿Empezar de cero el ERP? | **No.** El dominio/ledger lab sirve; el **canal Windows inbound + cert E2E** no |
| ¿Cuándo escribir código? | Tras Fase 1–3 definidas y primer rojo P0 reproducible |
| ¿PR #104? | Emergencia estabilidad (freeze/lab/badge); **no es certificación** |

---

## 9. PRÓXIMO PASO ÚNICO (siguiente turno)

**Sin modificar el motor:**

1. Redactar el **oráculo de paridad** (queries + criterios exactos) como spec ejecutable.
2. Inventariar comandos CI existentes que puedan alimentar P0.
3. Proponer harness mínimo (1 archivo de test de integración) que **falle hoy** en P0-1 bajo freeze — evidencia roja antes de cualquier fix.

Hasta que exista ese rojo reproducible, **cualquier cambio de sync es especulativo.**
