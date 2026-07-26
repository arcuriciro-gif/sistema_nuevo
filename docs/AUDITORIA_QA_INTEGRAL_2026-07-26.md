# Auditoría Integral y QA — Tata.Manager

**Fecha:** 2026-07-26  
**Versión auditada:** `1.2.33+38` (`main` @ `169627a`)  
**Tipo:** Auditoría adversarial estática + suite de tests + walkthrough mental módulo a módulo + revisión de reglas Firebase/Storage  
**Equipo simulado:** QA Senior · Software Tester · Arquitecto · Auditor ERP · UX/UI · Security · Flutter Senior · Firebase · SQLite  

**Complemento obligatorio (ejecución mental + certeza):**  
`docs/AUDITORIA_WALKTHROUGH_TESTER_2026-07-26.md`  
**Suite que demuestra bugs de comportamiento (no solo “compila”):**  
`test/auditoria_comportamiento_adversarial_test.dart`

### Metodología y límites

| Hecho | No hecho en este entorno |
|---|---|
| Revisión de código de todos los módulos listados | UI interactiva del `.exe` / APK físico |
| Walkthrough mental módulo a módulo con etiquetas de certeza | Double-tap / FPS / crash mid-TX en hardware real |
| `flutter test` suite existente + **11/11** adversariales de comportamiento | 10.000 productos reales en dispositivo |
| `dart analyze lib` → sin errores | Campo Windows↔Android con dos devices |
| Lectura adversarial de sync/outbox/ledgers | Medición FPS/CPU en hardware real |
| Revisión `firestore.rules` + `storage.rules` | Prueba AFIP / Meta API reales |
| Evidencia de crashes recientes en campo (Sync, Venta rápida) | |

**Etiquetas de certeza** (ver walkthrough): **PRODUCIDO** · **OBSERVADO EN CAMPO** · **HIPÓTESIS DE CÓDIGO** · **NO VERIFICABLE AQUÍ**.  
No se asume que “compila ⇒ funciona”.

---

## 1. Resumen Ejecutivo

Tata.Manager es un ERP Flutter multi-dispositivo con arquitectura ambiciosa (ledgers, outbox, watermarks, modo estable Windows, plugins). Hay base sólida de dominio y sync certificable **parcialmente** implementada.

**Estado general: NO APTO PARA PRODUCCIÓN comercial amplia.**

Razones principales:

1. **Dos canales de venta con inventarios distintos** — Remitos/Venta rápida mueven stock; Facturas A/B/C **no**.
2. **Windows sigue siendo frágil** — crashes reales al Sync y Venta rápida (mitigados parcialmente en 1.2.32–1.2.33; quedan vectores: pulls ilimitados, listeners de config, Storage).
3. **Riesgos de integridad de stock en la nube** — race en `stock_ops` / reclaim inflight.
4. **Validaciones de dominio débiles** — códigos vacíos, stock negativo por defecto, saldo CC editable a mano.
5. **Seguridad local insuficiente** — SHA-256 sin salt, token WhatsApp en prefs, reglas Firestore amplias para cualquier writer.
6. **AFIP incompleto** — ventas se confirman sin CAE real; IVA A puede calcularse mal.

El sistema **sí** es usable como piloto controlado (1–2 PCs + 1–2 celulares, un operador entrenado, remitos como canal principal, sync opcional) si se aceptan las limitaciones. **No** está listo para “múltiples empresas / 100 usuarios / 100k SKUs / fiscal estricto”.

---

## 2. Hallazgos (por prioridad)

### 🔴 Críticos

#### C1 — Facturas no mueven stock
- **Módulos:** Ventas / Facturación / Inventario  
- **Evidencia:** `cuenta_corriente_service.dart` `crearVentaConPago` inserta `ventas`/`ventas_items` sin `InventoryLedger` / `assertPuedeAplicar`.  
- **Repro:** Crear Factura B con 5 unidades; stock del producto no baja. Venta rápida del mismo SKU sí baja.  
- **Impacto:** Inventario mentiroso; sobreventa; KPIs de stock/ganancia inconsistentes.  
- **Solución:** Unificar canal de entrega (factura → evento `MERCADERIA_ENTREGADA` o exigir remito asociado). Bloquear factura si no hay stock según política.

#### C2 — Crash mid-sale: remito commit ≠ ledger
- **Evidencia:** `remito_service.dart` — TX SQLite (remito+items+pago) **después** publica eventos de inventario/dinero.  
- **Repro:** Matar proceso tras guardar remito y antes del event bus (corte de luz / crash Windows).  
- **Impacto:** Documento existe; stock y/o CC no actualizados; sync amplifica el desfase.  
- **Solución:** Escribir outbox/ledger **dentro** de la misma TX; aplicar post-commit.

#### C3 — `codigo` vacío / no UNIQUE → corrupción Firestore
- **Evidencia:** Formulario producto sin validador de código; docId remoto = `codigo` o fallback `id` local.  
- **Repro:** Alta sin código en PC y APK → docs `"1"`,`"2"` colisionan.  
- **Impacto:** Sobrescritura de productos entre dispositivos.  
- **Solución:** Código obligatorio + UNIQUE; UUID interno si el usuario no define SKU.

#### C4 — Hard-delete de producto solo local
- **Evidencia:** `producto_service.eliminarDefinitivo`; doc C7.  
- **Repro:** Papelera → eliminar definitivo → otro device revive el SKU al pull.  
- **Impacto:** Deletes no convergen.  
- **Solución:** Tombstone remoto ACK antes de wipe local.

#### C5 — Race `stock_ops` puede inflar stock
- **Evidencia:** `firestore_producto_repository` fallback de incremento si status claimed/pending_apply.  
- **Repro:** Crash entre increment y `applied` + reclaim.  
- **Impacto:** Stock nube > real.  
- **Solución:** Transacción atómica única; idempotencia por `opId` sin segundo increment.

#### C6 — Factura A: IVA +21% sobre precio de lista (posible doble IVA)
- **Evidencia:** `venta_factura_page.dart` añade 21% al total.  
- **Repro:** Precio de lista ya con IVA → factura 21% de más.  
- **Impacto:** Pérdida comercial / error fiscal.  
- **Solución:** Config “precios incluyen IVA” / cálculo neto+IVA explícito.

---

### 🟠 Altos

#### A1 — Double-tap Finalizar en Venta rápida / Factura / Remito
- **Evidencia:** `_finalizando` / `guardando` se setean tarde; sin `if (busy) return` al inicio.  
- **Repro:** Doble tap rápido en Finalizar → dos remitos.  
- **Impacto:** Doble stock/CC.  
- **Solución:** Guard inmediato + disable botón + future único.

#### A2 — Windows: `.get()` ilimitado de ventas/remitos/clientes
- **Evidencia:** `_pullSuaveWindows` / `_pullInicialCatchUp`.  
- **Repro:** Tenant con historial grande + Sync / pull periódico.  
- **Impacto:** OOM / crash `.exe` (ya visto en campo con Sync y venta).  
- **Solución:** Paginación + watermarks en **todas** las colecciones en Windows; cero full-get.

#### A3 — Stock negativo permitido por defecto
- **Evidencia:** `IntegrityPolicy` `?? true`.  
- **Impacto:** Oversell silencioso.  
- **Solución:** Default `false`; override explícito admin.

#### A4 — `limiteCuenta` cosmético
- **Evidencia:** Se guarda en cliente; ningún finalize lo consulta.  
- **Impacto:** Crédito sin control.  
- **Solución:** Gate en remito/factura/venta rápida.

#### A5 — Saldo CC editable en ficha cliente
- **Evidencia:** `cliente_form_page` campo saldo.  
- **Impacto:** Deuda inventada / sync de basura.  
- **Solución:** Solo lectura; origen = documentos.

#### A6 — AFIP: venta confirmada sin CAE
- **Evidencia:** Estados `pendiente_afip` / `pendiente_config` no bloquean éxito.  
- **Impacto:** Usuario cree que facturó legalmente.  
- **Solución:** Bloquear o UX de “no fiscal hasta CAE”.

#### A7 — Token WhatsApp en SharedPreferences (plaintext)
- **Evidencia:** `whatsapp_business_config.dart`.  
- **Impacto:** Robo de token Meta.  
- **Solución:** Secure storage.

#### A8 — Passwords locales SHA-256 sin salt + admin123
- **Evidencia:** `auth_service.dart`.  
- **Impacto:** Compromiso offline del DB.  
- **Solución:** Argon2/bcrypt; forzar cambio; recovery off by default post-setup.

#### A9 — Firestore rules: cualquier `canWriteOps` escribe ops sin schema
- **Evidencia:** `firestore.rules` match genérico.  
- **Impacto:** Cliente comprometido altera stock/ventas.  
- **Solución:** Validación de campos + roles granulares.

#### A10 — Storage rules demasiado abiertas
- **Evidencia:** `storage.rules` `tenants/{tenantId}/{allPaths=**}`.  
- **Impacto:** Abuso de cuota / overwrite.  
- **Solución:** Allowlist de paths + tamaño + contentType.

#### A11 — Soft-delete offline puede perderse por LWW
- **Evidencia:** Upload skip remote_wins sin forzar delete.  
- **Impacto:** Producto “borrado” reaparece.  
- **Solución:** Deletes con precedencia sobre LWW.

#### A12 — Authz ausente en CRM, documentos, analytics, CSV, comparador
- **Impacto:** Permisos UI-only.  
- **Solución:** `AuthorizationService.require` en todos los entrypoints.

#### A13 — Producto form sin validación
- Código/descripcion vacíos, stock no numérico → 0, precio 0.  
- **Solución:** Validators estrictos.

#### A14 — Dual-write producto (SQLite + fire-and-forget remoto + outbox)
- **Impacto:** Carreras foto/stock.  
- **Solución:** Un solo camino: local + outbox.

#### A15 — Backup restore sin pausar sync / limpiar watermarks
- **Impacto:** Corrupción post-restore.  
- **Solución:** Restore → offline → reset watermarks → catch-up planificado.

---

### 🟡 Medios

| ID | Hallazgo | Impacto |
|---|---|---|
| M1 | Dashboard “Valor stock” = precio×stock (no costo) | Valuación inflada |
| M2 | KPI “Críticos” mezcla sin stock | Urgencia falsa |
| M3 | CRM inactivos ignora facturas | Falsos inactivos |
| M4 | CRM / WhatsApp catalog local-only (multi-device) | Datos no viajan |
| M5 | Reminders CRM marcan día aunque notify falle | Avisos perdidos |
| M6 | DataRefreshHub refresca todos los módulos cacheados | Jank Windows |
| M7 | Config accesible por ícono aunque módulo oculto | Bypass de menú |
| M8 | Quick actions silenciosas si módulo oculto | UX “roto” |
| M9 | Reclaim inflight 90s Windows puede re-ejecutar ops lentas | Duplicados potenciales |
| M10 | Fotos: timeout 4s deja path local; peers sin imagen | Catálogo incompleto |
| M11 | `putData` carga imagen entera en memoria | Crash foto grande |
| M12 | CUIT/teléfono sin validación fuerte | Fallos AFIP/WhatsApp |
| M13 | Listeners ilimitados en no-Windows (ventas/remitos) | Escalabilidad Android |
| M14 | Outbox dead tras 12 intentos poco visible | Sync “muerto” silencioso |
| M15 | PDF/Storage y flush stock (~15–20s) aún pueden solaparse | Crash residual Windows |
| M16 | Precio 0 en carrito permitido | Ventas basura |
| M17 | Cliente form: `guardando` stuck on error | UI trabada |
| M18 | Proveedor exige email (fricción) | Altas bloqueadas |
| M19 | Búsqueda global carga 800 productos | Memoria |
| M20 | Eliminar factura confirmación débil vs anular | Pérdida |

---

### 🟢 Bajos

| ID | Hallazgo |
|---|---|
| B1 | Interpolación SQL de enteros en analytics (bajo riesgo hoy) |
| B2 | Mobile Finalizar no deshabilita carrito vacío en compact |
| B3 | Token WA se carga completo al abrir pantalla |
| B4 | Remito: Agregar vs tap de producto inconsistente |
| B5 | Demasiados diálogos para cerrar una venta rápida |
| B6 | Self-join legacy si `allowSelfJoin` quedó true en tenant viejo |

---

## 3. Riesgos de pérdida / corrupción de datos

| Riesgo | Probabilidad | Severidad | Escenario |
|---|---|---|---|
| Stock nube inflado | Media | Crítica | Crash mid stock_op + reclaim |
| Producto pisado entre devices | Media | Crítica | Códigos vacíos/duplicados |
| Delete no converge | Media | Alta | Hard-delete / LWW vs soft-delete |
| Remito sin stock | Media | Alta | Crash post-TX pre-event |
| CC incorrecta | Alta | Alta | Saldo editable + facturas vs remitos |
| Inventario mentiroso | Alta | Crítica | Facturas sin stock |
| Restore vs nube | Media | Crítica | Restore viejo con sync ON |
| Token Meta filtrado | Baja–Media | Alta | Prefs/backup |
| Ventas duplicadas | Media | Alta | Double-tap |
| Windows crash mid-sync | Alta (campo) | Alta | Pulls grandes + Storage |

---

## 4. Mejoras recomendadas antes de publicar

### Bloqueantes (P0)
1. Unificar inventario: facturas mueven stock **o** se prohíbe vender solo por factura.  
2. Validar `codigo` obligatorio + UNIQUE; banear docId = local id.  
3. Anti double-submit en Venta rápida / Remito / Factura.  
4. Ledger/outbox **en la misma TX** que el documento comercial.  
5. Windows: paginar **todas** las colecciones; eliminar full `.get()`.  
6. Default stock negativo = **false**.  
7. Idempotencia dura de `stock_ops`.  
8. Tombstone real en hard-delete producto.

### Importantes (P1)
9. Secure storage para tokens WA / recovery codes.  
10. Endurecer `firestore.rules` + `storage.rules`.  
11. Saldo CC read-only + `limiteCuenta` enforced.  
12. AFIP: no “éxito” sin CAE (o marcar no-fiscal explícito).  
13. Authz en CRM/docs/export.  
14. Password hashing moderno; cerrar admin123 post-setup.  
15. Restore offline + reset watermarks.

### Deseables (P2)
16. Debounce DataRefreshHub / lazy modules.  
17. CRM inactivos incluyen facturas.  
18. KPI stock a costo.  
19. Cola media (fotos) separada del sync docs.  
20. Tests de campo automatizados Windows crash suite.

---

## 5. Arquitectura — evaluación

**Fortalezas**
- Separación Core vs Plugins (WhatsApp fuera del sync de dominio) alineada al charter.  
- Ledgers de inventario/dinero + DomainEventBus (Capacidad 3).  
- Outbox + watermarks + conflicts (Capacidad 2) — dirección correcta.  
- Modo estable Windows (sin listeners de colecciones grandes) — reacción correcta a crashes.  
- Dual repository / catch-up paginado de productos (evolución reciente).

**Debilidades**
- **Dos verdades de venta** (remito vs factura) rompen el modelo ERP.  
- Dual-write + outbox = caminos paralelos.  
- Eventos de dominio **fuera** de la TX comercial.  
- Plugins locales (CRM/WA) sin contrato multi-device → expectativa falsa de “sistema único”.  
- Throttle global único mezcla stock, PDF, cliente, remito → colisiones temporales.

**Nota arquitectura:** 6.0/10 — buena dirección, inconsistencias peligrosas en el núcleo comercial.

---

## 6. UI / UX

**UI**
- Shell por secciones + tokens: mejora clara vs monolito anterior.  
- POS 2 columnas usable en desktop.  
- Riesgos: overflow en listas densas, jank por refresh global, badge sync confuso (“0 pendientes / 10 en curso”).

**UX**
- Venta rápida: demasiados pasos (carrito → cobro → compartir).  
- Acciones rápidas que no hacen nada si el módulo está oculto.  
- Config “oculta” pero accesible por ícono.  
- CRM/WhatsApp parecen “del sistema” pero son locales → frustración multi-device.  
- Confirmaciones destructivas irregulares (remito OK, factura/CRM flojas).

**Nota UI:** 6.5/10 · **UX:** 5.5/10

---

## 7. Rendimiento

| Punto débil | Evidencia |
|---|---|
| Full-collection get Windows | Soft pull ventas/remitos/clientes |
| Refresh global IndexedStack | Todas las páginas cacheadas se recargan |
| Búsqueda 800 productos en memoria | `busqueda_global_page` |
| `putData` fotos enteras | Media sync |
| Listeners ilimitados (móvil) | Ventas/remitos snapshots |
| Suite de tests OK pero sin load test | 75 tests, 0 stress |

**Nota rendimiento:** 5.0/10 para multi-device real; aceptable en tenant chico (<2k productos, docs acotados).

---

## 8. Seguridad

| Área | Estado |
|---|---|
| Auth local | Débil (SHA-256, admin123, biometric = userId) |
| Authz app | Parcial (huecos CRM/docs/export) |
| Firebase Auth | Presente; password en memoria para reconnect |
| Firestore rules | Membresía OK; writes ops demasiado amplios |
| Storage rules | Demasiado abiertos |
| Secretos | Token WA / recovery en prefs |
| SQL injection | Bajo (params mayormente); patrones interpolados puntuales |
| Multi-tenant | Tenant id + membership; self-join legacy residual |

**Nota seguridad:** 4.5/10

---

## 9. Escalabilidad

| Escala | ¿Soporta? | Comentario |
|---|---|---|
| 1 empresa, 1–3 devices, <3k SKUs | Condicional | Piloto con remitos + sync cuidadoso |
| 100 usuarios concurrentes | No | Sin roles server-side finos; listeners/costos |
| 1.000 usuarios | No | Firestore costs + falta de sharding/CQRS |
| 100.000 productos | No | Pulls, UI, índices; Windows colapsa |
| Múltiples empresas (tenants) | Parcial | Modelo tenant existe; onboarding/ops inmaduros |

**Nota escalabilidad:** 3.5/10

---

## 10. Veredicto Final

### Notas (1–10)

| Dimensión | Nota | Justificación breve |
|---|---|---|
| Arquitectura | **6.0** | Buen rumbo (outbox/ledgers/plugins); fisuras en venta/stock |
| Calidad del código | **5.5** | Mejoras recientes; pages/services grandes; dual-write |
| UI | **6.5** | Shell/POS mejorados; jank y estados sync confusos |
| UX | **5.5** | Flujos largos; permisos/menú inconsistentes |
| Rendimiento | **5.0** | OK tenant chico; peligroso con historial/catálogo grande |
| Seguridad | **4.5** | Auth local y rules ops insuficientes |
| Escalabilidad | **3.5** | No diseñado aún para 100k SKUs / muchos users |
| Mantenibilidad | **5.5** | Docs de capacidades ayudan; deuda sync Windows alta |
| Experiencia de usuario | **5.0** | Crashes recientes dañan confianza |
| Preparación producción | **4.0** | Bloqueantes P0 sin cerrar |

### Dictamen

# NO APTO PARA PRODUCCIÓN

**Evidencia técnica:**
1. Canal Factura sin inventario (C1) — defecto ERP de raíz.  
2. Riesgos de corrupción sync/stock (C3–C5, A2, A11).  
3. Crashes de campo en Windows al Sync y Venta rápida (mitigación parcial, no eliminación).  
4. Seguridad local y reglas cloud por debajo del umbral comercial.  
5. AFIP no bloqueante + IVA A dudoso (C6, A6).

### Sí apto como
**Piloto controlado / producción restringida** si y solo si:
- Se vende **solo** por Remito / Venta rápida (no Factura como entrega).  
- 1 tenant, pocos devices, operador capacitado.  
- Stock negativo desactivado.  
- Sync Windows con expectativa de demoras; backups locales frecuentes.  
- Sin dependencia fiscal AFIP real hasta cerrar CAE.

---

## Anexo A — Cobertura de módulos revisados

| Módulo | Revisado | Hallazgos clave |
|---|---|---|
| Inicio | Sí (código) | Refresh global, quick actions silenciosas |
| Dashboard | Sí | KPI stock/precio, críticos |
| Productos | Sí | Validación, delete, fotos, códigos |
| Clientes | Sí | Saldo editable, límite, CUIT |
| Proveedores | Sí | Email obligatorio, validación floja |
| Venta rápida | Sí + campo | Double-tap, stock, crash PDF/sync |
| Remitos | Sí | TX vs events, delete race Windows |
| Facturación A/B/C | Sí | Sin stock, IVA, AFIP |
| Compras | Sí (código) | Throttle Windows OK; validar costos |
| Cuenta corriente | Sí | Recalc + saldo editable |
| Inventario | Sí | Default negativo, ledger post-TX |
| Sync / Outbox | Sí + campo | Pulls, inflight, stock_ops |
| Firestore/SQLite | Sí | Rules, índices, schema 32 |
| Windows / Android | Parcial | Crashes Windows; Android menos probado aquí |
| WhatsApp / CRM | Sí | Local-only, token, catalog fotos |
| Seguridad / Perf | Sí | Ver §§7–8 |

## Anexo B — Suite automática

```
flutter test → 75 passed
dart analyze lib → 0 errors
```

La suite **no** cubre: double-tap UI, full sync Windows load, factura↔stock, hard-delete convergencia, AFIP real, stress 10k SKUs.

## Anexo C — Crashes de campo recientes (contexto)

| Fecha | Síntoma | Mitigación en main |
|---|---|---|
| 2026-07-26 | Sync tumba `.exe` | Throttle, catch-up liviano, pumps post-catchup (1.2.32) |
| 2026-07-26 | Badge 0 pending / 10 inflight | Reclaim inflight en pump (1.2.32+37) |
| 2026-07-26 | Venta rápida tumba `.exe` | PDF/Storage/cliente diferidos (1.2.33+38) |

Estas mitigaciones **reducen** pero **no eliminan** A2/M15.

---

*Fin del informe. Próximo paso recomendado: plan P0 en rama dedicada, con tests de regresión por cada crítico, antes de cualquier release público.*
