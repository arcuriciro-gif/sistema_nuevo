# Release train — consolidación a main

Gobernado por `ARCHITECTURE_PLATFORM.md` + `PLATFORM_CHARTER.md` + `ENGINEERING_GOVERNANCE.md`:  
sin release masivo mientras fallen aislamiento, integridad, ledgers o firma.  
Todo PR de producto debe incluir `PR_ARCHITECTURE_CHECKLIST.md`.

## Objetivo
Un instalador “oficial” desde `main`, sin depender de drafts eternos.  
Piloto controlado ≠ venta a miles de clientes.  
Release **no** se publica si fallan pruebas de migraciones/sync/stock/permisos/backup, o si hay pérdida potencial de datos / vulnerabilidades críticas (`ENGINEERING_GOVERNANCE.md` §11).

### North Star (release no debe degradar sin justificación)
Ver objetivos en `ENGINEERING_GOVERNANCE.md` §3 (sync &lt;2s, búsqueda &lt;300ms, login &lt;1s, apertura &lt;3s, restore &lt;5min, pérdida de datos = 0).

## Criterio para merge a main
1. CI Android + Windows en verde
2. Login local Windows OK
3. Sync básica clientes/productos OK con nube
4. Sin secretos nuevos en el diff (salvo keystore ya existente)
5. Docs de contratos/checklist actualizados si cambian paths/rules

## Orden sugerido (histórico reciente)
1. Sync/fotos/login/UI shell (rama ui-shell / PR #22 y derivadas)
2. Búsqueda / eliminar remitos-usuarios / márgenes (PR #24)
3. **Este PR: Fase 0+1 seguridad** (rules, membership, passwords, admin recovery)
4. **Fase 2 sync/stock** (soft-delete, LWW productos, stock atómico, catch-up)
5. **Fase 3 conflictos** (LWW proveedores, números únicos, código inmutable, stock_ops)
6. Luego **certificación comercial** — ver `AUDITORIA_CERTIFICACION_2026-07.md` y `ROADMAP_TATA_MANAGER_2_0.md` (Fases A–H). No avanzar a features nuevas (plugins/API/package) sin cerrar hardening A–C.

## Qué no mergear a ciegas
- Renombre de package Android sin plan de migración
- Wipe de DB / cambio de tenant default
- Rules que bloqueen membership sin backfill

## Artefactos
Tras merge a `main`, los workflows corren en **`main`** (Capacidad 5):
- `.github/workflows/build-android.yml` — analyze + test + APK + `SHA256SUMS.txt`
- `.github/workflows/build-windows.yml` — analyze + test + ZIP + `SHA256SUMS.txt`

Runbook restore: `docs/runbooks/BACKUP_RESTORE.md`.  
Auditoría Capacidad 5: `docs/capacidades/C5_RELEASE_READINESS.md`.

Inno Setup (unsigned): `packaging/windows/tata_manager.iss` (compilar en PC Windows con Inno 6).
Authenticode / package Play rename / R8 = diferidos.
