# Gobernanza de ingeniería — Tata.Manager

| Campo | Valor |
|---|---|
| Estado | **VINCULANTE — gobernanza oficial** |
| Tipo | Complementa la arquitectura; **no la modifica** |
| Vigencia | Desde 2026-07-21 |
| Relación | Junto a `ARCHITECTURE_PLATFORM.md` (dominio/core) y `PLATFORM_CHARTER.md` (filtro de escala) |
| Checklist PR | Usar también `PR_ARCHITECTURE_CHECKLIST.md` + § de este doc |

**No es una sugerencia.**  
Todo desarrollo futuro debe respetar estas reglas.  
Un PR que las viole sin justificación técnica escrita **no se aprueba**.

---

## 1. Engineering principles

La arquitectura existe para **resolver problemas reales**.  
Nunca para demostrar complejidad.

### No se acepta una “mejora” arquitectónica que

- aumente complejidad sin resolver un problema real  
- agregue más capas de las necesarias  
- incremente clases sin separación clara de responsabilidades  
- degrade el rendimiento  
- haga más difícil el debugging  
- complique el mantenimiento  
- dificulte el ingreso de nuevos desarrolladores  

### Toda nueva abstracción debe justificar por escrito

| Pregunta | Obligatoria |
|---|---|
| ¿Qué problema resuelve? | Sí |
| ¿Por qué era necesario crearla? | Sí |
| ¿Qué alternativas existían? | Sí |
| ¿Por qué esta es mejor (beneficio medible)? | Sí |

Si la abstracción **no aporta un beneficio real y medible** → **no se implementa**.

Esto **no debilita** `ARCHITECTURE_PLATFORM.md` (ledgers, eventos, 4 niveles de permisos).  
Significa: implementar esos contratos con la **menor superficie** que los cumpla — no con theater de capas.

---

## 2. Simplicidad

La solución **más simple** que cumpla todos los requisitos funcionales **y** no funcionales es siempre la preferida.

### Evitar

- Sobreingeniería  
- Patrones innecesarios  
- Capas redundantes  
- Interfaces sin propósito  
- Wrappers innecesarios  
- Abstracciones prematuras  

No construir pensando en impresionar.  
Construir pensando en **mantener el sistema diez años**.

### Tensión con el ADR (cómo se resuelve)

| Si el ADR exige… | La gobernanza exige… |
|---|---|
| Event Bus / ledgers | Un bus claro y ledgers append-only — **no** seis frameworks encima |
| 4 niveles de permisos | Guardas reales en cada nivel — **no** frameworks de policy sin uso |
| `Tata.Core` + plugins | Fronteras de módulo — **no** microservicios prematuros |

**Complejidad justificada por integridad/seguridad/escala: sí.**  
**Complejidad por moda o anticipación especulativa: no.**

---

## 3. North Star Metrics (oficiales)

Toda optimización debe poder **medirse**. Sin métrica, no hay “optimización” — hay opinión.

### Indicadores mínimos y objetivos iniciales

| Indicador | Objetivo |
|---|---|
| Tiempo promedio de sincronización (ciclo sano, red OK) | **&lt; 2 s** |
| Tiempo apertura aplicación (cold start usable) | **&lt; 3 s** |
| Tiempo apertura venta / pantalla de venta | Medir; target a fijar ≤ **1 s** p95 en hardware de referencia |
| Tiempo búsqueda producto (índice local caliente) | **&lt; 300 ms** |
| Tiempo generación PDF (remito/venta típico) | Medir; degradación no aceptable release a release |
| Tiempo login (local) | **&lt; 1 s** |
| Tiempo backup | Medir; documentar en runbook |
| Tiempo restauración backup | **&lt; 5 min** (tamaño de referencia documentado) |
| Conflictos de sincronización / día / tenant | Tendencia a **0**; alarmar si crece |
| Errores no recuperados | Tendencia a **0** críticos |
| Firestore Reads / Writes | Presupuesto por tenant; sin storms silenciosos |
| Consumo RAM / CPU / disco / red | Baselines por plataforma; sin regresiones &gt; umbral release |
| **Pérdida de datos** | **0** |

Los objetivos se refinan con baselines reales del panel técnico (Fase G del roadmap), pero **pérdida de datos = 0** no se negocia.

Cada PR que “optimiza” debe citar el indicador afectado y el antes/después (o por qué aún no hay baseline y cómo se medirá).

---

## 4. Non-functional requirements (NFRs)

Toda funcionalidad nueva debe respetar:

| NFR | Requisito |
|---|---|
| Disponibilidad | Objetivo **99.9%** del servicio de sync/control plane (diseño + operación) |
| Integridad | **100%** de invariantes de ledger / no corrupción silenciosa |
| Pérdida de datos | **0%** |
| Compatibilidad | **No romper** instalaciones existentes |
| Migraciones | **Automáticas**, forward-only, verificables |
| Rollback | **Seguro** (release / feature / migración según runbook) |
| Sincronización | **Consistente** (outbox + ACK + tombstones según ADR) |
| Seguridad | **Defensa en profundidad** (4 niveles) |
| Escalabilidad | **500 empresas · 5.000 usuarios · millones de movimientos** |
| Mantenibilidad | Nuevo desarrollador comprende la arquitectura **sin** el autor original |

Si una feature no puede demostrar NFRs → no entra a release.

---

## 5. Product boundaries — qué NO es Tata.Manager

Definición explícita. No convertirlo en producto universal.

### Fuera de alcance (rechazar por defecto)

- CRM de marketing  
- CMS  
- ERP industrial / MES / planta  
- Sistema contable completo (libro mayor impositivo integral)  
- Marketplace  
- Editor gráfico  
- Suite Office  
- POS especializado de supermercado  

Toda feature nueva debe justificar **por escrito** por qué pertenece al **dominio ERP comercial** (catálogo, partners, documentos, inventario físico, caja/CC, sync multi-dispositivo, verticales/plugins del ADR).

### Dentro de alcance (Core / vertical / plugin)

Ver `ARCHITECTURE_PLATFORM.md` §§6–7 y § Core first abajo.

---

## 6. Core first

Toda funcionalidad nueva responde **una** de estas:

| Clasificación | Criterio |
|---|---|
| **Core** (`Tata.Core`) | Reutilizable por cualquier rubro; sin lógica de calzado/ferretería/etc. |
| **Vertical** | Específico de rubro (`Tata.Calzado`, …) |
| **Integración / plugin** | Sistema externo (AFIP, WhatsApp, ML, API, BI, …) |

**Nunca** incorporar lógica específica de un negocio o rubro dentro del Core.  
El Core permanece **completamente reutilizable**.

---

## 7. Arquitectura modular (objetivo)

```
Tata.Core
    ↓
Verticales (Tata.Calzado, Tata.Ferretería, Tata.Repuestos, Tata.Textil, Tata.Distribuidora, …)
    ↓
Plugins (WhatsApp, Mercado Libre, WooCommerce, AFIP, API REST, Dashboard BI, Facturación electrónica, …)
```

Cada módulo debe poder **agregarse o eliminarse** sin modificar el Core (contrato + feature flag + schema propio).

Detalle normativo de dominio/eventos/ledgers: `ARCHITECTURE_PLATFORM.md` (no se redefine aquí).

---

## 8. Calidad del código

### No aceptar en `main` / release

- `TODO` / `FIXME` que bloqueen comportamiento (si quedan, issue + owner + fecha)  
- Código muerto  
- Imports sin uso  
- Duplicación injustificada  
- Magic numbers sin constante con nombre de dominio  
- Funciones / clases gigantes sin plan de corte  
- Singletons innecesarios  
- Dependencias circulares  
- Violaciones SOLID / Clean Architecture **sin** justificación del §1  

Cada PR debe **mejorar o mantener** la calidad.  
**Nunca** degradarla a cambio de “terminar la tarea”.

---

## 9. Observabilidad

Toda versión debe generar información útil para soporte:

- Errores / advertencias / eventos  
- Sincronizaciones / conflictos  
- Backups / restauraciones  
- Latencia / CPU / RAM  
- Estado Firebase / SQLite / Storage / Authentication / Internet  

Panel técnico para administradores (no mezclar con UX comercial).  
Alineado a `ARCHITECTURE_PLATFORM.md` §§10–11.

---

## 10. Documentación

Todo cambio arquitectónico actualiza, en el mismo PR o PR hermano inmediato:

- ADR (si cambia decisión)  
- Diagramas  
- Modelo de datos  
- Permisos  
- Eventos  
- API  
- Sincronización  
- Migraciones  
- Runbooks  

**No** permitir documentación desactualizada a sabiendas.  
Código que cambia contrato sin docs → **rechazar**.

---

## 11. Release policy

**No** generar versión Release si:

- Existe pérdida **potencial** de datos  
- Falla una migración  
- Falla la sincronización (pruebas críticas)  
- Falla un backup  
- Falla una restauración  
- Falla una prueba crítica  
- Existen vulnerabilidades **críticas** abiertas  

Alineado a `RELEASE_TRAIN.md` y `ARCHITECTURE_PLATFORM.md` §14.

---

## 12. Regla de oro

Toda decisión responde:

1. ¿Es más **segura**?  
2. ¿Es más **simple**?  
3. ¿Es más **mantenible**?  
4. ¿Es más **escalable**?  
5. ¿Es más **fácil de entender**?  
6. ¿**Reduce** deuda técnica?  
7. ¿Podrá mantenerla **otro equipo en diez años**?  

Si alguna respuesta es **NO**, hace falta **justificación técnica escrita**.  
Si no hay justificación → se elige otra solución.

---

## 13. Modo CTO (comportamiento de revisión)

A partir de esta gobernanza, la evaluación de trabajo **no** prioriza:

- “terminar la tarea”  
- “escribir más código”  
- “que compile / que funcione en un demo”  

Prioriza construir una **plataforma robusta**.

Cada PR se evalúa por:

- estabilidad  
- seguridad  
- integridad  
- sincronización  
- escalabilidad  
- mantenibilidad  
- **simplicidad**  

**Nunca** aceptar una solución solo porque funciona.  
Aceptarla solo si es la **mejor solución a largo plazo** para el producto.

El objetivo no es desarrollar una aplicación.  
El objetivo es una plataforma ERP comercial que evolucione **diez años** sin reescribir el núcleo.

---

## 14. Checklist adicional de PR (gobernanza)

Complementa `PR_ARCHITECTURE_CHECKLIST.md`:

- [ ] ¿La abstracción nueva tiene justificación §1 (problema, alternativas, beneficio medible)?  
- [ ] ¿Es la solución más simple que cumple ADR + NFRs?  
- [ ] ¿Clasificada Core / Vertical / Plugin?  
- [ ] ¿Dentro de product boundaries (§5)?  
- [ ] ¿Cita o actualiza métricas North Star si toca rendimiento/sync?  
- [ ] ¿Documentación del contrato actualizada en el mismo cambio?  
- [ ] ¿Calidad de código no degradada?  
- [ ] ¿Regla de oro (§12) respondida?  

---

## 15. Jerarquía (complemento, no reemplazo)

| Orden | Documento | Rol |
|---|---|---|
| 0 | `PRODUCT_MANIFESTO.md` | Supremo — gana todo conflicto con velocidad/features |
| 1 | `ARCHITECTURE_PLATFORM.md` | ADR de dominio / core / eventos / ledgers |
| 2 | `PLATFORM_CHARTER.md` | Filtro 500/5k/millones/10 años; diseños descartados |
| 3 | **Este documento** | Gobernanza de ingeniería: simplicidad, métricas, NFRs, límites, calidad, release |
| 4 | `ROADMAP_TATA_MANAGER_2_0.md` | Secuencia de migración |
| 5 | `AUDITORIA_CERTIFICACION_2026-07.md` | Gap vs legado |
| 6 | `ARCHITECTURE_CONTRACTS.md` | Contratos legado en campo |
| — | `PR_ARCHITECTURE_CHECKLIST.md` + §14 aquí | Gates de PR |

Ante tensión “ADR vs simplicidad”: se cumple el ADR con la implementación **más simple posible** — no se elimina el ADR, ni se infla con capas vacías.  
Ante tensión con “terminar rápido”: gana el **manifiesto**.  
**Moratoria documental:** no nuevos docs de gobernanza hasta Fases A–B–C + auditoría sin críticos.

---

*Fin de la gobernanza de ingeniería. Toda excepción requiere nota técnica que responda la regla de oro y el filtro de escala.*
