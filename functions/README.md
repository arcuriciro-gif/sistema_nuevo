# Cloud Functions — push FCM (alertas con APK cerrado)

## Qué hace
- `onNotificacionCreate`: al crear `tenants/{t}/notificaciones/{id}` → FCM al usuario destino
- `onPushRequestCreate`: al crear `tenants/{t}/push_requests/{id}` → FCM

## Deploy (una vez, plan Blaze)
```bash
cd functions && npm install
firebase login
firebase use tata-stock-8631e
firebase deploy --only functions,firestore:rules
```

Sin este deploy, el APK registra el token FCM pero **no hay quién envíe** el push con la app cerrada.
