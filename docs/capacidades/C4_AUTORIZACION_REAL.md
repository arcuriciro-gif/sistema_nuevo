# Capacidad 4 — Autorización real (auditoría de entrega)

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI + pruebas de rol en campo |
| Rama | `cursor/capacidad-4-autorizacion-real-e44b` |
| Depende de | Capacidad 3 (mergeada en `main` vía #33) |

## Objetivos vs entrega (Fase D roadmap)

| Objetivo | Estado | Evidencia |
|---|---|---|
| D1 — Authz en mutadores | Hecho (núcleo) | Producto/cliente/proveedor/remito/compra/venta/CC/stock/listas/categorías/branding/numeración/AFIP/backup |
| D2 — 4 roles end-to-end | Hecho (app) | `solo_lectura` solo `ver`; matriz para empleado/encargado; admin bypass |
| UI nivel 1 | Hecho (FABs) | FAB oculto sin `crear`/`editar` en productos, clientes, proveedores, remitos, compras, ventas, stock |
| Tests negativos | Hecho | `test/capacidad4_autorizacion_test.dart` |
| D3 — custom claims | Diferido | Rules siguen usando `members/{uid}.rol` (C1); Admin SDK claims = ops/infra |
| D4 — audit_log harden | Parcial | `registrarCambio` ya existe; política append-only formal = seguimiento |
| D5 — Argon2id | Diferido | Passwords siguen SHA-256; migración = Capacidad/ops posterior |

## Mapeo módulo ↔ acción

| Dominio | Módulo matriz | Acciones |
|---|---|---|
| Productos / categorías | `productos` | crear / editar / eliminar |
| Clientes | `clientes` | crear / editar / eliminar |
| Proveedores | `proveedores` | crear / editar / eliminar |
| Remitos / ventas / pagos CC | `remitos` | crear / editar / anular / eliminar(admin) |
| Compras | `compras` | crear / anular |
| Stock | `stock` | editar (ajuste) |
| Listas de precios | `listas_precios` | crear / editar / eliminar |
| Branding / numeración | `configuracion` | editar |
| AFIP / restaurar backup | admin | `requireAdmin` |
| Export backup | `backup` | editar |

## Checklist de certificación Capacidad 4

- [x] `AuthorizationService.require` en mutadores críticos
- [x] UI: FABs condicionados
- [x] Tests negativos por rol (`solo_lectura`, empleado sin permiso, admin OK)
- [x] Docs de capacidad
- [ ] **CI:** `flutter test` + builds Android/Windows verdes
- [ ] **Campo:** login como `solo_lectura` → no ve FAB crear; llamada a servicio falla
- [ ] **Campo:** empleado sin `productos.crear` no puede alta; sí puede remito si matriz lo permite
- [ ] **Ops (D3):** custom claims cuando exista Admin SDK / Functions

## Limitaciones conocidas

1. Ventas/CC usan módulo `remitos` (no hay fila `ventas` en seed de permisos).
2. Comparador / CSV / comunicaciones: mutaciones secundarias; authz parcial vía servicios que llaman (CSV→`insertarLista` ya protegido).
3. Claims JWT y Argon2id quedan fuera de este PR (infra + migración de hashes).
4. Firestore Rules no replican la matriz módulo×acción (solo admin / writeOps / solo_lectura).

## Veredicto

Capacidad 4 **lista para merge de desarrollo** tras CI verde.  
D3 claims y D5 Argon2id no bloquean el cierre de D1/D2 en app. No iniciar Capacidad 5 hasta este veredicto + CI.

> **Update 2026-07-21:** Capacidad 4 mergeada (#34). Capacidad 5 en curso: `docs/capacidades/C5_RELEASE_READINESS.md`.
