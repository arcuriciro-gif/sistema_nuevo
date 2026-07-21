# Tata.Manager — Product Manifesto

| Campo | Valor |
|---|---|
| Estado | **SUPREMO — prioridad sobre cualquier decisión técnica** |
| Vigencia | Desde 2026-07-21 |
| Conflicto | Si choca con velocidad, feature o moda técnica → **prevalece este manifiesto** |

Este documento tiene **prioridad sobre cualquier decisión técnica**.  
Cuando exista conflicto entre implementar una funcionalidad rápidamente o preservar estos principios, **siempre prevalecerán estos principios**.

---

## Nuestra misión

Construimos software que las empresas puedan utilizar durante **años con confianza**.

Nuestro objetivo **no** es desarrollar la mayor cantidad de funciones.  
Nuestro objetivo es construir el ERP más **confiable, estable y mantenible** posible.

Cada línea de código deberá **aumentar la calidad** del producto.  
Nunca solamente hacerlo más grande.

---

## Nuestros principios

1. **Los datos de nuestros clientes son sagrados.** Nunca una actualización podrá ponerlos en riesgo.  
2. **Perder un dato es siempre un error crítico.** No existen pérdidas de datos aceptables.  
3. **Toda operación importante debe poder reconstruirse.** Nada importante debe desaparecer.  
4. Preferimos una **función menos** antes que una función **insegura**.  
5. Preferimos una sincronización **lenta** antes que una sincronización **incorrecta**.  
6. Preferimos **rechazar** una operación antes que generar información **inconsistente**.  
7. Nunca agregaremos complejidad solamente porque una arquitectura moderna lo sugiera.  
8. El software deberá poder ser mantenido por personas que **nunca conocieron** al autor original.  
9. Toda decisión técnica deberá facilitar la **evolución futura** del producto.  
10. La **experiencia del usuario** es tan importante como la arquitectura. Una gran arquitectura que produce una mala experiencia también es un **fracaso**.

---

## Lo que nunca haremos

- Nunca sacrificaremos **estabilidad** por velocidad de desarrollo.  
- Nunca sacrificaremos **seguridad** por comodidad.  
- Nunca sacrificaremos **integridad** por rendimiento.  
- Nunca sacrificaremos **simplicidad** por elegancia técnica.  
- Nunca sacrificaremos **mantenibilidad** por modas tecnológicas.  
- Nunca aceptaremos **deuda técnica** sin documentarla.

---

## Definición de terminado

Una funcionalidad **solamente** estará terminada cuando:

- Compila  
- Tiene pruebas  
- Tiene documentación  
- Respeta la arquitectura (`ARCHITECTURE_PLATFORM.md`)  
- Respeta los ADR  
- Respeta la gobernanza (`ENGINEERING_GOVERNANCE.md`)  
- Respeta los NFR  
- No degrada el rendimiento (North Star)  
- No aumenta la deuda técnica (o la documenta con plan)  
- No rompe la sincronización  
- No rompe la seguridad  
- No rompe la mantenibilidad  

Si falta uno → **no está terminada**. No se mergea a release.

---

## Nuestra responsabilidad

No desarrollamos solamente software.  
Administramos la **información**, el **dinero**, el **trabajo** y la **confianza** de empresas reales.

Cada error puede afectar un negocio.  
Cada decisión debe tomarse con esa responsabilidad.

---

## Moratoria de gobernanza documental

Hasta que se completen las **Fases A, B y C** del roadmap y el sistema **supere una auditoría técnica sin hallazgos críticos**:

**No generar nuevos documentos de gobernanza** salvo que sean **estrictamente necesarios** para implementar un cambio concreto.

Documentos ya vigentes (no ampliar la constitución sin necesidad):

| Orden | Documento |
|---|---|
| 0 | **Este manifiesto** |
| 1 | `ARCHITECTURE_PLATFORM.md` |
| 2 | `PLATFORM_CHARTER.md` |
| 3 | `ENGINEERING_GOVERNANCE.md` |
| 4 | `ROADMAP_TATA_MANAGER_2_0.md` |
| 5 | `AUDITORIA_CERTIFICACION_2026-07.md` |
| 6 | `ARCHITECTURE_CONTRACTS.md` (legado) |
| — | `PR_ARCHITECTURE_CHECKLIST.md` / `RELEASE_TRAIN.md` (operativos) |

El siguiente trabajo de producto es **implementar A → B → C** bajo estos principios — no escribir más constitución.
