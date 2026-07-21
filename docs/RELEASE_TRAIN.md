# Release train — consolidación a main

## Objetivo
Un instalador “oficial” desde `main`, sin depender de drafts eternos.

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
4. Luego Fase 2 sync/stock (otro PR)

## Qué no mergear a ciegas
- Renombre de package Android sin plan de migración
- Wipe de DB / cambio de tenant default
- Rules que bloqueen membership sin backfill

## Artefactos
Tras merge a `main`, disparar workflows o añadir `main` a `on.push.branches` de:
- `.github/workflows/build-android.yml`
- `.github/workflows/build-windows.yml`
