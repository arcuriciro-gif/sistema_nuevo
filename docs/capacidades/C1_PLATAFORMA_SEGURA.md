# Capacidad 1 — Plataforma segura (auditoría de entrega)

| Campo | Valor |
|---|---|
| Estado | **CERTIFICADA CONDICIONALMENTE** (desarrollo cerrado; ops de producción abiertas) |
| Rama | `cursor/capacidad-1-plataforma-segura-e44b` |
| Manifiesto / ADR | Respetados (sin rediseño) |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| Multiempresa real | Hecho (nuevas instalaciones) | `BackendConfigService.generarTenantIdNuevo()` — ya no default `tata_stock` |
| Tenant isolation | Hecho (path + rules) | `firestore.rules` por `tenants/{tenantId}` |
| Firestore Rules | Hecho — **deploy manual** | Self-join no admin; config/usuarios solo admin; solo_lectura read-only |
| Claims | Parcial | Autoridad actual = `members/{uid}` en rules; lectura de custom claims si existen; Admin SDK claims = pendiente infra |
| Roles | Hecho | admin / encargado / empleado / solo_lectura asignable + rules |
| Device Trust | Hecho (inventario) | `devices/{deviceId}` + `DeviceTrustService` (no App Check aún) |
| Eliminar accesos inseguros | Hecho / ops | Keystore fuera del tracking git; CI vía secrets; membership sin auto-elevate |

## Checklist de certificación Capacidad 1

- [x] Compila (verificar CI / `flutter test`)
- [x] Tests Capacidad 1 (`test/capacidad1_seguridad_test.dart`)
- [x] Authz en servicios destructivos (producto/cliente/proveedor/venta/compra/remito/permisos)
- [x] Docs operativas actualizadas (`CHECKLIST_PUESTA_EN_MARCHA.md`)
- [ ] **Ops:** `firebase deploy --only firestore:rules,storage`
- [ ] **Ops:** En tenant legado `tata_stock`, set `allowSelfJoin: false` cuando todos los miembros estén invitados
- [ ] **Ops:** Rotar keystore Android; cargar `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEY_PROPERTIES` en GitHub Secrets
- [ ] **Ops:** Cambiar admin123 en cada instalación de campo y desactivar recovery default
- [ ] Prueba negativa: empleado no escribe `config/permisos` ni `usuarios` ni se auto-asigna `rol: admin`
- [ ] Prueba: instalación limpia recibe `t_<uuid>` distinto de `tata_stock`

## Limitaciones conocidas (no bloquean cierre si ops completan)

1. Custom claims JWT vía Admin SDK / Cloud Functions aún no desplegados — rules usan `members` (equivalente servidor para Firestore).
2. App Check / Play Integrity no activado (Device Trust = registro de dispositivos).
3. Instalaciones que ya tenían `tata_stock` en prefs **conservan** ese tenant (compatibilidad). Aislamiento pleno = onboarding a tenant propio + migración de datos.
4. Keystore histórico puede permanecer en historial git — **rotar** es obligatorio.

## Veredicto

Capacidad 1 **lista para merge condicionado a deploy de rules y rotación de firma**.  
Sin esos pasos de ops, el código nuevo no protege el proyecto Firebase en producción.
