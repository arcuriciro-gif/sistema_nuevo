# Roadmap Tata.Manager 2.0 — De aplicación a plataforma

Basado en `docs/AUDITORIA_CERTIFICACION_2026-07.md`.  
Gobernado por `docs/ARCHITECTURE_PLATFORM.md` (**ADR vinculante**), `docs/PLATFORM_CHARTER.md` y `docs/ENGINEERING_GOVERNANCE.md` (**simplicidad + métricas + NFRs**).

**Filtro de toda fase:** ¿Funciona con 500 empresas, 5.000 usuarios simultáneos, millones de movimientos, multi-dispositivo y 10 años?  
Si no → la entrega de esa fase se rediseña; no se “simplifica” violando el ADR ni se “complejiza” sin beneficio medible.

Prioridad fija: **integridad > seguridad > consistencia > escala > simplicidad operacional > mantenibilidad > features**.

No se implementa código en este documento. Es el plan de certificación **de plataforma**.

---

## Visión 2.0

Tata.Manager deja de ser “app Flutter con sync Firebase” y pasa a ser **plataforma ERP multi-tenant** según `ARCHITECTURE_PLATFORM.md`:

- Control plane (alta de empresas, invitaciones, claims)
- **`Tata.Core`** desacoplado del rubro + verticales/plugins
- **Documentos ≠ movimientos**; eventos de dominio → ledgers
- Event Bus interno (sin cadenas Ventas→Stock→Caja→Firebase)
- Sync fabric (outbox, ACK, tombstones, watermarks, versionado de contrato)
- Permisos en 4 niveles (UI → caso de uso → servicio → servidor)
- Observabilidad + health check + disaster recovery demostrable
- Release train con tests obligatorios; checklist arquitectónico en cada PR

Todo diseño listado como **descartado** en la Carta / incompatible con el ADR queda fuera de este roadmap.

---

## Fases 2.0 (orden obligatorio)

### Fase A — Freeze & Hardening de seguridad (bloqueante)

**Objetivo:** dejar de sangrar datos / roles / firma.

| # | Entrega | Cierra |
|---|---|---|
| A1 | Rotar keystore; secretos solo en CI; Play App Signing | C4 |
| A2 | `allowSelfJoin=false`; members solo admin/Function; bloquear self-elevate | C1 |
| A3 | Rules por rol/colección; `config/permisos` y `usuarios.rol` protegidos | C2, A3, A4 |
| A4 | Tenant ID único por empresa; migrar fuera de `tata_stock` compartido | C3 |
| A5 | App Check (Android + Windows donde aplique) | A10 |
| A6 | Eliminar `admin123` de builds comerciales; recovery controlado | A1 |
| A7 | Storage rules por path + rol; quitar `octet-stream` amplio | A5 |

**DoD:** pentest interno de reglas; intento de escalate falla; keystore no en git.

---

### Fase B — Sync & integridad (bloqueante comercial)

**Objetivo:** offline, deletes, colas y conflictos predecibles.

| # | Entrega | Cierra |
|---|---|---|
| B1 | Cola outbox durable: `pending→inflight→acked` | C7 |
| B2 | Tombstones para deletes (ventas/remitos/compras/clientes/proveedores) | C8, A6 |
| B3 | Watermarks persistentes por colección (no sets en memoria) | A6 |
| B4 | LWW/compare-and-set uniforme; prohibir `forzar:true` salvo admin recovery | A7 |
| B5 | Estado sync por colección (nunca “En la nube” si hay error parcial) | A8 |
| B6 | Catch-up paginado completo (sin techo 2k oculto) | A8 |

**DoD:** chaos tests: kill mid-sync, offline 8h, delete cruzado PC↔APK con app cerrada.

---

### Fase C — Inventario & dinero (bloqueante ERP)

**Objetivo:** ledgers certificables según `ARCHITECTURE_PLATFORM.md` §2–4.

| # | Entrega | Cierra |
|---|---|---|
| C1 | **Hecho (ADR):** documentos no mueven stock; solo eventos de dominio | Decisión de dominio |
| C2 | Event store `inventory_events` / `money_events` append-only + proyección | C5, C6 auditoría |
| C3 | Emisión explícita de `MERCADERIA_ENTREGADA` / `RECIBIDA` / etc. (nunca efecto colateral del doc) | filosofía dominio |
| C4 | Un solo `eventId` por hecho físico; prohibido doble documento → mismo movimiento | §2 ADR |
| C5 | Ledger CC/pagos/caja reconstructible; anulación = nuevo evento | ES parcial |
| C6 | Event Bus: listeners Stock/Caja/CC/Audit/Sync desacoplados | §5 ADR |
| C7 | Política tenant de *cuándo* emitir entrega (configurable, no hardcode en Core) | verticales |
| C8 | Invariante reconciliable + alarma divergencia; stock negativo configurable | integridad |

**DoD:** replay de eventos = saldos; 10k ops concurrentes; ningún `RemitoService`/`VentaService` muta stock directo.

---

### Fase D — Autorización real & auditoría

| # | Entrega | Cierra |
|---|---|---|
| D1 | `AuthorizationService` en **todos** los servicios mutadores | A2 |
| D2 | Roles completos: admin / encargado / empleado / solo_lectura (asignables) | B1 roles |
| D3 | Mirror de roles en custom claims + rules | C2 |
| D4 | `audit_log` append-only (quién/qué/cuándo/antes/después) | observabilidad |
| D5 | Hash passwords Argon2id + migración | M1 |

**DoD:** tests negativos por rol; intento directo a servicio falla.

---

### Fase E — Datos locales, backup, migraciones

| # | Entrega | Cierra |
|---|---|---|
| E1 | `PRAGMA integrity_check` al abrir; quarantine `.bad` + restore | M4 |
| E2 | Restore atómico (temp + rename); checksum; dry-run | A11 |
| E3 | Migraciones: fallar fuerte si ALTER real falla | M5 |
| E4 | Numeración con reserva transaccional | M3 |
| E5 | Backup cifrado opcional + retención | A11 |

---

### Fase F — Release train profesional

| # | Entrega | Cierra |
|---|---|---|
| F1 | Consolidar PRs probados → `main` con gates | RELEASE_TRAIN |
| F2 | CI en `main`: analyze + tests + build Android/Windows | A9, A12 |
| F3 | Artefactos con checksum + SBOM + provenance | A9 |
| F4 | Package Android comercial (`com.eltatamanager.app`) — **solo con plan migración** | A10 / Fase 5 legacy |
| F5 | R8/ProGuard on + mapping archivado | A10 |
| F6 | Windows: instalador (Inno/MSIX) + Authenticode | B2 |
| F7 | Versionado semver + changelog + canal update | Windows updates |

---

### Fase G — Observabilidad & performance

| # | Entrega | Cierra |
|---|---|---|
| G1 | Panel técnico admin (sync, errores, colas, memoria, queries) | §9 |
| G2 | Crash reporting (Sentry/Crashlytics) | M8 |
| G3 | Paginación sync/UI; índices; quitar límites ocultos | A8 |
| G4 | Benchmarks 50k productos / 100k clientes | §10 |
| G5 | Media queue por archivo | M6 |

---

### Fase H — Plataforma (después de A–G estables)

| # | Entrega |
|---|---|
| H1 | Core vs plugins (contratos, feature flags) |
| H2 | Diseño API pública `/api/v1` (auth, scopes, rate limit, idempotency) — **diseño primero** |
| H3 | AFIP real (reemplazar stub) |
| H4 | Conectores: WhatsApp / ML / Woo (opcionales) |
| H5 | Refactor `FirestoreSyncService` → módulos (sync engine + adapters) |

---

## Prioridad de implementación sugerida

```
A (seguridad) → B (sync) → C (stock/dinero) → D (authz) → E (DB) → F (release) → G (ops) → H (plataforma)
```

Cualquier feature nueva (UX, módulos) **se pospone** si abre huecos en A–C.

---

## Criterios de “certificado 2.0”

1. Pentest reglas: no self-elevate, no cross-tenant, no write de empleado a config/usuarios.
2. Chaos sync: 0 pérdida de cola; deletes convergentes PC↔APK con app cerrada.
3. Stock: replay de eventos = stock proyectado en N dispositivos.
4. CI verde en `main` con tests de sync/stock/auth/migraciones.
5. Keystore fuera del repo; builds firmados.
6. Backup/restore con integrity check y prueba de restauración documentada.
7. Roles solo_lectura verificados por test negativo.
8. Documentación ops: instalación, recuperación, versionado, runbooks.

---

## Qué NO hacer todavía

- Renombrar package Android sin plan de migración (Play + Firebase + SHA).
- Wipe de DB de clientes.
- Reescribir todo a “Firestore SoT puro” de golpe.
- Implementar API pública antes de A–C.
- Agregar marketplaces antes de stock certificable.
- Mergear todos los drafts a `main` sin gates.

---

## Decisión de dominio (Fase C) — RESUELTA

**Resuelta** por `ARCHITECTURE_PLATFORM.md` §2:

- Venta / Remito / Factura **no** bajan stock.
- Solo eventos de dominio: `MERCADERIA_ENTREGADA`, `DEVOLUCION_RECIBIDA`, `TRANSFERENCIA_CONFIRMADA`, `AJUSTE_INVENTARIO`, `MERCADERIA_RECIBIDA`, …
- Un hecho físico = un `eventId`; dos documentos no pueden generar el mismo movimiento.

Pendiente operativo: política por tenant de *cuándo* se emite `MERCADERIA_ENTREGADA` (configuración, no hardcode en `Tata.Core`).

---

## Estimación de esfuerzo (técnica, no calendario)

| Fase | Invasividad | Dependencias |
|---|---|---|
| A | Alta (rules + onboarding) | Firebase deploy + migración members |
| B | Alta (sync core) | Refactor colas / tombstones |
| C | Muy alta (dominio) | ADR eventos/ledgers; Event Bus; no acoplar docs→stock |
| D | Media | Tras A |
| E | Media | Tras B |
| F | Media | Tras tests mínimos |
| G | Media-baja | Tras B/C |
| H | Alta | Solo post-certificación núcleo (`Tata.Core` + plugins) |

---

## Gobernanza

- Cada fase = PR(s) con **prueba de fallo anterior** + test automatizado.
- No declarar fase cerrada por “se ve bien en 2 dispositivos”.
- Auditoría externa (este documento) se re-ejecuta al cierre de A, B y C.

---

*Roadmap vivo. Actualizar al cerrar cada fase con evidencias de DoD.*
