# Arquitectura oficial de plataforma — Tata.Manager

| Campo | Valor |
|---|---|
| Estado | **VINCULANTE — decisión de plataforma** |
| Tipo | Architecture Decision Record (ADR) de nivel plataforma |
| Vigencia | Desde 2026-07-21 · sin caducidad salvo ADR que lo reemplace |
| Audiencia | Todo PR, todo diseño, todo release, todo equipo futuro |
| Relación | Complementa y **manda** sobre `PLATFORM_CHARTER.md` en dominio/eventos/core |

**Esto no es una sugerencia.**  
**Es arquitectura oficial.** Toda implementación futura debe respetarlo.  
Un PR que lo viole **no se aprueba**.

---

## 1. Visión del producto

No estamos informatizando “El Tata”.  
Estamos construyendo un **núcleo ERP comercial** usable por **cientos de empresas** durante **los próximos 10 años**.

Cada decisión técnica debe responder **obligatoriamente**:

> ¿Esta arquitectura seguiría funcionando correctamente con **500 empresas**, **5.000 usuarios simultáneos**, **millones de movimientos**, **múltiples dispositivos** y **diez años de evolución**?

Si la respuesta es **NO**, esa solución queda **descartada**.

### No priorizar
- Rapidez de entrega  
- Facilidad de programación  
- Agregar funciones  

### Siempre priorizar
1. Integridad de datos  
2. Seguridad  
3. Escalabilidad  
4. Mantenibilidad  
5. Simplicidad operacional  
6. Compatibilidad futura  

---

## 2. Filosofía del dominio (irrenunciable)

**Los documentos NO generan movimientos.**  
**Los eventos de negocio generan movimientos.**

Por lo tanto:

| Documento | ¿Mueve stock? |
|---|---|
| Venta | **NO** |
| Remito | **NO** |
| Factura | **NO** |
| Compra (documento) | **NO** por sí sola |

Lo que mueve inventario son **únicos eventos de dominio**, por ejemplo:

| Evento de dominio | Efecto |
|---|---|
| `MERCADERIA_ENTREGADA` | Baja stock |
| `DEVOLUCION_RECIBIDA` | Sube stock |
| `TRANSFERENCIA_CONFIRMADA` | Mueve stock entre ubicaciones |
| `AJUSTE_INVENTARIO` | Corrige stock |
| `MERCADERIA_RECIBIDA` | Sube stock (ingreso físico) |

**Nunca** permitir que dos documentos distintos produzcan el mismo movimiento físico.  
Debe existir **una única fuente de verdad** para cada evento físico (idempotencia por `eventId` / `opId`).

Un documento puede *referenciar* o *disparar la emisión* de un evento, pero el ledger solo conoce el evento — no el tipo de documento.

### Implicación sobre el código legado

El comportamiento actual (p. ej. remito que descuenta stock directo, venta que no descuenta) es **deuda incompatible** con esta arquitectura.  
La migración debe converger a: documento → (opcional) comando → **evento de dominio** → proyección de ledger.  
No se aceptan parches que “hagan que venta también baje stock como el remito”.

---

## 3. Event Sourcing parcial

Migración gradual basada en eventos para:

- Inventario  
- Caja  
- Cuenta corriente  
- Pagos  
- Cobros  
- Auditoría  

### Reglas
- **No modificar** registros históricos de eventos.  
- **Siempre agregar** nuevos eventos.  
- Todo permanece auditable.  
- **Nunca** perder historial.

Ejemplo de cadena:

```
VentaCreada
  → PagoRegistrado
  → PagoAnulado
  → PagoCorregido
```

Los saldos/proyectados se recalculan; los eventos no se editan.

---

## 4. Ledger

Todo lo que represente **valor económico** o **inventario** se implementa mediante ledger:

- Stock  
- Caja  
- Cuenta corriente  
- Pagos  
- Cobros  
- Ajustes  
- Transferencias  

**No** almacenar únicamente saldos.  
Los saldos **deben poder reconstruirse** a partir del historial (replay / proyección).

Invariante de certificación:

```
proyección(ledger) == saldo_mostrado
suma(eventos) reproducible en cualquier dispositivo del tenant
```

---

## 5. Domain Events / Event Bus

Eliminar dependencias directas entre módulos.

### Prohibido (acoplamiento en cadena)

```
Ventas → StockService → CajaService → AuditoriaService → FirebaseService
```

### Obligatorio

Event Bus interno de dominio:

```
VentaConfirmada
   ├─ Stock (escucha; emite o reacciona solo si hay política de entrega)
   ├─ Caja (escucha)
   ├─ CuentaCorriente (escucha)
   ├─ Auditoría (escucha)
   └─ Sync (escucha / outbox)
```

Cada módulo es **independiente**.  
El Core expone contratos de eventos; los listeners no importan implementaciones concretas de otros bounded contexts salvo vía bus/puertos.

Nota: `VentaConfirmada` **no** implica automáticamente `MERCADERIA_ENTREGADA`. Esa es una decisión de caso de uso / política del tenant (entrega al confirmar, al remitar, etc.), siempre materializada como evento de inventario explícito.

---

## 6. Core ERP — `Tata.Core`

Diseñar un núcleo **desacoplado del rubro**.

### `Tata.Core` contiene únicamente

- Usuarios  
- Permisos  
- Inventario (ledger + eventos)  
- Ventas  
- Compras  
- Clientes  
- Proveedores  
- Caja  
- Cuenta corriente  
- Auditoría  
- Eventos / bus  
- Sincronización  
- Configuración  
- Backups  
- Seguridad  

### Sobre el Core se construyen verticales (el Core **nunca** los conoce)

- `Tata.Calzado`  
- `Tata.Ferreteria`  
- `Tata.Repuestos`  
- `Tata.Textil`  
- `Tata.Distribuidora`  
- …  

Si el Core importa un vertical → **violación de arquitectura**.

---

## 7. Plugins

Toda integración externa es módulo independiente:

- Mercado Libre  
- WhatsApp  
- WooCommerce  
- AFIP / Facturación electrónica  
- API REST  
- Dashboard BI  
- Reportes avanzados  

**Nunca** agregar dependencias de esos módulos dentro del núcleo.

Contrato mínimo de plugin: ver `PLATFORM_CHARTER.md` §5.

---

## 8. Permisos — cuatro niveles

| Nivel | Capa | Obligatorio |
|---|---|---|
| 1 | Interfaz | Ocultar/deshabilitar acciones |
| 2 | Casos de uso | Rechazar comando no autorizado |
| 3 | Servicios | Guardas en mutaciones |
| 4 | Servidor | Firestore Rules / API / claims |

**Nunca** confiar únicamente en ocultar botones (nivel 1).

---

## 9. Versionado

Versionar no solo la base de datos:

| Artefacto | Versionado |
|---|---|
| Schema SQLite | Sí (ya) |
| Dominio / reglas de negocio | Sí |
| Contrato de sync | Sí |
| Schema de eventos | Sí |
| API | Sí (`/v1`, …) |
| App cliente | Sí (semver) |

Si dos dispositivos usan versiones **incompatibles**, deben **detectarlo automáticamente** y bloquear sync peligroso (con mensaje operable), no corromper datos en silencio.

---

## 10. Observabilidad

Sistema interno que registre al menos:

- Errores  
- Conflictos  
- Tiempo de sincronización / latencia  
- CPU / RAM (best-effort por plataforma)  
- Firestore reads / writes  
- SQLite / tiempo de consultas  
- Backups  
- Última sincronización  
- Estado Firebase / Storage / Authentication  

**Panel técnico exclusivo para administradores** (no mezclar con UX comercial).

---

## 11. Health check por dispositivo

Cada dispositivo informa automáticamente:

- Versión de la app  
- Versión de base  
- Versión del dominio  
- Versión de sync  
- Último backup / última restauración  
- Estado SQLite / Firebase / Storage  
- Latencia  
- Errores pendientes  
- Operaciones pendientes (outbox depth)

---

## 12. Integridad de entidades

Toda entidad importante debe incorporar (o mapear hacia):

| Campo | Rol |
|---|---|
| `UUID` | Identidad estable cross-device |
| `TenantId` | Aislamiento |
| `Revision` | Concurrencia optimista |
| `CreatedAt` / `UpdatedAt` | Tiempo |
| `UpdatedBy` | Autoría |
| `DeletedAt` | Tombstone |
| `DeviceId` | Origen |
| `SyncVersion` | Contrato sync |
| `Checksum` | Integridad de payload |
| `Dirty` / `PendingSync` | Outbox local |

**Nunca** depender únicamente de `updatedAt` para LWW/conflictos.

---

## 13. Disaster recovery

Plan completo, no solo “copiar el `.db`”:

- Corrupción SQLite  
- Pérdida Firestore  
- Ransomware / disco dañado  
- Restauración parcial y completa  
- Backups corruptos  
- Errores humanos  

**No alcanza con hacer backups.**  
Hay que **demostrar** que se pueden restaurar (restore drills en CI/release + runbook).

---

## 14. Calidad de release

Cada release ejecuta automáticamente pruebas de:

- Migraciones  
- Sincronización  
- Ventas / compras / remitos  
- Stock (ledger)  
- Permisos / usuarios  
- Backups / restauraciones  
- Integridad  

**No** publicar release si alguna prueba falla.

---

## 15. Principios irrenunciables

1. La integridad de los datos vale más que el rendimiento.  
2. La consistencia vale más que la velocidad.  
3. La seguridad vale más que la comodidad.  
4. Nunca perder un dato es más importante que sincronizar rápido.  
5. Toda operación debe poder reconstruirse.  
6. Todo cambio debe poder auditarse.  
7. Todo módulo debe poder reemplazarse sin romper el núcleo.  
8. Nunca sacrificar arquitectura para resolver un problema inmediato.  
9. Toda nueva funcionalidad debe demostrar que no degrada el sistema existente.  
10. Otro equipo debe poder mantener Tata.Manager en diez años sin el autor original.

---

## 16. Auditoría permanente de PRs

Antes de aprobar cualquier Pull Request, responder por escrito:

| Pregunta | Si Sí → |
|---|---|
| ¿Rompe el aislamiento entre módulos? | **Rechazar** |
| ¿Rompe la sincronización? | **Rechazar** |
| ¿Rompe la escalabilidad (filtro 500/5k/millones/10 años)? | **Rechazar** |
| ¿Rompe la seguridad? | **Rechazar** |
| ¿Rompe la mantenibilidad? | **Rechazar** |
| ¿Rompe la integridad (ledgers / eventos / no-wipe)? | **Rechazar** |

Plantilla recomendada en cada PR de producto: checklist §16 + referencia a este ADR.

---

## 17. Objetivo final

No construir una aplicación.  
No construir un sistema para un solo negocio.

Construir una **plataforma ERP** moderna, escalable, segura, auditable, desacoplada y preparada para comercializarse **diez años** sin reescribir el núcleo.

---

## 18. Jerarquía documental

| Prioridad | Documento | Rol |
|---|---|---|
| 1 | **Este ADR** (`ARCHITECTURE_PLATFORM.md`) | Dominio, eventos, core, plugins, calidad, DR — **VINCULANTE** |
| 2 | `PLATFORM_CHARTER.md` | Filtro CTO, diseños descartados, SoT |
| 3 | `ENGINEERING_GOVERNANCE.md` | Gobernanza: simplicidad, métricas, NFRs, límites de producto, calidad, release |
| 4 | `ROADMAP_TATA_MANAGER_2_0.md` | Secuencia de migración |
| 5 | `AUDITORIA_CERTIFICACION_2026-07.md` | Gap vs legado |
| 6 | `ARCHITECTURE_CONTRACTS.md` | Contratos congelados del legado en campo |
| — | `PR_ARCHITECTURE_CHECKLIST.md` | Gate obligatorio de todo PR de producto |

Ante conflicto entre legado y este ADR: el legado se **migra**; no se usa como excusa para violar el ADR en código nuevo.  
Ante tensión ADR ↔ simplicidad: cumplir el ADR con la implementación **más simple** (`ENGINEERING_GOVERNANCE.md`).

---

*Cualquier excepción requiere un ADR nuevo que demuestre que sigue pasando el filtro 500 / 5.000 / millones / multi-dispositivo / 10 años. Si no lo demuestra, no hay excepción.*
