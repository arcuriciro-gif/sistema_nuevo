# Informe CTO — Simplificación del ERP Tata.Manager

**Fecha:** 2026-07-30  
**Versión analizada:** `1.4.30+88` (rama de trabajo previa) / `main` al momento del análisis  
**Alcance:** análisis completo. **Sin cambios de código.**  
**Misión:** convertir este ERP en un sistema simple, estable, rápido y fácil de mantener para una pyme de venta de suelas.

---

## Resumen ejecutivo

El proyecto tiene **~68.000 líneas Dart** en `lib/`. De eso:

| Área | LOC aprox. | ¿Aporta al objetivo? |
|------|-----------:|----------------------|
| Páginas / UI | 27.500 | Parcial — menú con 36 entradas; el núcleo cabría en ~12 |
| Sync | 11.700 | Sí el concepto; **no** el 70% de la maquinaria |
| Services | 11.700 | Parcial — AFIP stub, CRM, WhatsApp fuera de scope |
| Cert Lab | 3.600 | No — harness de laboratorio |
| Scheduler + Observability sync | ~2.800 | No en producción de campo |
| WhatsApp plugin | ~1.200 | No imprescindible para vender suelas |
| Domain (ledger, eventos) | 1.100 | Sí — núcleo de stock |
| Database helper | 1.700 | Sí, pero monolito |

**Veredicto:** el producto que el dueño necesita ya existe en el núcleo (productos, factura B, remito, compras, stock, precios, fotos, comparador, offline→cola→nube). Alrededor hay capas acumuladas por crashes de Windows, certificaciones, stubs fiscales y features de “ERP enterprise” que **no ayudan a vender más fácil**.

La sincronización **sí es necesaria** (PC + varios Android, offline). Lo que sobra es el motor 2.0: freeze, 4 pumps, soft-pull, turbo, adaptive, healer, lab, colas legacy duplicadas, rewinds de watermark.

**Objetivo de tamaño:** bajar el runtime de sync de ~12k LOC a algo del orden de **2–3k** (outbox + push/pull + stock_ops + ledger), y el menú de **36** a **~15** entradas visibles.

---

## Scope de producto (única brújula)

### Debe quedar

- Productos: ver, buscar, fotos, stock, precios, proveedor, listas  
- Ventas: Factura B, Remito, descuento automático de stock  
- Compras: registrar, actualizar stock/costos/listas  
- Stock idéntico en todos los dispositivos, inmediato tras venta/compra/remito  
- Precios que se reflejen solos en PC y Androids  
- Fotos multi-dispositivo  
- Comparador simple (proveedor, costo, precio, margen, diferencia)  
- Offline + cola simple + sync automático al recuperar Internet  

### No debe quedar (explícito del dueño)

AFIP, CAE, facturación electrónica, controladores fiscales, impuestos complejos, multi-moneda, contabilidad.

---

# 1. Código innecesario

## 1.1 Muerto seguro (eliminar ya — Fase 1)

| Path | Evidencia | LOC |
|------|-----------|----:|
| `lib/pages/calculadora_page.dart` | 0 imports / no menú / no push | ~272 |
| `lib/pages/ventas_totales_page.dart` | 0 imports; sustituida por `VentasPage` + filtros | ~544 |
| `lib/services/app_icon_build_service.dart` | 0 usos; branding usa `BrandingService` | ~bajo |
| `lib/core/sync/windows_sync_policy.dart` → `outboxDrainPlan` | Definido, nadie lo llama | — |
| `lib/core/sync/watermark_hardening.dart` | Re-export sin valor | 5 |
| `cupertino_icons` en `pubspec.yaml` | Sin usos en `lib/` | dep |

## 1.2 Fuera de scope de producto (candidatos fuertes a eliminar)

### AFIP / CAE (stub que además bloquea ventas)

| Path | Nota |
|------|------|
| `lib/services/afip_service.dart` | Stub explícito: no autoriza CAE; si AFIP está “activado” **bloquea** confirmar factura |
| UI en `documentos_config_page.dart`, `venta_factura_page.dart`, `configuracion_page.dart` | Entrada “Numeración y AFIP/ARCA” |
| Campos `estadoAfip` / `cae` / `caeVencimiento` en modelo/sync | Complejidad sin valor |

**Acción:** sacar activación AFIP y el stub. Dejar Factura B como documento interno con numeración local. Numeración sí; AFIP no.

### Cert Lab (~3.600 LOC en `lib/` + tests espejo)

| Path | Nota |
|------|------|
| `lib/core/cert/lab/**` (~14 archivos) | 0 refs desde pages/services; solo tests |
| `lib/core/cert/stock_*.dart`, `g6_eventual_consistency.dart` | Solo tests |
| `test/cert/**` | Espejo del lab |
| `lib/core/sync/observability/sync_{stress,benchmark,certification}_runner.dart`, `sync_report_pdf.dart` | Lab de sync empaquetable en runtime |

**Acción:** sacar del árbol de producción (mover a `tool/` / package `dev`, o archivar). No debe viajar en el EXE/APK.

### WhatsApp Business (~1.900+ LOC si se cuenta UI + plugin + plantillas)

| Path | Nota |
|------|------|
| `lib/pages/whatsapp_business_page.dart` | Menú |
| `lib/plugins/whatsapp/**` | API Meta / catálogo |
| `lib/services/whatsapp_plantillas_service.dart` | Plantillas |

**Acción:** si no vende más fácil hoy → menú off + código fuera del release. Deeplink `wa.me` simple en clientes puede quedar sin el plugin Business.

### CRM Lite (4 servicios + página, sin sync real)

| Path | Nota |
|------|------|
| `crm_lite_page.dart` | Menú “Seguimiento” |
| `crm_lite_service`, `crm_seguimiento_service`, `crm_automations_service`, `crm_reminder_service` | Solo local |

**Acción:** candidato a podar. No está en la lista “debe poder”.

## 1.3 Duplicaciones / solapes

| Qué | Dónde | Acción |
|-----|-------|--------|
| Colas legacy prefs + `SyncOutbox` SQLite | `_colaClientes/…/_colaStockOps` en `firestore_sync_service` | Una sola cola: outbox |
| Dedup stock_ops doble | `_stockOpsHechas` (prefs) + `StockOpsAppliedStore` (SQLite) | Solo store |
| 4 timers de sync | `_outboxPump`, `_pullPump`, `_stockOpsPullPump`, `_criticalConvergencePump` | Un pump |
| Soft-pull + pump stock_ops + critical convergence | Mismos datos por 3 caminos | Un camino |
| Scheduler 2.0 (Turbo/Adaptive/EntityLock/metrics history) | `lib/core/sync/scheduler/**` | Claim fijo L1/L2 |
| `StockIntegrityValidator` vs `IntegrityReconcileService` | Validator **0 usos en lib/** | Fusionar o borrar validator |
| Writers de historial de precios | `HistorialPrecioService` + inserts en producto/compra/comparador | Un writer |
| Decode Excel | `CsvService` + `importacion_page` | Un parser |
| Catálogo menú duplicado | `shell_menu_catalog.dart` **debe** mantenerse en sync con `_items` de `main_shell.dart` | Una sola fuente |
| Hub Importaciones + ítem “Importar Productos” + Comparador otra vez | Menú 36 entradas | Un solo atajo |
| Dashboard + Inteligencia Comercial + Inicio | 3 pantallas analíticas | Una |

## 1.4 Pantallas / menú fuera del núcleo (ocultar o eliminar)

Menú actual: **36** entradas. Núcleo solicitado cabe en ~15:

**KEEP visible:** Inicio · Productos · Stock · Listas · Comparador · Venta rápida / Factura B · Remitos · Compras · Clientes · Proveedores · Configuración · Usuarios · Backup · (Papelera / Categorías / Importar según uso real)

**Candidatos a ocultar/eliminar del menú (no necesariamente borrar archivo día 1):**

- WhatsApp Business, Comunicaciones/Chat interno  
- CRM Seguimiento  
- Inteligencia Comercial (solapa Dashboard)  
- Presupuestos / Entregas / Tickets (si no se usan en la pyme; Factura B + Remito bastan)  
- Archivo PDF, Etiquetas, Auditoría, Primeros pasos, Manual (Manual puede quedar en Config)  
- Panel técnico (KEEP para soporte, pero solo admin y sin lab)  
- Importaciones hub vs Importar (dejar uno)

## 1.5 Dependencias

| Dep | Veredicto |
|-----|-----------|
| `cupertino_icons` | Eliminar |
| `audioplayers` | Solo alertas chat → eliminar si se va chat |
| `mobile_scanner` | KEEP si el scanner se usa en mostrador |
| Resto Firebase / sqflite / excel / pdf | KEEP |

## 1.6 Docs / binarios ruidosos

- Auditorías versionadas (`AUDITORIA_*`, `FIX_EXE_*`, checklists 1.2.x / 1.4.x) → archivar o una sola carpeta `docs/archive/`  
- Manual PDF triplicado (~14 MB × 3) → un solo asset  

---

# 2. Arquitectura

## 2.1 Qué hay hoy (simplificado)

```
UI (57 pages / 36 menú)
  → Services (38)
    → SQLite (DatabaseHelper monolito ~1700 LOC)
    → Domain events → InventoryLedger / MoneyLedger
    → SyncOutbox
  → FirestoreSyncService (~5800 LOC god-object)
    → 4 pumps + soft-pull + freeze Windows + scheduler 2.0 + observability
    → Firestore + Storage
```

## 2.2 Qué es demasiado complejo

1. **`FirestoreSyncService` (5.800 LOC)** — un solo archivo concentra boot, cuarentena, listeners, soft-pull, stock_ops, Actualizar ahora, apply de todas las entidades, colas legacy, rewind, convergence. Imposible de mantener.  
2. **Stack Windows de mitigación** — `freezeBackgroundForStability`, soft-pull, hardCap, critical convergence, watermark rewind v142→v154. Cada crash agregó una capa; ninguna reemplazó a la anterior.  
3. **Sync Engine 2.0** — prioridades L1–L4, turbo, adaptive batch, entity locks, metrics history, auto-healer, circuit breaker, SLA, flight recorder, cert PDF. Para una pyme de suelas es enterprise theatre.  
4. **Doble autoridad de stock mal comunicada** — el diseño correcto es `stock_ops → ledger → proyección`. Pero coexisten prefs legacy, holds, applied store, hechas set, y política freeze que **mata** el inbound de stock en Windows.  
5. **Menú / shell** — `main_shell.dart` ~1.600 LOC + catálogo duplicado.  
6. **Tres capas analíticas** — Inicio / Dashboard / Inteligencia Comercial.  
7. **Cert Lab dentro de `lib/`** — código de prueba en el mismo árbol que el producto.

## 2.3 Qué fusionar / qué capas pueden desaparecer

| Fusionar / desaparecer | En |
|------------------------|-----|
| Colas prefs → solo `SyncOutbox` | Sync |
| 4 pumps → 1 loop: push outbox + pull stock_ops + pull docs | Sync |
| Turbo/Adaptive/EntityLock/metrics → claim fijo | Sync |
| Soft-pull Windows + freeze + critical → una política: throttle + hardCap, listeners mínimos o pull periódico único | Sync |
| AFIP stub → fuera; Factura B = doc interno | Ventas |
| Money ledger / CC | KEEP si la pyme cobra en cuenta; no es “contabilidad” |
| Domain event bus | KEEP si es delgado; no crear otra abstracción |
| Repos abstractos poco usados | OK dejar; no expandir |
| `StockIntegrityValidator` → reconcile del panel | Integrity |
| Dashboard ∩ Inteligencia ∩ Inicio → una home | UI |
| CRM + WhatsApp plugin | Producto opcional / fuera |

## 2.4 Servicios que hacen lo mismo (o casi)

- Push de documentos: outbox **y** colas prefs  
- Pull de stock: soft-pull lane `stock_ops` **y** `_stockOpsPullPump` **y** critical convergence  
- “Sanar” sync: AutoHealer + reclaim inflight + sweep holds + reconcile pendientes + rewind watermark  
- Diagnóstico: Panel técnico + Observability hub + Cert runners  

## 2.5 Arquitectura objetivo (sin agregar capas nuevas)

```
UI (menú chico)
  → Services existentes (producto, venta, remito, compra, precio, comparador)
    → SQLite + InventoryLedger (deltas)
    → SyncOutbox (una cola)
  → SyncService delgado
    → un timer: drain outbox → pull stock_ops → pull docs tocados
    → Firestore / Storage
```

Regla: **si se puede resolver tocando un archivo existente, no crear uno nuevo.**

---

# 3. Sync — respuestas únicas

## ¿Qué hace?

Mantiene SQLite local y Firestore del tenant eventualmente consistentes:

1. Cambios locales (venta, remito, compra, precio, producto) se escriben en SQLite.  
2. Stock: se registra un **delta** en `inventory_ledger` y se encola un `stock_op` en la outbox.  
3. Push: la outbox sube docs y stock_ops a Firestore.  
4. Pull: otros dispositivos bajan docs (LWW de catálogo) y aplican stock_ops al ledger (nunca confían en `productos.stock` remoto como autoridad).  
5. Offline: queda en cola; al volver Internet se drena.

## ¿Por qué existe?

Hay **varios dispositivos** (EXE Windows + varios Android) que deben vender **offline** y verse los mismos productos, precios, fotos y stock. Sin servidor propio: Firestore es el bus. El stock no puede ser “último gana” sobre un número absoluto (se pisan); necesita log de operaciones.

## ¿Es realmente necesario?

**Sí el concepto** (cola + stock_ops + ledger + proyección).  
**No** el motor actual completo. El 60–70% de `lib/core/sync/` existe por mitigar crashes del EXE y por certificación/observability, no por el dominio de suelas.

## ¿Puede hacerse más simple?

**Sí.** Objetivo:

1. Una cola SQLite (`SyncOutbox`).  
2. Un pump.  
3. Prioridad fija: stock_ops y docs de venta antes que catálogo masivo.  
4. Windows: throttle + hardCap chico (anti-crash), **sin** freeze eterno que deje el stock muerto.  
5. “Actualizar ahora” = push hasta ACK + pull hasta atrapar — **sin** rebobinar 30 días de watermark.  
6. Lab/cert/scheduler 2.0 **fuera** del runtime.

## ¿Qué código eliminaría? (solo quitar)

Orden de menor a mayor riesgo:

1. Dead: `outboxDrainPlan`, `watermark_hardening.dart`  
2. Lab: `sync_stress_runner`, `sync_benchmark_runner`, `sync_certification_runner`, `sync_report_pdf`, `sync_process_rss*`  
3. Scheduler ornamental: `turbo_mode_controller`, `adaptive_sync_controller`, `entity_lock_registry`, `scheduler_state_store`, `sync_metrics_history_store`, `sync_scheduler_metrics` (reemplazar claim por lógica mínima **dentro** del pump existente — no crear framework nuevo)  
4. Colas legacy prefs (`_cola*`) una vez migrada la flota  
5. `_stockOpsHechas` prefs → solo `StockOpsAppliedStore`  
6. Con freeze permanente: código soft-pull/listeners Windows muerto **o** (preferible) **eliminar el freeze** y el critical convergence pump, dejando un solo pull acotado  
7. Flags de rewind v142/v144/v151/v154 → no rewind en “Actualizar ahora”  
8. Parte de observability (SLA/flight/op_trace) si el panel de campo no la usa  

**No eliminaría sin reemplazo funcional:** `sync_outbox`, camino stock_ops → `inventory_ledger_service`, watermark/hold básicos, ACK con prueba cloud `applied`, tombstones, catch-up básico, hardCap Windows, media sync de fotos.

### Problemas reales del sync (para no “arreglar” agregando capas)

Al simplificar hay que **respetar** estos hechos (hoy son bugs, no features):

1. **Freeze** estabiliza el EXE pero **mata** convergencia de stock/papelera en Windows.  
2. **Rewind de 30 días** en Actualizar ahora puede re-aplicar historia y empeorar stock.  
3. **opIds** derivados de ids locales (`…_${productoId}` / eventos locales) pueden colisionar entre dispositivos si el id no es globalmente único.  
4. Watermark basado en reloj de cliente es frágil.  
5. Múltiples pumps compiten y se pisan prioridades.

La solución correcta es **quitar caminos**, unificar push→pull, y opIds únicos — no agregar un quinto pump.

---

# 4. Riesgos

Antes de borrar nada:

| Qué se elimina | Qué rompe | Qué depende | Cómo verificar |
|----------------|-----------|------------|----------------|
| Páginas muertas (calculadora, ventas_totales) | Nada | Nadie | `flutter analyze` + búsqueda de imports |
| `AppIconBuildService` | Nada | Nadie | analyze |
| AFIP stub + UI | Si alguien tenía AFIP “activado”, deja de bloquear (mejora). Numeración debe seguir | `venta_factura_page`, config docs | Crear Factura B en EXE y APK; PDF; numeración correlativa |
| Cert Lab de `lib/` | Tests `test/cert/**` | Solo CI de certificación | Mover tests o marcar skip; CI producto verde |
| WhatsApp plugin | Menú WA, CRM deeplinks avanzados, catálogo Meta | `main_shell`, CRM | Abrir cliente y chequear que no crashee; opcional deeplink simple |
| CRM Lite | Menú Seguimiento | Shell | Navegación sin crash |
| Colas legacy | Dispositivos viejos con cola prefs no migrada | Sync boot | Migración one-shot al outbox **antes** de borrar; test: ítem pending legacy → outbox |
| Scheduler 2.0 | Orden de drain si algo depende de turbo | Outbox pump | Venta offline → online → peer ve stock |
| Freeze / critical pump | Si se saca freeze sin hardCap, EXE puede volver a caer | Windows boot | Stress: login Windows + sync 10 min sin cierre; stock converge |
| Soft-pull | Si se saca y no queda otro pull de docs | Catálogo Windows | Cambio precio en APK → se ve en EXE sin F5 eterno |
| Rewind watermark | Deja de “recuperar” ops viejas por fuerza bruta | Actualizar ahora | Mejor: push+pull limpio; test E2E delta A→B |
| Observability lab | Panel técnico pierde PDF/bench | Panel | Dejar diagnóstico mínimo (pending/dead) |
| Dashboard / Inteligencia | Atajos analíticos | Menú | Una home con KPIs básicos alcanza |
| `StockIntegrityValidator` | Nada en prod | Solo tests | Ajustar tests o usar reconcile |

### Regla de verificación por fase

Checklist de oro (siempre):

1. Ver / buscar productos + fotos en EXE y 2 APK  
2. Cambiar precio en un dispositivo → aparece en los otros sin reiniciar  
3. Factura B + Remito → stock baja igual en todos  
4. Compra → stock y costo suben igual  
5. Comparador: proveedor / costo / precio / margen / diferencia  
6. Airplane mode → venta → online → sync solo  
7. Windows: 10+ minutos post-login sin cierre espontáneo  

---

# 5. Plan de trabajo

## Fase 1 — Eliminar código muerto

**Objetivo:** cero riesgo, menos ruido.

- Borrar `calculadora_page`, `ventas_totales_page`, `app_icon_build_service`  
- Borrar `watermark_hardening` / dead `outboxDrainPlan`  
- Quitar `cupertino_icons`  
- Archivar docs de auditoría versionada y PDF duplicados  

**Done when:** analyze limpio; app abre; menú igual.

## Fase 2 — Eliminar duplicaciones y fuera de scope

**Objetivo:** producto = pyme de suelas.

- Desactivar/eliminar AFIP (UI + stub + campos muertos en flujo de venta)  
- Sacar Cert Lab del runtime (`lib/core/cert` → fuera)  
- Decisión producto: WhatsApp Business y CRM (recomendación CTO: **fuera del menú** y del release)  
- Unificar writers de historial de precios  
- Unificar menú: una fuente; pasar de 36 a ~15 entradas visibles  
- Fusionar Inicio/Dashboard/Inteligencia en una home  
- Un atajo de importación  

**Done when:** Factura B no menciona CAE; menú cabe en una pantalla; lab no viaja en APK/EXE.

## Fase 3 — Simplificar sincronización

**Objetivo:** una cola, un pump, stock que converge.

Orden estricto (quitar, no agregar):

1. Apagar rewind en Actualizar ahora  
2. Eliminar freeze eterno **o** (si el EXE cae) reemplazarlo por solo hardCap+throttle — **nunca** freeze + stock muerto  
3. Un solo pump: outbox → stock_ops pull → docs pull  
4. Borrar soft-pull / critical / stock pump dedicados como caminos paralelos  
5. Borrar scheduler ornamental (turbo/adaptive/locks/metrics history)  
6. Borrar colas prefs legacy tras migración  
7. Un solo dedup applied store  
8. Asegurar opIds globalmente únicos **modificando** el builder existente (device id + event), sin motor nuevo  
9. Sacar lab observability del runtime  

**Done when:** cambio de stock en A aparece en B sin “magia”; EXE estable; Actualizar ahora no empeora.

## Fase 4 — Simplificar arquitectura

**Objetivo:** menos archivos que entender.

- Partir o adelgazar `firestore_sync_service` por extracción **interna** solo si achica (preferir borrar antes que mover)  
- Adelgazar `main_shell` / config  
- Panel técnico mínimo (pending, dead, último error) sin cert PDF  
- `DatabaseHelper`: no expandir; migraciones viejas no tocar salvo necesidad  

**Done when:** un desarrollador nuevo entiende sync en <1 lectura del flujo outbox→ledger.

## Fase 5 — Optimizar solo si hace falta

- Solo si tras Fase 3–4 sigue lento o inestable  
- Prohibido: nuevo “engine”, nuevo healer, nuevo watermark magic, nuevo lab  
- Permitido: índices SQLite, menos trabajo por tick, menos logs  

---

## Estimación de impacto (orden de magnitud)

| Acción | LOC fuera (orden) |
|--------|------------------:|
| Muerto + deps | ~800 |
| Cert Lab + lab sync | ~4.500+ |
| WhatsApp + CRM (si se corta) | ~3.000+ |
| AFIP stub/UI | ~400+ |
| Scheduler ornamental + pumps duplicados + cols legacy | ~2.000–4.000 (vía borrado/consolidación) |
| Menú/UI analítica | miles de LOC de superficie |

**Meta:** runtime claramente más chico; sync comprensible; mismas capacidades de la lista ✔ del dueño.

---

## Definición de terminado (producto)

El proyecto está terminado cuando se pueda:

- ✔ Ver / buscar productos, fotos, stock, precios, proveedor, listas  
- ✔ Factura B + Remito con descuento de stock  
- ✔ Registrar compras (stock/costos/listas)  
- ✔ Actualizar precios y verlos en PC + todos los Android  
- ✔ Comparar listas de proveedores  
- ✔ Mismos datos en todos los dispositivos  
- ✔ Offline + sync automático al recuperar Internet  

…y el código sea **claramente más pequeño, más simple y más fácil de mantener** que hoy.

---

## Decisión pedida al dueño (antes de Fase 2+)

Para no cortar de más, confirmar en una línea cada ítem:

1. **WhatsApp Business:** ¿fuera? (recomendado: sí)  
2. **CRM / Seguimiento:** ¿fuera? (recomendado: sí)  
3. **Chat interno / Comunicaciones:** ¿fuera? (recomendado: sí)  
4. **Presupuestos / Tickets / Entregas:** ¿se usan o solo Factura B + Remito?  
5. **Cuenta corriente:** ¿se usa para cobrar? (si sí → KEEP)  
6. **Panel técnico:** ¿solo admin para soporte? (recomendado: sí, mínimo)

Hasta tener esas respuestas, la Fase 1 (muerto) puede ejecutarse sin riesgo.

---

*Fin del informe. Próximo paso autorizado por este documento: Fase 1 — eliminar código muerto. No escribir features. No agregar clases nuevas.*
