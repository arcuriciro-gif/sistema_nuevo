# CERTIFICACIÓN POR INVARIANTES — Sync Engine + Stock

**Producto:** Tata.Manager  
**Versión:** 1.4.9+77  
**Fecha:** 2026-07-27  

> Ver también: [`CERTIFICACION_RESIDUALES_CERRADOS.md`](./CERTIFICACION_RESIDUALES_CERRADOS.md)  
> (poison queue, legacy ledger, G6 formal, watermark HOL).

---

## Cobertura (post-residuales)

| G | Estado | Evidencia |
|---|--------|-----------|
| **G1** | **Demostrada** | UNIQUE + PBT + contraejemplos |
| **G2** | **Demostrada** | TX atómica + reject codigo vacío + dead gestionada |
| **G3** | **Demostrada** | throw sin proof; no-ops ciegos |
| **G4** | **Demostrada** | legacy seed + validator |
| **G5** | **Demostrada** | PBT permutaciones |
| **G6** | **Demostrada** | definición formal + drain→quiescencia PBT |
| **G7** | **Demostrada** | verificarProyeccion en PBT |

## Veredicto

Módulo de stock **certificado** bajo G1–G7 con evidencia estructural y generativa.  
Riesgo operativo residual: poison que re-falla tras force-requeue (payload corrupto) → alarma C8 visible.
