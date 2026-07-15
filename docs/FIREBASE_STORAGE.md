# Firebase Storage — fotos / logo

Sin esto, la app guarda fotos **en el equipo** pero no puede subirlas a la nube
(`object-not-found` / `permission-denied`).

## Pasos (una sola vez)

1. Entrá a [Firebase Console](https://console.firebase.google.com/) → proyecto **tata-stock-8631e**.
2. **Build → Storage → Get started** (si aún no está creado).
3. Pestaña **Rules** → pegá el contenido de `storage.rules` de este repo → **Publish**.
4. Reiniciá la app e intentá de nuevo el logo / foto.

Alternativa CLI (con Firebase CLI logueado):

```bash
firebase deploy --only storage
```

Firestore (costos, stock, sync) puede funcionar aunque Storage no esté listo.
Las fotos locales se siguen viendo en **este** dispositivo.
