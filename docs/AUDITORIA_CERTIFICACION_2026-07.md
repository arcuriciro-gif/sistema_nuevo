# Auditoría de certificación — Tata.Manager

| Campo | Valor |
|---|---|
| Fecha | 2026-07-21 |
| Alcance | Tip de producto auditado: `cursor/remitos-eliminar-sync-admin-e44b` @ `6e754b4` |
| Rol | Auditor externo (CTO / Arquitectura / Seguridad / DevOps / QA) |
| Postura | **No se asume que el sistema esté terminado.** Se busca lo que puede romperlo. |
| Código | **Sin cambios de producto en esta entrega** — solo informe + roadmap. |

---

## 0. Veredicto ejecutivo

**No certificar Tata.Manager como ERP comercial multi-dispositivo en el estado actual.**

El producto demuestra valor operativo real (ventas/remitos/compras, sync Firebase, builds Android/Windows). Eso no equivale a certificación. Los bloqueantes de venta B2B / multi-sucursal son:

1. **Seguridad Firebase**: self-join + cualquier miembro escribe todo el tenant.
2. **Tenant por defecto único** (`tata_stock`) compartible entre instalaciones.
3. **Keystore Android y passwords versionados en el repo.**
4. **Stock no certificable**: ventas no mueven stock; `stock_ops` no es atómico.
5. **Offline/cola**: se vacía antes de confirmar subida; deletes offline no son durables.
6. **Permisos**: mayormente UI; casi sin enforcement en servicios ni en rules por rol.
7. **CI/CD**: builds sin tests, sin `main`, sin firma Windows, sin provenance.
8. **Escala**: límites duros (10k productos sync, 2k catch-up docs) y sin paginación completa.

**Nivel comercial actual estimado:** prototipo avanzado / piloto controlado (1 empresa, pocos dispositivos, operadores de confianza).  
**Nivel objetivo 2.0:** ERP comercial multi-tenant, multi-dispositivo, auditables.

---

## 1. Mapa del sistema (estado real)

```
┌─────────────┐   sync bus    ┌──────────────────────┐
│ Windows EXE │◄─────────────►│ Firebase Auth        │
│ Android APK │               │ Firestore (tenant)   │
└──────┬──────┘               │ Storage (media)      │
       │                      └──────────────────────┘
       ▼
┌──────────────────┐
│ SQLite local     │  ← Source of Truth operativo por dispositivo
│ (eltata.db)      │
└──────────────────┘
```

| Capa | Realidad |
|---|---|
| SoT operativo | SQLite por dispositivo |
| SoT entre dispositivos | Firestore parcial (stock cloud + documentos merge) |
| Auth | Local (SHA-256) + Firebase Auth (Google / vínculo) |
| Autorización | Matriz SQLite + UI; **casi nada en Firestore rules por rol** |
| Tenant | Default hardcodeado `tata_stock` + SharedPreferences editable |
| Sync | `FirestoreSyncService` (~2443 líneas) monolítico |
| Media | Storage opcional; falla → foto solo local |
| Backup | Copia cruda de `.db` |

Contratos documentados en `docs/ARCHITECTURE_CONTRACTS.md` (Fases 0–3).  
Release train en `docs/RELEASE_TRAIN.md` — `main` aún no consolida las fases.

---

## 2. Matriz de hallazgos (resumen)

| ID | Severidad | Área | Título corto |
|---|---|---|---|
| C1 | **CRÍTICO** | Seguridad | Self-join + auto-elevación de rol en `members/{uid}` |
| C2 | **CRÍTICO** | Seguridad | Cualquier miembro escribe/borra colecciones operativas |
| C3 | **CRÍTICO** | Tenants | Default `tata_stock` rompe aislamiento multi-empresa |
| C4 | **CRÍTICO** | Release | Keystore + passwords Android en el repositorio |
| C5 | **CRÍTICO** | Stock | Ventas no descuentan stock ni generan `stock_ops` |
| C6 | **CRÍTICO** | Stock | `stock_ops` no es atómico (race + claim incompleto) |
| C7 | **CRÍTICO** | Sync | Cola offline se vacía antes de confirmar upload |
| C8 | **CRÍTICO** | Sync | Deletes offline no se encolan (resurrección / divergencia) |
| A1 | **ALTO** | Auth | `admin/admin123` recovery default habilitado |
| A2 | **ALTO** | Permisos | Enforcement casi solo UI; servicios sin guardas |
| A3 | **ALTO** | Permisos | Matriz `config/permisos` escribible por cualquier miembro |
| A4 | **ALTO** | Usuarios | Docs `usuarios` escribibles → sync puede elevar roles locales |
| A5 | **ALTO** | Storage | Read/write de todo el tenant a cualquier miembro |
| A6 | **ALTO** | Sync | Delete remoto solo remitos/clientes y sets en memoria |
| A7 | **ALTO** | Sync | LWW parcial; `forzar:true` y writes absolutos de stock |
| A8 | **ALTO** | Escala | Catch-up 2k / productos 10k / `.get()` completos |
| A9 | **ALTO** | CI/CD | Sin tests en pipeline; sin `main`; Windows sin firma |
| A10 | **ALTO** | Android | Package `com.example.*`, sin App Check / Play Integrity, R8 off |
| A11 | **ALTO** | Backup | Restore borra destino sin validación; auto-backup silencioso |
| A12 | **ALTO** | Tests | ~3 tests unitarios; sin sync/stock/auth/migraciones |
| M1 | **MEDIO** | Auth | SHA-256 sin salt/KDF |
| M2 | **MEDIO** | Auth | Recovery code en plain prefs; RNG débil password temporal |
| M3 | **MEDIO** | Numeración | Race local en `generarNumero` remitos/compras |
| M4 | **MEDIO** | SQLite | Sin integrity_check / recuperación de corrupción |
| M5 | **MEDIO** | Migraciones | `ALTER` swallow-all puede ocultar schema incompleto |
| M6 | **MEDIO** | Media | Storage down → fotos no portables; sin cola por archivo |
| M7 | **MEDIO** | Código | Mega-servicios / singletons / AFIP stub |
| M8 | **MEDIO** | Observabilidad | Logs locales sin rotación; sin crash/telemetry |
| M9 | **MEDIO** | Docs | README plantilla; release train no cerrado |
| B1 | **BAJO** | UX/Roles | `solo_lectura` aspiracional; no asignable en UI |
| B2 | **BAJO** | Windows | Instalador = ZIP + BAT; sqlite3.dll best-effort |
| B3 | **BAJO** | Plugins | Shell por módulo hardcodeado; no platform |

---

## 3. Hallazgos detallados

### C1 — Self-join + auto-elevación de rol (CRÍTICO)

**Por qué existe:** Fase 1 priorizó migración de dispositivos existentes (`allowSelfJoin=true`).

**Evidencia:** `firestore.rules` L54–83; `tenant_membership_service.dart` crea tenant con `allowSelfJoin: true`.

**Riesgo:** Cualquier cuenta Firebase autenticada puede crear/actualizar su `members/{uid}` con `rol: admin` si self-join está activo, o actualizar su propio member doc sin restringir campos privilegiados.

**Reproducción:**
```js
setDoc(doc(db, "tenants/tata_stock/members/<uid>"), {
  uid, rol: "admin", activo: true, actualizadoEn: new Date().toISOString()
});
```

**Solución:** Self-join off en producción; create/update de members solo owner/admin o Cloud Function; `affectedKeys().hasOnly` para updates propios; roles vía custom claims.

**Impacto de corregir:** Flujo de invitación obligatorio; migración de miembros actuales.

---

### C2 — Escritura operativa sin roles en Firestore (CRÍTICO)

**Evidencia:** `firestore.rules` L88–108 — `allow read, write: if isMember` para productos, ventas, remitos, compras, usuarios, config, stock_ops, etc.

**Riesgo:** Un empleado (o miembro elevado) puede borrar ventas, pisar stock, reescribir permisos, alterar usuarios.

**Reproducción:** `deleteDoc(.../ventas/X)`, `setDoc(.../config/permisos, ...)`, `setDoc(.../productos/COD, {stock:-99999})`.

**Solución:** Rules por colección + rol + acción; operaciones destructivas por Functions; validación de schema/`hasOnly`.

**Impacto:** Sync cliente debe adaptarse; algunas escrituras pasan a backend.

---

### C3 — Tenant default `tata_stock` (CRÍTICO)

**Evidencia:** `backend_config_service.dart` — `_defaultTenant = 'tata_stock'`; editable en SharedPreferences.

**Riesgo:** Todas las instalaciones nuevas apuntan al mismo tenant conocido. Combinado con C1/C2 = aislamiento multi-empresa inexistente.

**Solución:** Tenant UUID no adivinable; binding por invitación/claim; `allowSelfJoin=false`; migración de datos del tenant compartido.

---

### C4 — Keystore en el repo (CRÍTICO)

**Evidencia:** `android/key.properties` con passwords en claro; `android/keystore/tata-manager.jks` versionado; `.gitignore` Android fuerza inclusión (`!keystore/tata-manager.jks`, `!key.properties`).

**Riesgo:** Quien tenga el repo firma APKs como Tata.Manager. Impide certificación Play / confianza comercial.

**Solución:** Rotar keystore; secretos en CI; Play App Signing; nunca versionar `.jks`/passwords.

---

### C5 — Ventas no mueven stock (CRÍTICO)

**Evidencia:** `venta_service.dart` crea vía CC y solo `subirVenta`; `cuenta_corriente_service` no actualiza `productos.stock`. Remitos/compras sí llaman `ajustarStockEnNube`. Anular venta no revierte stock.

**Qué ocurre en escenario “10 celulares vendiendo el mismo artículo” (vía Ventas):**
- Se crean N documentos de venta.
- El stock local y cloud **no baja**.
- Overstock / stock fantasma asegurado.

**Nota de producto:** Si el flujo comercial real es Remito (no Venta), el riesgo se mitiga parcialmente — pero entonces el módulo Ventas es una bomba de consistencia inventarial.

**Solución:** Unificar motor de stock: toda salida (venta/remito) y entrada (compra/devolución/ajuste) genera evento idempotente + movimiento local + `stock_ops`.

---

### C6 — `stock_ops` no atómico (CRÍTICO)

**Evidencia:** `firestore_producto_repository.dart` L118–149 — `get` → `set` claim → `increment` separado. Comentario explícito: sin `runTransaction` por estabilidad Windows.

**Escenarios:**
| Caso | Resultado actual |
|---|---|
| Dos clientes mismo `opId` concurrentes | Ambos pueden pasar `exists==false` → doble incremento |
| Crash tras `set` claim y antes de increment | Reintentos ven claim y **nunca aplican delta** (pérdida) |
| Delete de claim en catch | Abre ventana a re-aplicación o pérdida según timing |

**Solución:** Transacción o `create` precondicionado + reconciliador de claims incompletos; pruebas de carrera; alternativa Event Store append-only.

---

### C7 — Cola offline se vacía antes de subir (CRÍTICO)

**Evidencia:** `firestore_sync_service.dart` `_vaciarColasYSubirPendientes` L257–296: copia cola → clear → persist empty → luego `subirX`.

**Escenario corte de luz / kill proceso mid-flush:** pendientes desaparecen de la cola aunque el upload no terminó.

**Solución:** Estados `pending | inflight | acked`; borrar solo tras ACK remoto; reintentos con backoff.

---

### C8 — Deletes offline no durables (CRÍTICO)

**Evidencia:** `eliminarRemitoRemoto` / `eliminarVentaRemota` / deletes cliente-proveedor retornan sin cola si no hay escritura remota. Soft-delete de productos existe; hard-delete de documentos comerciales no.

**Escenario:** Borrar remito/venta/cliente sin red → local desaparece → remoto sigue → al reconectar puede **reaparecer** o quedar divergente.

**Solución:** Tombstones durables (`deletedAt`, `deletedBy`, `opId`) sincronizados; never hard-delete sin tombstone ack.

---

### A1 — `admin/admin123` (ALTO)

Recovery default `true` en prefs. Reset de prefs / restore puede reabrir puerta. Hash conocido en seed DB.

**Fix:** Eliminar en builds comerciales; bootstrap con secreto único; recovery solo vía canal controlado.

---

### A2 — Permisos UI ≠ permisos reales (ALTO)

Solo `RemitoService.eliminar` y creación de usuarios exigen admin en servicio.  
`ProductoService.eliminar`, `ClienteService.eliminar`, `VentaService.eliminar/anular`, `CompraService.anular`, `StockService.registrarMovimiento`, etc. **sin guarda**.

Roles reales UI: `admin`, `encargado`, `empleado`.  
`solo_lectura`: en matriz, **no asignable**.  
`supervisor`: alias legacy de `encargado`.  
Firestore: solo `isMember` / `isTenantAdmin` — sin empleado/supervisor/lectura.

**Ataque:** build modificado o llamada directa a servicios → mutación local + sync a nube.

---

### A3–A5 — Permisos, usuarios, Storage (ALTO)

Cualquier miembro puede reescribir `config/permisos`, docs `usuarios` (roles), y leer/escribir todo Storage del tenant (<15MB, tipos amplios incl. `octet-stream`).

---

### A6 — Delete sync incompleto (ALTO)

Sets `_remitosConfirmadosEnNube` / clientes **en memoria**. Si el otro dispositivo estaba cerrado al borrar, al abrir el set está vacío → **no detecta ausencia**. Ventas/compras/proveedores: sin lógica equivalente.

Escenario “elimino en EXE, APK cerrado, luego abro APK”: puede seguir mostrando el remito (regresión parcial del fix reciente).

---

### A7 — Conflictos de edición (ALTO)

| Escenario | Comportamiento actual |
|---|---|
| 5 PCs editan producto | `set(merge:true)`; LWW parcial; última escritura efectiva gana campos |
| Edición stock en formulario | Puede subir **absoluto** y pisar deltas concurrentes |
| 2 usuarios editan mismo cliente | `forzar: true` saltea LWW remoto |
| 10 celulares remito mismo SKU | Deltas suman, pero sin freno stock negativo ni C6 |
| Internet intermitente | Cola C7 + deletes C8 + estado “En la nube” engañoso (A8) |
| Firestore lento | Timeouts/errores catch → UI puede marcar OK parcial |
| Storage caído | Producto sync OK sin foto remota |
| SQLite dañada | Open falla; sin repair path |

---

### A8 — Escala y falsa confianza (ALTO)

- Productos sync/watch: límite **10.000**.
- Catch-up ventas/remitos/compras: **2.000** recientes.
- Clientes/proveedores: `.get()` completo.
- Tras pull parcial con errores, `start()` puede setear **“En la nube”**.
- Búsqueda global: muestra ~800 productos iniciales.

Con 50k productos / 100k clientes / 500k movimientos: no hay diseño de paginación, índices, ni proyección.

---

### A9–A12 — Release, Android, backup, tests (ALTO)

- Workflows solo en ramas `cursor/*`, no `main`.
- CI: `pub get` + build; **0 tests**.
- Artefactos sin checksum/SBOM/firma.
- `applicationId = com.example.sistema_nuevo`.
- Sin Firebase App Check / Play Integrity.
- `isMinifyEnabled = false` (R8/ProGuard off).
- Windows: ZIP carpeta Release + BAT; sin MSI/firma Authenticode.
- Backup: copy `.db`; restore borra destino antes de copiar; fallo mid-copy = pérdida.
- Tests: búsqueda texto, texto producto, parser PDF. Faltan sync/stock/auth/permisos/migraciones/backup.

---

### M1–M9 / B1–B3 — (MEDIO / BAJO)

Ver matriz §2. Destacan: hashing débil, numeración race, migraciones silenciosas, AFIP stub (`afip_service` no autoriza de verdad), `FirestoreProductoRepository.eliminar` retorna 0, mega-archivo sync 2443 LOC, sin observabilidad central, README plantilla Flutter.

---

## 4. Simulación de escenarios (qué hace el código HOY)

| # | Escenario | Resultado demostrable |
|---|---|---|
| 1 | 5 PCs editan mismo producto | Campos merge; posible pérdida de cambios; stock absoluto puede pisar |
| 2 | 10 celulares venden mismo SKU (módulo Ventas) | Ventas OK; **stock intacto** |
| 3 | 10 celulares remiten mismo SKU | Stock baja por deltas; posible negativo; race en `stock_ops` |
| 4 | 2 usuarios editan mismo cliente | Último write gana (`forzar:true`) |
| 5 | Offline horas + cola + kill mid-sync | Pendientes pueden **perderse** (C7) |
| 6 | Delete remito offline | Local gone; remoto intacto → resurrección posible (C8) |
| 7 | Delete remito online, otro device cerrado | Set memoria vacío al abrir → remito puede quedar (A6) |
| 8 | Firestore down | App local sigue; sync falla; label puede mentir |
| 9 | Storage down | Productos sin foto en otros devices |
| 10 | SQLite corrupt | Crash al abrir; sin auto-repair |
| 11 | Restore backup falla mid-copy | DB destino ya borrada → pérdida local |
| 12 | Empleado llama `ProductoService.eliminar` | Éxito local + sync si es miembro |
| 13 | Empleado escribe `members/{uid}.rol=admin` | Posible si self-join/update propio (C1) |
| 14 | Otro tenant | Si conoce `tata_stock` y self-join → entra (C3) |
| 15 | Reinicio inesperado mid-anulación remito | Stock local/remoto pueden divergir según punto de falla |

---

## 5. Stock — integridad matemática

**No certificable hoy.**

Razones:
1. Canal Ventas ≠ canal Remitos respecto a stock.
2. `stock_ops` no atómico.
3. Movimientos locales `movimientos_stock` no se sincronizan como ledger.
4. Sin invariante “suma(deltas) + stock_inicial = stock_actual” verificable entre dispositivos.
5. Sin protección stock negativo server-side.
6. Ajustes absolutos desde UI pueden romper la secuencia de deltas.

**Requisito mínimo certificación inventarial:** ledger append-only + proyección de stock + reconciliación periódica + alarmas de divergencia.

---

## 6. Event Sourcing parcial — evaluación

| Dominio | ¿Conviene ES? | Estado actual | Recomendación 2.0 |
|---|---|---|---|
| Stock | **Sí** | Ops parciales no atómicas | Event store `stock_events` + proyección |
| Pagos / CC | **Sí** | Snapshot venta con pagos embebidos | Eventos de pago inmutables |
| Auditoría | **Sí** | Casi inexistente | Append-only `audit_log` |
| Productos/clientes | Híbrido | LWW documentos | Documentos + outbox; no ES full |
| Remitos/compras | Híbrido | Snapshots merge | Snapshot + eventos de ciclo de vida (crear/anular/borrar) |

**Ventajas ES (stock/CC):** idempotencia real, replay, auditoría, reconstrucción, multi-device seguro.  
**Desventajas:** complejidad, almacenamiento, necesidad de proyecciones, curva de aprendizaje, migración desde snapshots.

**Decisión arquitectónica recomendada:** Event Sourcing **parcial** solo en dinero e inventario; resto CQRS light (commands + documents).

---

## 7. Permisos — matriz real vs deseada

| Capacidad | Admin UI | Encargado UI | Empleado UI | Solo lectura | Enforcement servicio | Enforcement Firestore |
|---|---|---|---|---|---|---|
| Ver módulos | Matriz | Matriz | Matriz | Matriz* | Parcial | Solo membership |
| Crear productos | Matriz | Matriz | Matriz | — | No | Miembro = write |
| Eliminar productos | Matriz | Matriz | Matriz | — | **No** | Miembro = write |
| Eliminar remitos | Admin only (nuevo) | Oculto | Oculto | — | **Sí admin** | Miembro = write |
| Anular remitos | UI | UI | UI | — | **No** | Miembro = write |
| Eliminar ventas | UI | ? | ? | — | **No** | Miembro = write |
| Editar permisos | Página | — | — | — | **No** | Miembro = write |
| Self elevate role | — | — | — | — | N/A | **Posible** |

\* `solo_lectura` no asignable en UI.

**Conclusión:** los permisos **no son reales** a nivel de producto comercial. Ocultar botones no es seguridad.

---

## 8. Tenants

| Requisito | Estado |
|---|---|
| Aislamiento datos | Path `tenants/{id}/...` OK en estructura |
| Tenant no adivinable | **FAIL** — default conocido |
| Self-join off | **FAIL** — default true |
| Usuarios no compartidos | **FAIL** si mismo tenant |
| Storage aislado | Path OK; acceso por membership débil |
| Cross-tenant access | Posible vía C1+C3 |

---

## 9. Observabilidad (gap)

Hoy: `AppLog` append local; `debugPrint`; label sync binario.

Falta panel técnico admin con:
- sync count / latency p50-p95 / errores / conflictos
- ops por tipo / cola depth / inflight age
- memoria / tiempo apertura / query times
- divergencias stock (local vs cloud)
- version app + device tag + tenant

**Propuesta 2.0:** módulo `diagnostics` oculto (admin), export JSON, opcional Crashlytics/Sentry.

---

## 10. Performance — cuellos detectados

| Carga | Cuello |
|---|---|
| 50k productos | Límite 10k sync; listeners pesados; búsqueda 800 |
| 100k clientes | `.get()` completo; sin paginación UI/sync |
| 500k movimientos | Tabla local sin sync; reportes full scan |
| 20 usuarios / 5 PC / 15 móviles | Contención stock_ops + merge docs + bandwidth |
| Sync start | Sweep ausentes + catch-up + media retry en hilo cliente |

Optimizaciones requeridas: cursores, índices SQLite, proyecciones, sync incremental watermark, batching, isolate para imports, paginación UI.

---

## 11. Plugins / plataforma modular

**Estado:** shell por `modulo` hardcodeado; sin registry, sin DI formal, sin contratos de plugin, AFIP stub.

**Diseño 2.0 (sin implementar ahora):**
- Core: auth, tenant, sync engine, inventory ledger, CC ledger, catalog.
- Plugins: WhatsApp, ML, Woo, AFIP, e-commerce, dashboard, API.
- Install/uninstall = feature flags + tablas propias + no tocar schema core sin migración versionada.
- Sandbox permisos por plugin.

---

## 12. API pública (diseño, no implementación)

```
HTTPS /api/v1
Auth: OAuth2 client credentials + user tokens (JWT) scoped to tenant
Rate limit: per token / per tenant
Idempotency-Key en POSTs de stock/ventas/pagos
Resources:
  /products /customers /suppliers /sales /remitos /purchases /stock/events /payments
Permissions: scopes (products:read, stock:write, ...)
Versionado: URL /v1; deprecation headers
Audit: cada mutación → audit_log
Nunca exponer Firebase rules client keys como API
```

Gateway: Cloud Functions / Cloud Run delante de Event Store + proyecciones.  
Clientes Flutter **no** son la API.

---

## 13. Android / Windows checklist certificación

### Android
| Ítem | Estado |
|---|---|
| Google Sign-In | Presente; depende SHA configurado manual |
| Package comercial | **FAIL** `com.example.sistema_nuevo` |
| Keystore seguro | **FAIL** en repo |
| App Check / Play Integrity | **AUSENTE** |
| R8/ProGuard | **OFF** |
| Deep links | No auditado como producto |
| Developer Error / misconfig | Riesgo residual si SHA/package cambian |

### Windows
| Ítem | Estado |
|---|---|
| SQLite FFI + dll | Best-effort en CI |
| Firebase Desktop | Operativo en builds actuales |
| Instalador firmado | **AUSENTE** |
| Auto-update | **AUSENTE** |
| Backup/restore seguro | **DÉBIL** |

---

## 14. Calidad de código (muestra)

| Archivo | LOC | Nota |
|---|---:|---|
| `firestore_sync_service.dart` | 2443 | God object |
| `main_shell.dart` | 1315 | Navegación + permisos + UI |
| `configuracion_page.dart` | 1157 | |
| `auth_service.dart` | 1154 | Auth + recovery + Google |
| `database_helper.dart` | 1100 | Schema + migraciones |

Patrones: singletons abundantes, poco DI, tests pobres, AFIP muerto, `eliminar` remoto stub en productos.

---

## 15. Documentación

| Doc | Estado |
|---|---|
| ARCHITECTURE_CONTRACTS | Útil (F0–3) |
| CHECKLIST_PUESTA_EN_MARCHA | Manual |
| FIREBASE_* | Operativo |
| RELEASE_TRAIN | Incompleto (`main`) |
| README | Plantilla Flutter |
| Manual editorial | Marketing, no técnico de ops |
| Esta auditoría | Nueva |
| Roadmap 2.0 | Nueva (`ROADMAP_TATA_MANAGER_2_0.md`) |

---

## 16. Clasificación de riesgo residual para venta

| Modo de venta | ¿Viable? | Condición |
|---|---|---|
| Piloto 1 empresa, 1–2 PCs + 1–2 celulares, operadores de confianza | Condicional | Con monitoreo manual y backups diarios |
| Multi-sucursal / multi-usuario concurrente | **No** | Hasta cerrar C5–C8 + A7 |
| Multi-tenant SaaS | **No** | Hasta cerrar C1–C3 + claims |
| Play Store público | **No** | Hasta C4 + package + Integrity + R8 |
| ERP “competidor moderno” | **No** | Requiere Roadmap 2.0 fases A–D |

---

## 17. Próximo paso inmediato (sin code todavía)

1. Leer y aprobar este informe.
2. Priorizar backlog del Roadmap 2.0 (doc hermano).
3. **No mergear a ciegas** los drafts actuales a `main` sin plan de hardening.
4. Decidir: ¿el flujo de stock comercial es Remito, Venta, o ambos? (bloquea diseño C5).

---

*Fin del informe de auditoría. Ningún hallazgo CRÍTICO o ALTO debe considerarse “ya arreglado” hasta tener prueba automatizada + reproducción fallida negativa.*
