# Auditoría Integral y QA — Tata.Manager (v2 post-fixes)

**Fecha:** 2026-07-26  
**Versión auditada:** `1.2.35+40`  
**Rama:** `cursor/fix-p0-auditoria-integridad-e44b` @ `5e7072d`  
**Suite automática:** `flutter test` → **94/94 OK**  
**Equipo simulado:** QA Senior · Software Tester · Arquitecto · Auditor ERP · UX/UI · Security · Flutter Senior · Firebase · SQLite  

### Metodología y límites

| Hecho en esta pasada | No hecho en este entorno |
|---|---|
| Revisión adversarial de código módulo a módulo | UI interactiva del `.exe` / APK físico |
| Verificación de fixes P0/P1 con tests de comportamiento | 10.000 productos / 100 usuarios reales |
| Lectura de sync/outbox/ledgers/rules | Medición FPS/CPU en hardware |
| Walkthrough mental de escenarios destructivos | Campo Windows↔Android con 2 devices |
| Evidencia de crashes históricos en campo | AFIP/Meta API reales |

**Etiquetas de certeza**

| Etiqueta | Significado |
|---|---|
| **PRODUCIDO** | Demostrado por test automático en esta sesión |
| **OBSERVADO EN CAMPO** | Crash/comportamiento visto por usuario/agente |
| **HIPÓTESIS DE CÓDIGO** | Ruta leída; no ejecutada en UI real |
| **NO VERIFICABLE AQUÍ** | Requiere device / red / certificados |

**Regla:** no se asume que “compila ⇒ funciona”. Los fixes P0/P1 se dan por **cerrados solo con evidencia**.

---

## 1. Resumen Ejecutivo

Tata.Manager es un ERP Flutter offline-first con SQLite local, outbox, ledgers de inventario/dinero y sync Firestore. Tras la oleada de correcciones **1.2.34–1.2.35**, los fallos más graves de integridad de dominio que la auditoría anterior demostró (factura sin stock, códigos vacíos, límite CC inútil, hard-delete sin tombstone, stock negativo por default, AFIP que “guardaba OK” sin CAE) **quedaron cerrados en código y tests**.

Eso **no** convierte al producto en APTO PARA PRODUCCIÓN comercial amplia.

Siguen abiertos vectores que pueden **perder stock, dinero o datos** bajo uso real multi-dispositivo o bajo carga Windows:

1. **Anular/eliminar factura** aún puede dejar stock sin devolver (TX no unificada / delete sin anular).  
2. **Compras** siguen aplicando stock *después* del commit; la 2ª edición de compra puede no mover stock (eventId fijo).  
3. **Remito + Factura** sobre la misma entrega **doble-bajan** stock (no hay vínculo documento).  
4. **Catch-up inicial Windows** sigue haciendo `.get()` completo de ventas/remitos/clientes.  
5. **AFIP real** no existe: con AFIP on se bloquea (correcto), pero no hay emisión fiscal verdadera.  
6. Paths de stock **absoluto** (formulario/import) siguen bypasseando el ledger.

**Estado general: NO APTO PARA PRODUCCIÓN** (piloto controlado: sí, con reglas operativas estrictas).

**Nota de progreso:** respecto a la auditoría matutina del mismo día, el sistema pasó de “integridad rota en el canal de facturas” a “integridad parcialmente certificable en alta de venta/remito”, con deuda concentrada en compras, anulación de facturas, sync Windows y modelo fiscal.

---

## 2. Hallazgos

### 2.1 Cerrados en esta versión (evidencia)

| ID previo | Hallazgo | Evidencia de cierre | Certeza |
|---|---|---|---|
| C1 | Facturas no movían stock | `crearVentaConPago` → `applyInTxn` + tests adversariales | PRODUCIDO |
| C3 | Código vacío/duplicado | Validación servicio + UNIQUE parcial schema 33 | PRODUCIDO |
| A3 | Stock negativo default ON | `IntegrityPolicy` default `false` | PRODUCIDO |
| A4 | `limiteCuenta` no bloqueaba | `assertDentroLimiteCuenta` | PRODUCIDO |
| A1 | Double-tap Finalizar | Flags `_finalizando`/`guardando` antes de await | HIPÓTESIS DE CÓDIGO + guardas en código |
| C4 | Hard-delete producto solo local | `eliminarProductoRemoto` + outbox delete | PRODUCIDO |
| A5 | Saldo CC pisable a mano | `ClienteService.actualizar` preserva saldo DB | PRODUCIDO |
| C2 (parcial) | Remito/factura create mid-crash | Ledger en misma TX al **crear** remito/venta | HIPÓTESIS DE CÓDIGO (tests crean OK) |
| C5 (parcial) | Race stock_ops | Si op existe → no re-incrementa | HIPÓTESIS DE CÓDIGO |
| A6 | AFIP confirma sin CAE | Gate en `venta_factura_page` | HIPÓTESIS DE CÓDIGO |
| M12 | CUIT basura | `Cuit.esValido` módulo 11 | PRODUCIDO (unit) |
| A7 | Password sin salt | KDF `v2$salt$hash` + migrate login | PRODUCIDO (unit) |
| A8 | Token WA plaintext | `SecureLocalStore` | HIPÓTESIS DE CÓDIGO |
| A2 (parcial) | Soft pull Windows unbounded | Páginas 80 docs clientes/ventas/remitos | HIPÓTESIS DE CÓDIGO |

---

### 2.2 Abiertos — Críticos 🔴

#### R1 — Anular factura: stock/money fuera de TX
- **Módulos:** Facturación / Inventario / CC  
- **Evidencia:** `lib/services/venta_service.dart` `anular` — UPDATE `estado=anulada` y luego `DomainEventBus.publish` de reverso.  
- **Repro:** Anular Factura B; matar proceso entre UPDATE y publish.  
- **Impacto:** Documento anulado; stock **no** vuelve; CC inconsistente.  
- **Certeza:** HIPÓTESIS DE CÓDIGO  
- **Solución:** Misma TX que remito (`applyInTxn` + `appendInTxn` + update estado).  
- **Prueba concreta:** Anular factura en Windows con Process Explorer matando el `.exe` al snackbar “anulada”; verificar stock.

#### R2 — Eliminar factura sin anular = stock perdido para siempre
- **Evidencia:** `VentaService.eliminar` borra pagos/items/venta; UI puede llamar sin `anular` previo (`venta_factura_page`).  
- **Repro:** Factura confirmada → Eliminar (no Anular).  
- **Impacto:** Stock queda bajo; ledger sin reverso; tombstone nube sin compensación.  
- **Certeza:** HIPÓTESIS DE CÓDIGO  
- **Solución:** Exigir anular atómico antes de hard-delete; bloquear delete si no está anulada.

#### R3 — Compras: stock post-commit + 2ª edición con eventId fijo
- **Evidencia:** `compra_service.dart` publish recepción **después** de TX; edit usa `inv:recepcion:compra:$id:edit` fijo → 2ª edición idempotent-skip.  
- **Repro:** (a) Crash tras guardar compra; (b) Editar cantidades dos veces.  
- **Impacto:** Compra sin stock / stock congelado en 1ª edición.  
- **Certeza:** HIPÓTESIS DE CÓDIGO  
- **Solución:** `applyInTxn` en create/anular/edit; eventIds con revision/uuid.

#### R4 — Remito + Factura = doble entrega de stock
- **Evidencia:** `Venta.mueveStock` para todo excepto presupuesto; no hay `remitoId` en ventas.  
- **Repro:** Remito 3 u → Factura B mismas 3 u → stock −6.  
- **Impacto:** Sobreventa; inventario mentiroso; CC puede doblar deuda.  
- **Certeza:** HIPÓTESIS DE CÓDIGO (modelo)  
- **Solución:** Vincular factura↔remito; factura desde remito con `mueveStock=false`.

#### R5 — Stock absoluto bypassa ledger (formulario / import)
- **Evidencia:** `producto_form_page` edita `stock`; `ProductoService.actualizar` con `incluirStockAbsoluto`; import CSV pisa stock.  
- **Repro:** Remito baja stock; editar producto stock a mano; sync peer.  
- **Impacto:** `productos.stock` ≠ suma ledger; pelea con `stock_ops`.  
- **Certeza:** HIPÓTESIS DE CÓDIGO  
- **Solución:** Cambios de stock solo vía evento `AJUSTE_INVENTARIO`; import genera ajustes.

---

### 2.3 Abiertos — Altos 🟠

#### R6 — Catch-up inicial Windows sigue con `.get()` completo
- **Evidencia:** `_pullInicialCatchUp` full get de clientes/proveedores/ventas/remitos/compras/documentos.  
- **Impacto:** OOM / crash `.exe` en tenants grandes (**OBSERVADO EN CAMPO** históricamente).  
- **Solución:** Paginar todas las colecciones; cero full-get en Windows.

#### R7 — Soft-pull Windows no rota compras/proveedores/documentos
- **Evidencia:** `_pullSuaveWindows` solo clientes/ventas/remitos/productos.  
- **Impacto:** Drift permanente post catch-up para compras/proveedores.  
- **Solución:** Round-robin de páginas por colección.

#### R8 — `clientes.saldo` recalculado vs money_ledger pueden divergir
- **Evidencia:** `recalcularSaldoCliente` desde SUM documentos; `actualizarEstadoPago` cambia saldo sin eventos money.  
- **Impacto:** CC UI ≠ ledger; reconciliación puede “verse sana” mal.  
- **Solución:** Saldo = proyección del money ledger; eliminar atajos de estado sin eventos.

#### R9 — Toggle cobro remito: reverso money con eventId fijo
- **Evidencia:** `money:remito_cobro_rev:$id` fijo → 2º ciclo cobrado↔pendiente no revierte.  
- **Solución:** IDs por ciclo/revisión.

#### R10 — Rules: empleado puede soft-wipe con `set`/`update`
- **Evidencia:** `firestore.rules` — delete es admin, pero tombstone/overwrite vía `set(merge)` permitido a `canWriteOps`.  
- **Impacto:** Empleado borra catálogo vía merge destructivo.  
- **Solución:** Tombstones solo admin/encargado; `hasOnly` en updates.

#### R11 — Hard tombstone producto puede no hard-deletear en peers
- **Evidencia:** `esTombstoneRemoto` exige descripción vacía; merge puede conservar descripción.  
- **Impacto:** “Eliminar definitivo” no converge.  
- **Solución:** Flag `tombstone:true` manda hard-delete siempre.

#### R12 — Storage: path `branding/` bloqueado por rules nuevas
- **Evidencia:** `branding_service` sube a `tenants/.../branding/`; rules permiten solo productos/clientes/documentos/usuarios/chats/pdfs/misc.  
- **Impacto:** Logo no sincroniza.  
- **Solución:** Permitir `branding` o usar `misc/branding`.  
- **Nota deploy:** `firebase deploy --only firestore:rules,storage` pendiente en campo.

#### R13 — Conflictos LWW invisibles al operador
- **Evidencia:** `recordConflict` solo cuenta en panel técnico; upload `remote_wins` silencioso.  
- **Impacto:** Pérdida silenciosa de ediciones.  
- **Solución:** Inbox de conflictos + opción forzar.

#### R14 — Outbox reclaim 90s vs jobs stock Windows 18s+
- **Evidencia:** Pump reclaim 90s; stock cloud delay 18s.  
- **Impacto:** Reclaim prematuro / thrash (mitigado en stock_ops por idempotencia).  
- **Solución:** TTL por tipo + heartbeat.

#### R15 — Biometría no migra hash / no revalida password
- **Evidencia:** `loginConHuella` no llama `_upgradePasswordHashIfNeeded`.  
- **Impacto:** Usuarios solo-huella quedan en SHA-256 legado.  
- **Solución:** Forzar password periódico o upgrade en próximo login con clave.

---

### 2.4 Abiertos — Medios 🟡

#### R16 — UNIQUE parcial: restore de papelera choca con código activo
- Soft-delete libera código; alta nueva + restore → conflicto índice.

#### R17 — KPIs mezclan remitos + facturas como “ventas”
- `analytics_service` UNION; con R4 dobla métricas.

#### R18 — Factura B/C guardan `iva=0`; toggle IVA no está en UI Config
- Flag existe en prefs; sin control visible en Configuración.

#### R19 — Accesos rápidos Inicio silenciosos sin permiso
- `_irAModulo` no-op sin snackbar.

#### R20 — `venta_factura_page` ~1090 LOC (god page)
- Alto riesgo de regresión fiscal/stock.

#### R21 — Proveedor delete sin `syncId` no encola tombstone
- Remoto puede quedar huérfano.

#### R22 — Clientes: sin UNIQUE teléfono/CUIT
- Duplicados comerciales permitidos.

#### R23 — PDF share inmediato en Windows aún en rutas manuales
- Auto-PDF diferido; Compartir/Imprimir siguen síncronos (crash histórico).

---

### 2.5 Abiertos — Bajos 🟢

#### R24 — LWW producto: local gana metadata pero pisa stock remoto absoluto
#### R25 — Textos cortados / overflow en listas densas (NO VERIFICABLE AQUÍ sin UI)
#### R26 — Dark mode inconsistente (NO VERIFICABLE AQUÍ)
#### R27 — Emojis/caracteres especiales en descripciones: SQLite tolera; PDF puede fallar (HIPÓTESIS)

---

## 3. Riesgos (pérdida de datos / dinero / stock)

| Riesgo | Probabilidad en piloto | Impacto | Mitigación operativa hasta fix |
|---|---|---|---|
| Stock doble por remito+factura | Alta si usan ambos canales | Crítico | **Solo remitos** como entrega; factura fiscal desactivada o solo presupuesto interno |
| Anular/eliminar factura sin devolver stock | Media | Crítico | No eliminar facturas; solo anular tras verificar stock; backup diario |
| Compra editada 2 veces | Media | Alto | No reeditar compras; anular y recrear |
| Catch-up Windows tumba `.exe` | Alta con catálogo grande | Alto | Sync opcional; APK como maestro temporal |
| Conflicto LWW silencioso | Media multi-device | Alto | Un operador a la vez por SKU/cliente |
| Empleado wipe vía Firestore set | Baja (requiere cliente malo) | Alto | Roles: pocos empleados con write; deploy rules |
| AFIP on sin integración | Media | Bloqueo operativo (no pérdida) | Dejar AFIP **off** hasta WSAA/WSFE |

---

## 4. Mejoras recomendadas antes de publicar

### Bloqueantes (hacer antes de “producción”)
1. Anular/eliminar factura atómico + obligatorio anular antes de delete.  
2. Compras: ledger in-TX + eventIds únicos por edición.  
3. Modelo entrega única: factura↔remito o un solo canal de stock.  
4. Prohibir stock absoluto fuera de `AJUSTE_INVENTARIO`.  
5. Catch-up Windows 100% paginado (todas las colecciones).  
6. Deploy rules actualizadas + path `branding`.  
7. Inbox de conflictos LWW visible al admin.

### Importantes (sprint siguiente)
8. Saldo CC = money ledger.  
9. Soft-pull rotativo compras/proveedores/documentos.  
10. UI toggle IVA / AFIP precios.  
11. UNIQUE CUIT opcional; validar teléfono.  
12. Split `venta_factura_page`.  
13. Biometría + upgrade hash.  
14. TTL outbox por tipo.

### Operativos
15. Runbook: “piloto = remitos + 1 PC + 1 celular + sync consciente”.  
16. Backup SQLite programado antes de cada sync masivo.

---

## 5. Arquitectura

### Fortalezas
- Separación plugins (WhatsApp/CRM) fuera del outbox core.  
- Ledgers append-only + `domain_events` idempotentes.  
- Outbox durable + tombstones (Capacidad 7) en varias entidades.  
- Domain bootstrap / AuthorizationService en mutadores.  
- Modo estable Windows parcialmente implementado.

### Debilidades
- **Dos canales de entrega** (remito/factura) sin agregación de dominio.  
- **Proyección dual** de saldo (documentos vs ledger) y de stock (columna vs ledger).  
- Sync con **tres modos** (listeners / soft-pull / catch-up) incompletos entre sí.  
- Páginas UI monolíticas (factura, shell).  
- AFIP como stub con gate — arquitectura fiscal incompleta.

**Calidad arquitectónica:** ambiciosa y mejorando, aún **inconsistente en invariantes de dominio**.

---

## 6. UI / UX

### Observado en código / hipótesis
- Shell por módulos con permisos: bien encaminado.  
- Venta rápida: flujo corto; double-tap mitigado.  
- Factura: denso, AFIP/CUIT/IVA/cobro en una sola pantalla (~1090 LOC).  
- Inicio: KPIs que navegan en silencio si el módulo está oculto.  
- Config AFIP: falta toggle “precios incluyen IVA” pese a existir en prefs.  
- Panel técnico: útil para ops, opaco para el dueño no técnico.

### Riesgos UX
- Usuario factura + remite “para hacer las cosas bien” y **rompe stock** (R4).  
- Mensajes de sync/crash históricos generan desconfianza; mitigações existen pero requieren re-test de campo en `1.2.35+40`.

**NO VERIFICABLE AQUÍ:** overflow, dark mode, rotación Android, densidad real de pantallas.

---

## 7. Rendimiento

| Área | Estado | Evidencia |
|---|---|---|
| Soft-pull Windows | Mejorado (páginas 80) | Código |
| Catch-up inicial Windows | **Sigue peligroso** | Full `.get()` |
| Listeners productos | Limitados / diferidos en Windows | Código |
| Inicio carga remitos | Puede traer todos para 3 cards | `inicio_page` |
| PDF Windows | Diferido en auto; share manual riesgo | Código + campo histórico |
| 100k SKUs | No certificado | NO VERIFICABLE |
| Rebuilds/FPS | No medido | NO VERIFICABLE |

**Punto débil #1:** primer sync Windows con historial grande.  
**Punto débil #2:** valorización/listados sin paginación UI agresiva en todas las pantallas.

---

## 8. Seguridad

| Control | Estado |
|---|---|
| Auth local hash | Mejorado (v2 salt+KDF); legado migrable |
| Biometría | No fuerza upgrade hash |
| AuthorizationService | Presente en mutadores clave |
| Firestore rules | Mejoradas; tombstone vía set aún amplio |
| Storage rules | Allowlist carpetas; falta `branding` |
| Token WhatsApp | Ofuscado device-bound ≠ HSM |
| SQL injection | Queries parametrizadas sqflite (bien) |
| Secretos en cliente | Tokens Meta/AFIP paths en dispositivo |
| Multi-tenant | Path tenants + members |

**Veredicto seguridad:** aceptable para piloto cerrado; **insuficiente** para multi-empresa / empleados no confiables / compliance fiscal.

---

## 9. Escalabilidad

| Escenario | Evaluación |
|---|---|
| 1–2 PCs + 1–2 celulares, <5k SKUs, un operador | Viable con disciplina (remitos, sync consciente) |
| 100 usuarios concurrentes | **No** — sin backend de autorización fuerte, LWW silencioso, catch-up pesado |
| 1.000 usuarios | **No** |
| 100.000 productos | **No certificado** — índices SQLite OK-ish; sync/UI no |
| Múltiples empresas (tenants) | Modelo tenant existe; onboarding/rules/ops incompletos para SaaS |

---

## 10. Veredicto Final

### Notas (1–10)

| Dimensión | Nota | Justificación breve |
|---|---|---|
| Arquitectura | **6.5** | Ledgers/outbox sólidos; invariantes de entrega rotos (R4) |
| Calidad del código | **6.0** | Mejoras P0/P1 reales; god-pages y caminos dobles |
| UI | **5.5** | Funcional; factura/config densas; sin prueba visual aquí |
| UX | **5.0** | Flujos peligrosos (remito+factura); silencios de permiso |
| Rendimiento | **4.5** | Soft-pull ok; catch-up Windows sigue bomba |
| Seguridad | **6.0** | KDF+rules mejor; wipe set y tokens locales |
| Escalabilidad | **3.5** | Piloto sí; 100 usuarios / 100k SKUs no |
| Mantenibilidad | **5.5** | Capacidades documentadas; deuda concentrada |
| Experiencia de usuario | **5.0** | Crash histórico Windows; confianza frágil |
| Preparación producción | **4.0** | Integridad parcial; fiscal stub; sync incompleto |

### Conclusión

# NO APTO PARA PRODUCCIÓN

**Evidencia técnica:**

1. Invariante de inventario aún rompible (R2, R3, R4, R5) — un ERP no puede publicar con doble entrega y delete sin reverso.  
2. Sync Windows catch-up aún unbounded — historial de crashes en campo no cerrado del todo.  
3. Fiscal: AFIP no emite CAE; solo bloquea. No es sistema de facturación electrónica.  
4. Multi-dispositivo: conflictos LWW silenciosos + soft-pull incompleto.  
5. Escalabilidad no demostrada más allá de piloto.

### Sí es apto como
**Piloto controlado** si se impone:

- Canal de entrega = **solo Remitos / Venta rápida**.  
- Facturas A/B/C **apagadas** o solo internas con AFIP **off**.  
- Máx. 2 dispositivos; un editor a la vez por entidad.  
- Build **1.2.35+40** + deploy de rules.  
- Backup diario.  
- No reeditar compras; no hard-delete facturas.  
- Re-test campo Sync + Venta rápida en Windows antes de ampliar usuarios.

---

## Anexo A — Matriz módulo × estado

| Módulo | Estado post-1.2.35 | Riesgo residual principal |
|---|---|---|
| Inicio | Parcial | KPI mixtos; nav silenciosa |
| Dashboard | Parcial | Valor stock a precio venta |
| Productos | Mejorado | Stock absoluto / restore UNIQUE |
| Clientes | Mejorado | Duplicados CUIT/tel; LWW |
| Proveedores | Parcial | Tombstone si syncId vacío |
| Venta rápida | Mejorado | Re-test crash Windows |
| Remitos | Mejorado (create/anular TX) | Toggle cobro money id |
| Facturación | Mejorado create; **malo anular/delete** | R1 R2 R4 |
| Compras | **Débil** | R3 |
| Cuenta corriente | Mejorado límite | Divergencia ledger |
| Inventario | Mejorado política | Bypasses absolutos |
| Sync/Outbox | Mejorado parcial | Catch-up / soft-pull huecos |
| WhatsApp/CRM | Plugin aislado | Token ofuscado; Meta no probada |
| AFIP | Gate seguro; stub | Sin CAE real |
| Windows | Mitigado | Catch-up + PDF share |
| Android | NO VERIFICABLE AQUÍ | Rotación/multitarea |

## Anexo B — Protocolo de re-test campo (obligatorio)

1. Instalar `1.2.35+40` en PC + APK.  
2. Producto stock 10 → Factura B ×3 → stock **7**.  
3. Remito ×2 mismas unidades → stock **5** (documentar; ideal = bloquear).  
4. Anular factura → stock debe volver (hoy: verificar R1).  
5. Compra + editar 2 veces → anotar stock.  
6. Sync catch-up en PC con >2k docs → ¿crash?  
7. AFIP on → factura debe **bloquear**.  
8. Double-tap venta rápida → 1 remito.  
9. Hard-delete producto → peer no revive.  
10. Cortar net mid-venta → outbox drena al volver.

## Anexo C — Referencias

- Tests: `test/auditoria_comportamiento_adversarial_test.dart`, `test/auditoria_p1_seguridad_cuit_test.dart`  
- Walkthrough anterior: `docs/AUDITORIA_WALKTHROUGH_TESTER_2026-07-26.md` (rama docs)  
- PR fixes: https://github.com/arcuriciro-gif/sistema_nuevo/pull/66  
