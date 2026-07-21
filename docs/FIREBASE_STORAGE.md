# Firebase Storage — fotos / logo

Sin esto, la app guarda fotos **en el equipo** pero no puede subirlas a la nube
(`object-not-found` / `permission-denied`).

## Pasos (una sola vez)

1. Entrá a [Firebase Console](https://console.firebase.google.com/) → proyecto **tata-stock-8631e**.
2. **Build → Storage → Get started** (si aún no está creado).
3. **Orden recomendado (Fase 1):**
   1. Instalá el APK/EXE nuevo (crea `tenants/{tenant}/members/{uid}` al conectar).
   2. Publicá **Firestore rules** (`firestore.rules`).
   3. Publicá **Storage rules** (`storage.rules`).
4. Pestaña **Rules** → pegá el contenido de `storage.rules` de este repo → **Publish**.
5. Reiniciá la app e intentá de nuevo el logo / foto.

Alternativa CLI (con Firebase CLI logueado):

```bash
firebase deploy --only firestore:rules,storage
```

**Importante:** las Storage rules de Fase 1 exigen membresía en Firestore.
Si publicás Storage rules antes de que algún dispositivo cree `members/{uid}`,
las fotos fallan con `permission-denied` hasta el primer login con nube.

Firestore (costos, stock, sync) puede funcionar aunque Storage no esté listo.
Las fotos locales se siguen viendo en **este** dispositivo.
