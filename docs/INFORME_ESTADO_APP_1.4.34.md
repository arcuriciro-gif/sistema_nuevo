# Informe de estado — Tata.Manager

**Fecha:** 2026-07-30  
**Punta del trabajo de simplificación:** `1.4.34+92`  
**Rama tip:** `cursor/fase5-limpieza-residual-e44b`  
**`main` hoy (producción/base):** `1.4.28+86` — las Fases 1–5 **aún no están mergeadas**

---

## 1. Veredicto en una frase

La app ya está recortada a un **ERP pyme para vender suelas** (productos, stock, Factura B / Remito, compras, precios, sync simple). El código tip es ~**13 300 LOC** más chico que `main`. Falta **mergear el stack de PRs** y superar la **[validación final de campo](VALIDACION_FINAL_CAMPO.md)** (jornada real). Compilar/tests **no** alcanzan.

---

## 2. Dónde quedó vs dónde estaba

| Métrica | `main` (1.4.28) | Tip Fase 5 (1.4.34) | Δ |
|---|---|---|---|
| Versión | `1.4.28+86` | `1.4.34+92` | +6 build |
| LOC en `lib/` | ~67 997 | ~54 726 | **−13 271** |
| Ítems menú | 39 | **22** | −17 |
| `firestore_sync_service.dart` | ~5 652 | ~5 338 | −314 (sigue siendo el god-object) |
| AFIP / WA Business / CRM Lite / Cert Lab | presentes o en menú | **fuera de producto** | — |
| Colas prefs + Turbo/Adaptive | vivos / residuales | **muertos** (outbox única) | — |

---

## 3. Qué es la app hoy (producto)

### En el menú (22)

| Área | Pantallas |
|---|---|
| Vender | Inicio, Venta Rápida, Ventas / Facturas, Remitos |
| Catálogo | Productos, Papelera, Categorías, Importar |
| Stock / compras | Stock, Compras |
| Precios | Listas de Precios, Comparador de listas |
| Personas | Clientes, Cuenta corriente, Proveedores |
| Ops | Reportes, Usuarios, Permisos, Mi perfil, Respaldo, Panel técnico, Configuración |

### Capacidades que **sí** cubre (misión CTO)

- Productos: listar, buscar, fotos, stock, precios, proveedor, listas  
- Factura B (documento + CC; **no** mueve stock) + Remito / Venta Rápida (**sí** descuentan stock)  
- Compras que suman stock  
- Mismo stock en dispositivos (vía `stock_ops` + ledger)  
- Sync de precios / catálogo  
- Comparador de precios de proveedores  
- Offline → cola outbox → nube (cola única SQLite)

### Qué **no** es más (sacado en Fase 2+)

- AFIP / CAE / facturación electrónica (Factura B local sin bloqueo AFIP)  
- WhatsApp Business plugin / CRM Lite  
- Cert Lab y runners de laboratorio  
- Menú hinchado (analítica / labs / extras fuera de scope)  
- Sync Engine 2.0 ornamental (Turbo, Adaptive, EntityLock, dual prefs queue)

### Residuo menor aceptable

- `wa.me` deeplink simple en clientes (no plugin WA)  
- Campos/comentarios AFIP residuales en modelo venta (sin módulo fiscal)  
- Observabilidad / healer / circuit breaker (útiles, no “enterprise sync”)

---

## 4. Arquitectura sync (estado tip)

```
UI (menú 22)
  → servicios / SQLite
  → InventoryLedger (deltas) + SyncOutbox (única cola)
  → 1 Timer unificado:
       1) pull stock_ops (hardCap Windows ≤4)
       2) drain outbox
       3) soft docs (catálogo / negocio)
  → Firestore / Storage
```

**Autoridad de stock:** `stock_ops` → ledger → proyección `productos.stock`  
(no LWW de stock absoluto desde el doc producto)

**opId cloud:** `deviceId_eventId_productoId`  
**Migración legacy:** one-shot prefs → outbox (`sync_outbox_migrated_v2`)

---

## 5. Stack de PRs (orden de merge)

| # | Fase | PR | Estado | Base |
|---|---|---|---|---|
| 0 | Informe análisis | [#112](https://github.com/arcuriciro-gif/sistema_nuevo/pull/112) | OPEN | `main` |
| 1 | Código muerto (−971) | [#113](https://github.com/arcuriciro-gif/sistema_nuevo/pull/113) | OPEN | `main` |
| 2 | Scope pyme (−14k) `1.4.31` | [#114](https://github.com/arcuriciro-gif/sistema_nuevo/pull/114) | OPEN | `main` |
| 3 | Sync simple `1.4.32` | [#115](https://github.com/arcuriciro-gif/sistema_nuevo/pull/115) | OPEN | Fase 2 |
| 4 | Adelgazar sync `1.4.33` | [#116](https://github.com/arcuriciro-gif/sistema_nuevo/pull/116) | OPEN | Fase 3 |
| 5 | Limpieza residual `1.4.34` | [#117](https://github.com/arcuriciro-gif/sistema_nuevo/pull/117) | OPEN | Fase 4 |

**Importante:** en GitHub, `main` sigue en **1.4.28**. Todo lo de simplificación vive en ramas abiertas. Hasta mergear (ideal: 114→115→116→117, o squash del tip), los builds de campo “oficiales” no llevan este corte.

Nota: #113 (Fase 1) quedó absorbida dentro de #114; se puede cerrar al mergear #114.

---

## 6. Riesgos / deuda que queda

| Tema | Severidad | Nota |
|---|---|---|
| `firestore_sync_service.dart` ~5.3k LOC | Alta deuda | Sigue siendo el archivo más peligroso; Fase 5 no lo partió a propósito |
| Stack sin merge | Bloqueante producto | Campo tip ≠ `main` |
| Observabilidad sync (SLA, flight, hub) | Media | Útil para panel técnico; se puede seguir adelgazando si duele |
| Preemption L1 en drain | Baja | No es Turbo; sigue activa y es razonable |
| Docs viejos (Cert Lab, roadmaps 2.0) | Baja | Ruido documental; no afectan runtime tip |
| Validación campo EXE+APK tip | **Crítica** | No dar por cerrado sin prueba `tata_stock` |

---

## 7. Checklist de campo (aceptación)

**Documento oficial (gate):** [`VALIDACION_FINAL_CAMPO.md`](VALIDACION_FINAL_CAMPO.md) — jornada completa PC + 2–3 Android.

Resumen mínimo tip `1.4.34+92` / `tata_stock`:

1. Remito → stock idéntico en todos  
2. Precios idénticos tras ≥50 cambios  
3. Offline ≥2 h → outbox vacía, sin duplicados  
4. Fotos sync (sobre todo APK↔APK)  
5. Comparador como herramienta de **decisión** (hoy incompleto en código — ver §3 del gate)  
6. EXE estable **toda la jornada**

Si falla → estabilizar; **no** features nuevas.

---

## 8. Próximo paso recomendado (CTO)

1. **Mergear** stack (#114 → #117) a `main` cuando el campo tip esté verde.  
2. **No** abrir Fase 6 de features.  
3. Solo si duele en campo: partir/adelgazar `firestore_sync_service` o borrar más observabilidad.  
4. Optimizar rendimiento **solo** con dolor medido (crash, freeze, stock que no llega).

---

## 9. Resumen ejecutivo

| Pregunta | Respuesta |
|---|---|
| ¿Qué es hoy? | ERP pyme suelas: vender + stock + precios + sync |
| ¿Qué dejó de ser? | Suite AFIP/CRM/lab + sync “enterprise” |
| ¿Está en `main`? | **No** — tip en PRs #114–#117 |
| ¿Cuánto se achicó? | ~**−13 k LOC** `lib/` vs `main` |
| ¿Qué falta para “listo”? | Jornada PASS ([VALIDACION_FINAL_CAMPO](VALIDACION_FINAL_CAMPO.md)) + merge |
| ¿Comparador listo? | **No** — faltan eliminados / multi-proveedor / márgenes / PVP / ganancia |
| ¿Seguir agregando features? | **No** — jornada + estabilizar gaps del gate |
