# Contratos congelados — Tata.Manager (Fase 0 / legado)

Documento de gobernanza del **estado actual en campo**. **No cambiar estos contratos sin migración versionada y aprobación.**

**Manifiesto de producto (SUPREMO):** `PRODUCT_MANIFESTO.md`.  
**Arquitectura oficial de destino (VINCULANTE):** `ARCHITECTURE_PLATFORM.md`.  
**Gobernanza de ingeniería (VINCULANTE, complementaria):** `ENGINEERING_GOVERNANCE.md`.  
Doctrina CTO: `PLATFORM_CHARTER.md`.  
Checklist de PRs: `PR_ARCHITECTURE_CHECKLIST.md`.

Varias filas de este documento son **legado tolerado en migración**, no el diseño final (p. ej. tenant default `tata_stock`, remito que descuenta stock directo, rules solo por membership, ausencia de ledgers/event bus).

**Moratoria:** no ampliar la constitución documental hasta Fases A–B–C + auditoría sin críticos.

Última actualización: 2026-07-21 · Schema SQLite: **v25** · Tenant default: **`tata_stock`** (legado — a eliminar en Roadmap 2.0 Fase A)

---

## 1. Identidad de apps

| Plataforma | Valor |
|------------|--------|
| Android `applicationId` | `com.example.sistema_nuevo` |
| Windows exe | `Tata.Manager.exe` |
| Firebase project | `tata-stock-8631e` |
| Package futuro (pendiente Fase 5) | `com.eltatamanager.app` — **no usar hasta migración aprobada** |

---

## 2. Firestore — layout

```
tenants/{tenantId}/
  _meta/bootstrap          # opcional
  members/{uid}            # membresía (Fase 1+)
  productos/{codigo}       # docId = código de producto
  clientes/{syncId}        # UUID
  proveedores/{syncId}     # UUID
  usuarios/{firebaseUid}
  ventas/{numero}
  remitos/{numero}
  compras/{numero}
  documentos/{id}
  chats/...
  notificaciones/...
  stock_ops/{opId}         # idempotencia stock (Fase 3)
  config/branding
  config/permisos
  config/listas_precios
  config/categorias
```

**Tenant ID:** SharedPreferences `backend_tenant_id` (default `tata_stock`).

---

## 3. SQLite — archivo y versión

| Ítem | Valor |
|------|--------|
| Archivo | `eltata.db` |
| Desktop path | Application Support `/databases/eltata.db` |
| `DatabaseHelper` version | **25** |
| Preferencias nube | `backend_firebase_enabled` |

Migraciones: solo incrementales `oldVersion < N`. Nunca wipe en upgrade.

---

## 4. Colas offline (SharedPreferences)

| Clave | Entidad |
|-------|---------|
| `sync_cola_clientes_ids` | clientes |
| `sync_cola_proveedores_ids` | proveedores |
| `sync_cola_productos_ids` | productos |
| `sync_cola_ventas_ids` | ventas |
| `sync_cola_remitos_ids` | remitos |
| `sync_cola_compras_ids` | compras |
| `sync_cola_stock_ops_v2` | deltas stock idempotentes |

---

## 5. Identificadores cross-device

| Entidad | Clave cloud | Clave local |
|---------|-------------|-------------|
| Producto | `codigo` | `id` AUTOINCREMENT |
| Cliente / Proveedor | `syncId` UUID | `id` AUTOINCREMENT |
| Venta / Remito / Compra | `numero` | `id` AUTOINCREMENT |
| Usuario | `firebaseUid` | `id` AUTOINCREMENT |

---

## 6. Seguridad (Fase 1)

- **No** subir hash de password a Firestore.
- Membership: `tenants/{tenantId}/members/{uid}`.
- Rules: ver `firestore.rules` y `storage.rules`.
- Admin default `admin123`: solo si recovery por defecto sigue habilitado; tras cambio de clave se desactiva. Alternativa: código de recuperación local.

---

## 7. Sync / stock (Fase 2)

- Productos: LWW por `actualizadoEn`; soft-delete (`deleted_at`) se propaga entre dispositivos.
- No hay sweep completo de productos al conectar (solo ausentes + cola).
- Stock en nube: ajustes atómicos idempotentes (`stock_ops/{opId}` + increment), no multi-master de absolutos en remitos/compras/ajustes.
- Catch-up ventas/remitos/compras: hasta 2000 docs recientes.
- SQLite sigue siendo SoT operativo local; Firestore es bus de sync (stock cloud como autoridad entre dispositivos).

---

## 8. Conflictos multi-dispositivo (Fase 3)

- Proveedores: LWW por `actualizadoEn` (paridad con clientes).
- Remitos/compras: número `R-#####-XXXX` / `C-#####-XXXX` con tag de dispositivo.
- Código de producto inmutable en edición (identidad cloud = `codigo`).
- Colección `stock_ops` en rules (idempotencia durable).

---

## 9. Release

- Builds CI: workflows `Build Android APK` / `Build Windows Instalador`.
- Artefactos: `Instalador_Android`, `Instalador_Windows`.
- Objetivo: consolidar features estables en `main` (release train); no dejar features solo en drafts eternos.
