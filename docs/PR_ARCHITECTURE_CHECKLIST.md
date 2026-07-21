# Checklist de revisión arquitectónica (obligatorio)

Pegar en la descripción de todo PR que toque `lib/`, rules, sync, schema o seguridad.

Gobernado por: `docs/ARCHITECTURE_PLATFORM.md` + `docs/PLATFORM_CHARTER.md`.

## Filtro de escala
- [ ] ¿Sigue correcto con 500 empresas, 5.000 usuarios simultáneos, millones de movimientos, multi-dispositivo y 10 años?
- [ ] Si la respuesta es dudosa: **no mergear** — rediseñar.

## Dominio / ledgers
- [ ] ¿Los documentos (venta/remito/factura) **no** mueven stock directamente?
- [ ] ¿Todo movimiento de inventario/dinero es un **evento de dominio** append-only?
- [ ] ¿Hay un solo `eventId` / fuente de verdad por hecho físico?
- [ ] ¿No se reescriben eventos históricos?

## Acoplamiento
- [ ] ¿No hay cadena Ventas→Stock→Caja→Audit→Firebase?
- [ ] ¿Los efectos cruzados van por Event Bus / puertos?
- [ ] ¿El Core no importa verticales ni plugins (AFIP, ML, WhatsApp, …)?

## Seguridad (4 niveles)
- [ ] UI  
- [ ] Caso de uso  
- [ ] Servicio  
- [ ] Servidor (rules/API/claims)  

## Integridad / sync
- [ ] ¿Entidades relevantes con UUID, TenantId, Revision, tombstone, sync metadata (no solo `updatedAt`)?
- [ ] ¿Outbox con ACK (no borrar cola antes de confirmar)?
- [ ] ¿Compatibilidad de versiones de dominio/sync detectada?

## Calidad
- [ ] ¿Tests automatizados cubren el riesgo introducido?
- [ ] ¿No degrada integridad/seguridad/escala existente?
- [ ] ¿Otro equipo podría mantener esto en 5–10 años con docs/runbook?

## Veredicto
- [ ] **APROBAR** — cumple ADR  
- [ ] **RECHAZAR** — viola ADR (indicar ítem)
