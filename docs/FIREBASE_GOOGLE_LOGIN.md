# Google Login (Android) — ApiException 10

El error `ApiException: 10` aparece si Firebase no tiene el **SHA-1** del APK.

## Huellas de esta app

Paquete: `com.example.sistema_nuevo`  
Proyecto Firebase: `tata-stock-8631e`

### Firma estable (APK nuevos desde CI, keystore del repo)

- **SHA-1:** `A8:E0:3B:99:65:68:4C:7D:21:AC:DC:2A:EA:FF:BD:C8:5F:B4:E4:EF`
- **SHA-256:** `79:25:21:4A:72:B7:32:F8:63:50:D7:6E:36:DB:BD:EA:BB:D0:E6:8F:1E:C8:6A:25:0A:7E:2E:88:60:60:46:FC`

### APK anterior (firmado con debug de GitHub Actions)

- **SHA-1:** `9F:4B:ED:E9:52:CA:FD:40:F3:CC:12:20:51:30:C2:63:53:C8:EE:FB`
- **SHA-256:** `27:13:A3:B5:AA:61:2D:15:3B:4D:D1:EA:86:46:2D:AC:5E:72:06:F1:2E:28:7E:54:29:09:0F:31:4F:CB:39:8D`

## Pasos en Firebase (obligatorio)

1. Abrí [Firebase Console](https://console.firebase.google.com/) → proyecto **tata-stock-8631e**
2. ⚙️ Project settings → tu app Android `com.example.sistema_nuevo`
3. **Add fingerprint** → pegá **ambos** SHA-1 (y si pide, los SHA-256)
4. Authentication → Sign-in method → **Google** → Enabled
5. Descargá de nuevo `google-services.json` y reemplazá `android/app/google-services.json` (opcional pero recomendado)
6. Esperá 5–10 minutos, reinstalá el APK nuevo
7. (Fase 1) Publicá también `firestore.rules` y `storage.rules` del repo — sin membership las lecturas/escrituras de sync fallan

Sin este paso, Google en el celular **siempre** falla con error 10.
