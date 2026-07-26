# Auditoría Final — Tata.Manager Release Candidate

| Campo | Valor |
|---|---|
| Fecha | 2026-07-26 |
| Versión auditada | `1.2.53+61` (rama con PRs #78–#81) |
| Alcance | Código fuente + reglas Firebase + evidencia de campo reciente |
| Método | Revisión adversaria multi-especialista (sin asumir que “compila = funciona”) |
| Confianza | **72%** (código leído; sin harness dual-device instrumentado en esta corrida) |

---

## 1. Resumen Ejecutivo

Tata.Manager tiene una base de dominio local seria (ledger de inventario + outbox + tests de matriz en dispositivo único), pero **la sincronización multi-dispositivo y la cuenta corriente remota no son certificables** en el estado actual.

Evidencia de campo (mismo día): `.exe` con **546 pendientes** (542 productos), **0 en curso**, **intentos 0**, texto “arranque 45s” — la cola no avanzaba. Eso no es un bug cosmético: es pérdida operativa de convergencia.

Hay escenarios demostrables en código donde:

* el stock en nube puede quedarse sin incrementar tras un crash Windows;
* anular un remito en el dispositivo **seguidor** no revierte stock;
* anular/restaurar en el seguidor puede **duplicar** movimiento;
* la cuenta corriente del APK no refleja remitos/ventas bajados de la nube;
* el watermark de `stock_ops` puede saltar ops si el producto aún no existe localmente.

**Veredicto oficial (una opción):**  
# APTO SOLO PARA PILOTO CONTROLADO

**No** apto como ERP principal multi-dispositivo sin restricciones.  
Piloto aceptable solo con reglas operativas duras (ver §8).

---

## 2. Hallazgos

### 🔴 Crítico

#### C1 — Windows `stock_ops` no atómico: crash tras claim = stock perdido en nube
* **Descripción:** `_ajustarStockWindowsSafe` escribe `stock_ops/{opId}` con `status: applied` y **después** hace `FieldValue.increment`. Si el proceso muere o hay timeout entre ambos, el reintento ve `exists` y retorna OK; el outbox hace ACK.
* **Impacto:** stock de nube e APK incorrectos; el negocio vende/compra con verdad falsa.
* **Probabilidad:** media-alta en Windows (timeouts 8s + historial de crashes).
* **Repro:** crear remito/compra en `.exe` → matar proceso justo tras crear `stock_ops` → reabrir → outbox limpio, producto en Firestore sin incremento.
* **Evidencia:** `lib/repositories/firestore_producto_repository.dart:217–243`. `reconcilizarStockOpsPendientes` solo mira `pending_apply`/`claimed`, no `applied` huérfanos.
* **Solución:** marcar `pending_apply` hasta confirmar increment; o Cloud Function atómica; reconciliar `applied` sin `ultimaStockOp`.

#### C2 — Anular remito/venta en dispositivo seguidor no revierte stock
* **Descripción:** inbound `stock_ops` se graba con `documentType: stock_op`. Anular consulta `ledgerNet` por `remito`/`venta` → net 0 → no revierte.
* **Impacto:** stock queda descontado tras anulación en el celular/PC que no originó el doc.
* **Probabilidad:** alta en uso PC+APK real.
* **Repro:** PC crea remito −5 → APK sync → APK anula → stock APK sigue −5.
* **Evidencia:** `inventory_ledger_service.dart:275–276`; `remito_service.dart:472–473`; sync apply remitos sin eventos de inventario.
* **Solución:** atribuir ops inbound al documento comercial, o al anular detectar ops relacionadas / forzar reverse por ítems.

#### C3 — Anular→restaurar en seguidor = doble salida de stock
* **Descripción:** restaurar re-aplica entrega si hay líneas, sin exigir net documentario previo.
* **Impacto:** stock 2× descontado; posible stock negativo o inventarios imposibles.
* **Probabilidad:** media (sigue a C2).
* **Repro:** escenario C2 + restaurar en APK.
* **Evidencia:** `remito_service.dart:615–637`; patrón similar en venta/compra reopen.
* **Solución:** gate restore con net/ledger; o emitir stock_op de reverse al anular en origen y aplicar en todos.

#### C4 — Watermark `stock_ops` avanza aunque se salteen ops
* **Descripción:** si el producto no existe local, la op se `continue` pero el cursor `afterAt` igual avanza.
* **Impacto:** movimiento perdido para siempre en ese dispositivo (salvo red de seguridad “recientes” en APK; Windows no la tiene igual).
* **Probabilidad:** media (alta de productos / orden de sync).
* **Repro:** op de stock llega antes que el producto → watermark pasa → producto llega después → stock nunca aplica.
* **Evidencia:** `_pullStockOpsRemotas` / `_aplicarStockOpsItems` en `firestore_sync_service.dart`.
* **Solución:** no avanzar watermark si hubo skips; cola de “ops pendientes de producto”.

#### C5 — `startAfter([at])` sin tie-break por docId
* **Descripción:** ops con mismo `at` pueden quedar fuera de página.
* **Impacto:** pérdida silenciosa de deltas.
* **Probabilidad:** baja-media en ráfagas.
* **Evidencia:** `firestore_producto_repository.dart:324–329`.
* **Solución:** `orderBy('at').orderBy(FieldPath.documentId)` + cursor compuesto.

#### C6 — Outbox ACK de stock “stuck/dead” sin prueba de apply en nube
* **Descripción:** `purgeStuckStockOps` / `ackDeadStockOps` limpian badge sin verificar incremento remoto.
* **Impacto:** UI “sana” con stock incorrecto.
* **Probabilidad:** media (fue la mitigación anti-crash Windows).
* **Evidencia:** `sync_outbox.dart:510–558`; llamadas en boot/pump Windows.
* **Solución:** ACK solo tras read-back de `ultimaStockOp` o status real `applied`+increment.

#### C7 — Cuenta corriente no se reconcilia al bajar ventas/remitos
* **Descripción:** apply remoto inserta docs; no escribe money_ledger ni `recalcularSaldoCliente`.
* **Impacto:** APK/PC con remitos visibles y saldo cliente 0 (o al revés).
* **Probabilidad:** alta.
* **Repro:** remito a CC en PC → APK ve remito, `clientes.saldo` no cambia.
* **Evidencia:** `_aplicarRemitosRemotos` / `_aplicarVentasRemotas` sin money path.
* **Solución:** sincronizar money ledger / recalc saldo tras apply; o CC solo en origen hasta replay.

#### C8 — Cola Windows puede quedar sin drenar (evidencia de campo)
* **Descripción:** 546 pendientes, intentos 0, “arranque 45s”. Causas encadenadas: cuarentena, pump que no priorizaba productos, return silencioso si Auth no listo.
* **Impacto:** PC y APK operan con catálogos/ventas distintos.
* **Probabilidad:** observada en producción del dueño.
* **Evidencia:** captura 2026-07-26; fixes parciales en #80/#81 (`1.2.52–53`).
* **Solución:** mantener drain priorizado + cuarentena corta + nunca skip silencioso del pump; métrica “intentos>0 en <60s”.

---

### 🟠 Alto

#### A1 — Bootstrap / migración watermark puede doble-aplicar stock
Producto nuevo acepta stock absoluto remoto; luego se reaplican `stock_ops` históricos. Migración `at_v2` reinicia cursor.
* **Evidencia:** merge productos + `_pullStockOpsRemotas`; `stock_ops_watermark.dart`.
* **Solución:** seed stock 0 + replay, o watermark “now” sin replay completo sobre stock ya proyectado.

#### A2 — `_stockOpsHechas` truncado a 500
Pierde memoria de ops viejas; con reset de watermark re-aplica.
* **Evidencia:** persistencia hechas en `firestore_sync_service.dart`.

#### A3 — Anular remoto por upsert de `estado` no ejecuta side-effects
El seguidor ve `anulado` sin reverse stock/CC.
* **Evidencia:** apply remitos/ventas solo copia campos.

#### A4 — `actualizarEstadoPago` inventa cobros sin money_ledger / pagos
Saldo doc vs ledger divergen; anular no limpia.
* **Evidencia:** `venta_service.dart:386–420`; remitos UI marcar cobrado.

#### A5 — Remito + Factura pueden cobrar CC dos veces (stock una)
Política anti-doble stock no bloquea doble deuda.
* **Evidencia:** remito money + `cuenta_corriente_service` factura.

#### A6 — Reglas Firestore: cualquier miembro no `solo_lectura` escribe ops
Permisos de módulo son solo cliente. Empleado puede tumbar catálogo/ventas en nube.
* **Evidencia:** `firestore.rules` `canWriteOps`.

#### A7 — `admin123` recovery ON por defecto; recovery code en SharedPreferences
Acceso físico ≈ admin local.
* **Evidencia:** `admin_access_policy.dart:26–32`.

#### A8 — Listeners Android 10k productos + ausentes `.get()` completo
Riesgo ANR/OOM; sync al login pesada.
* **Evidencia:** `watchSnapshots(limit: 10000)`; `_subirClientesAusentesEnNube`.

#### A9 — Backup/restore cierra DB en caliente; backup sin cifrar
Crash/corrupción + exposición de hashes/datos.
* **Evidencia:** `backup_service.dart`.

#### A10 — Token WhatsApp con XOR (no Keystore)
* **Evidencia:** `secure_local_store.dart`.

---

### 🟡 Medio

#### M1 — LWW producto solo por timestamp; ACK outbox tras skip
Pérdida de precios/costos ante skew de reloj.

#### M2 — Remito/venta upload pisa `actualizadoEn=now` (last-writer clobber items/pagos)

#### M3 — Tombstone remito: reverse por qty de ítems ≠ net; no borra pagos

#### M4 — Ítems remotos omitidos si falta producto → doc incompleto

#### M5 — Fotos: Storage off en Windows (by design); branding path no está en `storage.rules`

#### M6 — God-object `FirestoreSyncService` (~4.3k LOC) + dual write (upload inmediato + outbox)

#### M7 — Rotación APK mitigada (`isDesktopShellLayout` + cache); residual recrear páginas

#### M8 — Integridad automática alinea stock, no CC; enmascara drift money si saldo≈0

---

### 🟢 Bajo

#### B1 — Asimetrías UX (remito anulado con `saldoPendiente` residual)
#### B2 — Menú básico/completo solo UI (bien documentado)
#### B3 — Tests de sync cubren helpers/outbox, no harness dual-device E2E

---

## 3. Riesgos operativos

| Riesgo | Nivel | Comentario |
|---|---|---|
| Pérdida de datos | **Alto** | C1, C4, C5, C6, C8 |
| Corrupción / estados imposibles | **Alto** | C2, C3, A1 |
| Pérdida / error de stock | **Crítico** | C1–C6, A1 |
| Error cuenta corriente | **Alto** | C7, A3–A5 |
| Sync rota / divergencia | **Crítico** | C8 + todo C* |
| Caídas (.exe / APK) | **Medio-Alto** | mitigado pero no cerrado; PDF/backup/listeners |

---

## 4. Estado por módulo

| Módulo | Estado | Nota |
|---|---|---|
| Productos | 🟠 | Local OK; sync LWW/cola/fotos frágiles |
| Clientes | 🟠 | Sync doc OK; saldo CC no confiable cross-device |
| Proveedores | 🟡 | Menos crítico; misma cola outbox |
| Compras | 🟠 | Local TX razonable; reopen/sync riesgos |
| Ventas | 🟠 | Local OK; pago/estadoPago y sync CC rotos |
| Remitos | 🔴 | Anular/restaurar cross-device peligrosos |
| Facturación | 🟡 | Stock policy OK; CC puede doblar con remito |
| Cuenta corriente | 🔴 | No converge por sync; atajos de cobro |
| Inventario | 🔴 | Ledger local sólido; nube/Windows/seguidor no |
| Sincronización | 🔴 | Prioridad máxima; no certificable aún |
| Usuarios / permisos | 🟠 | UI sí; rules nube demasiado abiertas |
| Configuración | 🟡 | Opt-in nube; branding Storage mismatch |
| Backup | 🟠 | Restore sin quiesce; sin cifrado |
| Panel técnico | 🟢 | Útil para ver pending/dead |

---

## 5. Rendimiento

| Carga | ¿Soporta? | Justificación |
|---|---|---|
| 10 usuarios | Parcial | Un tenant con 1–2 escritores activos; listeners Android ya pesan |
| 50 usuarios | **No** | Rules + listeners + outbox no estánen a escala |
| 100 usuarios | **No** | Sin partición, sin backend de aplicación |
| 10.000 productos | Límite | UI `obtenerTodos()` sin paginar; watch 10k |
| 100.000 productos | **No** | Memoria + Firestore snapshots |
| 1.000.000 movimientos | **No** | Soft-pull Windows maxApply 8; watermark frágil |

Cuellos: `FirestoreSyncService` monolítico, listeners Android, catch-up 2000 IDs/ciclo, listas UI full-scan.

---

## 6. Seguridad

| Área | Evaluación |
|---|---|
| Auth local | Aceptable; recovery `admin123` default = riesgo |
| Auth Firebase | Funcional; huella no amarra secreto |
| Autorización | **Cliente-only** para módulos; rules no reflejan matriz |
| Firestore rules | Membresía sí; ops demasiado permisivas; tenant update sin constraint |
| Storage rules | Sin `branding/`; `misc` amplio |
| Secretos locales | XOR + prefs; backups en claro |
| Biometría | Soft-gate (PIN del teléfono basta) |

---

## 7. Arquitectura

**Adecuada como base de ERP chico offline-first**, incorrecta aún como sistema multi-dispositivo de verdad única.

Fortalezas:

* Ledger local + domain events idempotentes en TX (dispositivo origen).
* Outbox durable.
* Separación stock absoluto remoto vs proyección local (R6/R7) bien intencionada.

Debilidades estructurales:

* Dual authority (ledger local vs `stock_ops` vs `productos.stock`).
* Side-effects de anular/cobrar no viajan como eventos de dominio en sync.
* God-service de sync + dual write.
* Mitigaciones Windows (no-txn, purge ACK, quarantine) priorizan “no crashear” sobre “no mentir el stock”.

Para ERP comercial serio hace falta: eventos de dominio sync-first (stock + money), apply atómico en nube, y reglas que reflejen roles reales.

---

## 8. Veredicto Final

# APTO SOLO PARA PILOTO CONTROLADO

### Condiciones obligatorias del piloto
1. **Un solo dispositivo escribe stock/CC crítico** (ideal: solo `.exe`), o anular/restaurar **solo en el origen**.
2. Operador mira el badge: pendientes deben bajar; si “intentos 0” > 2 min → no operar.
3. No confiar en saldos CC del APK hasta ver cobro/recalc local.
4. Backup diario offline; restore solo con app cerrada/quiesce.
5. Desactivar recovery `admin123` en campo; no compartir DB.
6. Catálogo < ~5–8k productos hasta paginar UI/listeners.
7. Build mínimo: **1.2.53+61** (fixes cola/arranque); re-validar en campo.

### Por qué no “APTO PARA PRODUCCIÓN”
Existen escenarios **demostrados en código** de pérdida/doble aplicación de stock y CC incorrecta entre dispositivos. Eso invalida uso como ERP principal sin supervisión.

### Por qué no “NO APTO” absoluto
En **un solo dispositivo**, flujos create→anular→restaurar de remito/venta/compra estánen tests de matriz y TX locales. Hay valor operativo real si se acota el multi-dispositivo.

### Confianza de la auditoría: **72%**

### No verificable en esta corrida (requiere prueba de campo)
1. Tasa real de timeouts Windows en `windows_safe`.
2. Densidad de `at` duplicados en Firestore productivo.
3. Si ya hubo doble-apply post-migración `at_v2` en tenants vivos.
4. Drift money_ledger vs `clientes.saldo` en DB real.
5. Reglas desplegadas == `firestore.rules` del repo.
6. E2E instrumentado PC↔APK (anular, compra, cobro, kill mid-sync).
7. Carga 10k productos en hardware del cliente.
8. Que #81 elimine definitivamente “arranque eterno” en su PC.

### Pruebas reales mínimas antes de liberar producción multi-dispositivo
| # | Prueba | Criterio de pase |
|---|---|---|
| T1 | PC remito −N → APK stock −N < 60s | Igualdad exacta |
| T2 | APK anula remito sync → ambos stock +N | Igualdad; sin doble |
| T3 | Kill `.exe` mid stock_op ×20 | 0 ops `applied` sin increment |
| T4 | Remito CC PC → saldo APK | Saldo igual |
| T5 | Cola 500 productos | intentos>0 en <60s; cola ↓ |
| T6 | Offline 10 ventas + reconnect | 0 pérdida / 0 dup |
| T7 | Edición concurrente precio PC+APK | Resultado definido documentado |
| T8 | Restore backup | App quieta; datos íntegros |

---

## Apéndice — Referencias de código clave

* `lib/repositories/firestore_producto_repository.dart` — Windows safe stock  
* `lib/core/domain/inventory_ledger_service.dart` — inbound `documentType: stock_op`  
* `lib/services/remito_service.dart` — anular/restaurar  
* `lib/core/sync/firestore_sync_service.dart` — pump, catch-up, apply docs  
* `lib/core/sync/sync_outbox.dart` — purge/ACK  
* `firestore.rules` / `storage.rules`  
* `lib/core/security/admin_access_policy.dart`  
* Evidencia de campo: cola 546 / intentos 0 / arranque 45s (2026-07-26)

---

*Fin del informe. No suavizado a propósito: el sistema puede ayudar al negocio hoy en piloto acotado; no puede garantizar integridad multi-dispositivo como ERP principal.*
