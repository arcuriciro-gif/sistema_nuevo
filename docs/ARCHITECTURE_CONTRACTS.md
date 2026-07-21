# Contratos congelados — Tata.Manager (Fase 0)

Documento de gobernanza. **No cambiar estos contratos sin migración versionada y aprobación.**

Última actualización: 2026-07-21 · Schema SQLite: **v24** · Tenant default: **`tata_stock`**

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
| `DatabaseHelper` version | **24** |
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

## 7. Release

- Builds CI: workflows `Build Android APK` / `Build Windows Instalador`.
- Artefactos: `Instalador_Android`, `Instalador_Windows`.
- Objetivo: consolidar features estables en `main` (release train); no dejar features solo en drafts eternos.
