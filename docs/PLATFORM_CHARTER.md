# Carta de plataforma — Tata.Manager

| Campo | Valor |
|---|---|
| Estado | **Doctrina vigente** |
| Audiencia | CTO, arquitectura, seguridad, DevOps, QA, futuros equipos |
| Pregunta maestra | ¿Este diseño funciona con **500 empresas**, **5.000 usuarios**, **millones de movimientos** y **10 años de soporte**? |
| Si la respuesta es no | **Se descarta.** Sin excepciones por “es más rápido” o “es más fácil”. |
| ADR de dominio/core | **`ARCHITECTURE_PLATFORM.md` — VINCULANTE** (documentos ≠ movimientos; ledgers; Tata.Core; 4 niveles de permisos) |

Este documento **manda** sobre conveniencia de implementación, atajos de sync, y features de marketing.  
En filosofía de dominio, eventos, Core, plugins y calidad de release, **manda** `ARCHITECTURE_PLATFORM.md`.

No estamos construyendo una aplicación Flutter con Firebase.  
Estamos construyendo una **plataforma ERP multi-tenant** cuyos clientes (empresas) y módulos deben sobrevivir a cambios de equipo, de dispositivo y de escala.

---

## 1. Identidad del producto

| Somos | No somos |
|---|---|
| Plataforma multi-empresa | Una sola DB compartida “de la casa” |
| Núcleo + módulos versionados | Monolito accidental con pantallas nuevas |
| Contratos estables + migraciones | “Lo arreglamos en el cliente” |
| Autoridad de seguridad en servidor | Botones ocultos + rules permisivas |
| Ledgers de dinero e inventario | Números que “casi coinciden” entre PCs |
| Operación documentada 10 años | Conocimiento en la cabeza de un autor |

**Unidad de venta:** un **tenant** (empresa) aislado.  
**Unidad de despliegue cliente:** Windows + Android firmados, versionados, actualizables.  
**Unidad de extensión:** **módulo/plugin** con contrato, no un `if` en `main_shell`.

---

## 2. Filtro de decisión (obligatorio)

Antes de aprobar cualquier diseño, PR, regla Firebase, schema o integración, responder por escrito:

1. **Escala:** ¿Sigue correcto con 500 tenants y millones de eventos?
2. **Aislamiento:** ¿Un tenant puede leer/escribir otro? (debe ser imposible)
3. **Autoridad:** ¿Quién es la fuente de verdad bajo conflicto? (debe ser explícita)
4. **Falla:** ¿Qué pasa con corte de luz, red caída 8h, proceso matado mid-sync?
5. **Seguridad:** ¿Un cliente modificado o un SDK directo puede escalar privilegios?
6. **Operación:** ¿Otro equipo puede operar esto en 5 años solo con docs + runbooks?
7. **Evolución:** ¿Se puede versionar/migrar sin wipe ni downtime destructivo?
8. **Observabilidad:** ¿Podemos detectar divergencia antes que el cliente llame enojado?

Si alguna respuesta es débil → **rediseñar**, no “parchar y mergear”.

### Prioridades (orden fijo)

1. Estabilidad  
2. Seguridad  
3. Integridad de sync / dinero / stock  
4. Escalabilidad  
5. Simplicidad operacional  
6. Mantenibilidad multi-equipo  
7. Features nuevas  

La velocidad de entrega **no** está en la lista. La deuda que impide 10 años de soporte **tampoco** se acepta a cambio de demos.

---

## 3. Arquitectura de plataforma (objetivo)

```
                    ┌─────────────────────────────┐
                    │  Control plane (plataforma) │
                    │  tenants · billing · keys   │
                    │  invitations · claims       │
                    │  observability · support    │
                    └──────────────┬──────────────┘
                                   │
         ┌─────────────────────────┼─────────────────────────┐
         ▼                         ▼                         ▼
   Tenant A                   Tenant B                   Tenant N
   (aislada)                  (aislada)                  (aislada)
         │                         │                         │
    ┌────┴────┐               ┌────┴────┐               ┌────┴────┐
    │ Core    │               │ Core    │               │ Core    │
    │ API/CF  │               │ API/CF  │               │ API/CF  │
    │ Ledgers │               │ Ledgers │               │ Ledgers │
    └────┬────┘               └────┬────┘               └────┬────┘
         │                         │                         │
    Clients (Win/APK)         Clients (Win/APK)         ...
    SQLite = cache/ops        SQLite = cache/ops
    Outbox → sync             Outbox → sync
```

### Capas no negociables

| Capa | Responsabilidad | Prohibido |
|---|---|---|
| **Control plane** | Alta de empresas, invitaciones, claims, límites, soporte | Tenant hardcodeado compartido |
| **Tenant core** | Catálogo, partners, docs comerciales, config | Escritura anárquica desde cualquier miembro |
| **Ledgers** | Stock events, payment events, audit log | Stock “absoluto” concurrente multi-master |
| **Sync fabric** | Outbox, ACK, tombstones, watermarks | Borrar cola antes de confirmar |
| **Client apps** | UX + cache SQLite + outbox | Ser la autoridad de seguridad |
| **Modules** | AFIP, marketplaces, WhatsApp, API, BI | Acoplarse al schema core sin contrato |

### Fuente de verdad (SoT) a 10 años

| Dominio | SoT plataforma | Rol de SQLite |
|---|---|---|
| Dinero (CC, pagos) | Ledger de eventos del tenant | Proyección / offline |
| Inventario | Ledger de eventos de stock | Proyección / offline |
| Auditoría | Append-only inmutable | Copia local opcional |
| Catálogo / partners | Documento versionado + LWW/CAS server-side | Cache |
| Sesión / UX | Local | Local |
| Permisos efectivos | Claims + rules/API | Cache de matriz (no autoridad) |

El modelo actual “SQLite SoT operativo + Firestore bus permisivo” **no pasa el filtro** a 500 empresas. Se tolera solo como **estado legacy en migración**, no como diseño final.

---

## 4. Diseños descartados (no volver a proponerlos)

Estos patrones **fallan** la pregunta maestra. Quedan prohibidos como destino 2.0:

| Diseño | Por qué muere a escala / 10 años |
|---|---|
| Tenant default `tata_stock` para todos | Colisión masiva; soporte imposible; fuga entre clientes |
| `allowSelfJoin` / self-update de `rol` | Cualquier cuenta se hace admin del tenant |
| `allow write: if isMember` en todo el tenant | Empleado = dueño de los datos |
| Permisos solo ocultando UI | Builds modificados / SDK directo bypassean |
| Keystore y passwords en git | Compromiso de firma = compromiso de canal de update |
| Cola sync vaciada antes de ACK | Pérdida silenciosa bajo kill/power loss |
| Deletes hard sin tombstone durable | Resurrecciones; historiales distintos por sucursal |
| Confirmación de deletes en `Set` en memoria | Falla si la app estaba cerrada |
| `stock_ops` get→set→increment sin atomicidad | Doble movimiento o pérdida bajo concurrencia |
| Ventas y remitos con reglas de stock distintas | Inventario no certificable; soporte eterno de “faltan unidades” |
| Límites ocultos (2k catch-up, 10k productos) como “OK” | Clientes grandes se corrompen sin saberlo |
| God-object `FirestoreSyncService` eterno | Ningún equipo nuevo puede poseerlo con seguridad |
| Módulos = `switch` en shell | No es plataforma; es aplicación creciendo |
| API = exponer Firestore al mundo | Sin rate limit, sin versión, sin contrato |
| Wipe de DB como “migración” | Destruye confianza comercial |
| Features nuevas antes de cerrar integridad | Escala el caos, no el negocio |

---

## 5. Contratos de módulo (plataforma, no app)

Todo módulo nuevo (interno o futuro partner) debe cumplir:

1. **Contrato publicado** (inputs/outputs, permisos, eventos emitidos).  
2. **Schema propio versionado**; no mutar tablas core ad hoc.  
3. **Feature flag / install state** por tenant.  
4. **Desinstalable** sin romper ledgers core (puede dejar datos archivados).  
5. **Tests de contrato** en CI.  
6. **Runbook** de soporte (fallas típicas, rollback).  
7. **Dueño de equipo** documentado (CODEOWNERS o equivalente).

Núcleo mínimo que **no** es módulo opcional:

- Identidad / tenant / membership  
- Autorización  
- Catálogo (productos)  
- Partners (clientes/proveedores)  
- Ledgers stock + dinero  
- Sync fabric  
- Auditoría  
- Backup/restore certificado  
- Observabilidad básica  

Todo lo demás (AFIP, WhatsApp, ML, Woo, dashboards avanzados, API pública) es **módulo**.

---

## 6. Seguridad de plataforma

| Principio | Implicación |
|---|---|
| Least privilege | Rules/API por rol y por recurso |
| Server authority | Roles y deletes sensibles vía backend confiable |
| Tenant isolation | Paths + claims + tests de fuga cruzada |
| Supply chain | Secretos fuera del repo; builds firmados; provenance |
| Defense in depth | App Check + auth + rules + authz en servicio + audit |
| Recovery sin puerta trasera global | Sin `admin123` universal en campo |

---

## 7. Operación a 10 años (simplicidad operacional)

Preferir lo aburrido y observable:

- Un **release train** desde `main` con gates (analyze, tests, builds).  
- SemVer + changelog + canales (stable / preview).  
- Migraciones **forward-only**, idempotentes, con verificación de schema.  
- Backups con checksum + restore drill documentado.  
- Panel técnico admin: sync health, cola, divergencias, errores.  
- Runbooks: alta tenant, recuperación admin, divergencia stock, restore.  
- Nada que solo “el autor original sepa reiniciar”.

**Complejidad permitida** solo donde compra integridad (ledgers, outbox, authz).  
**Complejidad prohibida** en atajos locales que no escalan (flags mágicos, defaults compartidos, sync “best effort” silencioso).

---

## 8. Relación con documentos existentes

| Documento | Rol |
|---|---|
| **`ARCHITECTURE_PLATFORM.md`** | **ADR oficial vinculante** (dominio, eventos, Core, plugins, DR, calidad) |
| **`ENGINEERING_GOVERNANCE.md`** | **Gobernanza oficial** (simplicidad, métricas, NFRs, límites, calidad de código, release) — complementa, no modifica el ADR |
| **Esta carta** | Filtro CTO + diseños descartados |
| `ROADMAP_TATA_MANAGER_2_0.md` | Plan de migración a plataforma (Fases A–H) |
| `AUDITORIA_CERTIFICACION_2026-07.md` | Diagnóstico del estado aplicación actual |
| `ARCHITECTURE_CONTRACTS.md` | Contratos congelados del legado; cambiar solo con migración |
| `RELEASE_TRAIN.md` | Consolidar releases sin drafts eternos |
| `PR_ARCHITECTURE_CHECKLIST.md` | Gate obligatorio de PRs |

Ante conflicto entre “hacer que compile hoy” y estos docs: gana **`ARCHITECTURE_PLATFORM.md`**, luego esta carta, aplicando siempre **`ENGINEERING_GOVERNANCE.md`** (simplicidad medible).

---

## 9. Definición de éxito (plataforma)

Tata.Manager 2.0 es plataforma cuando:

1. Onboard de la empresa **501** no requiere un hack distinto a la **1**.  
2. Un empleado de la empresa A **no puede** tocar la B ni elevándose a sí mismo.  
3. Un millón de movimientos de stock/pagos son **reconstruibles** desde ledger.  
4. PC y celular **convergen** tras offline, kills y deletes (con pruebas automatizadas).  
5. Un equipo nuevo puede mantener un módulo con contrato + CI + runbook, sin al autor original.  
6. El soporte diagnostica con métricas, no con “probá reinstalar”.  
7. El canal de update es firmado y trazable.

Hasta entonces: **piloto controlado**, no venta masiva.

---

## 10. Próxima decisión de negocio (resuelta)

**Resuelta en `ARCHITECTURE_PLATFORM.md` §2:**  
Los documentos (venta / remito / factura) **no** mueven stock.  
Solo eventos de dominio (`MERCADERIA_ENTREGADA`, `DEVOLUCION_RECIBIDA`, `TRANSFERENCIA_CONFIRMADA`, `AJUSTE_INVENTARIO`, `MERCADERIA_RECIBIDA`, …).

Cualquier PR que haga “venta baja stock como remito” o “remito llama StockService directo sin evento” **viola** la arquitectura oficial y se rechaza.

Siguiente decisión operativa: política por tenant de *cuándo* se emite `MERCADERIA_ENTREGADA` (al confirmar venta, al emitir remito, al despachar, etc.) — siempre como evento explícito, nunca como efecto colateral del documento.

---

*Carta viva. Toda excepción requiere registro escrito de por qué pasa el filtro 500 / 5.000 / millones / 10 años — o se rechaza.*
