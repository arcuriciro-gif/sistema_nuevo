# Cómo generar APK y EXE (Tata.Manager)

Versión del proyecto: ver `pubspec.yaml` (`version: x.y.z+build`).  
En la pantalla de **login** debe verse abajo: **`Tata.Manager v1.1.4 (14)`** (o la versión actual).  
Si no aparece ese texto, estás abriendo una carpeta/EXE **vieja**.

Package Android: `com.eltatamanager.app`.

---

## Requisitos

### Comunes
- Repo actualizado (`git pull` de la rama que uses).
- `flutter pub get`
- Firebase: `android/app/google-services.json` con la app `com.eltatamanager.app` (ya registrado en la consola).

### Solo Windows (para el .exe)
- PC con **Windows 10/11**
- Flutter con desktop habilitado
- Visual Studio 2022 con workload **“Desktop development with C++”**

### Solo Android (para el .apk)
- Flutter + Android SDK  
  (o usar un APK ya compilado)

---

## A) Generar el APK (celular)

En la carpeta del proyecto:

```bash
flutter pub get
flutter build apk --release
```

**Archivo generado:**
```
build/app/outputs/flutter-apk/app-release.apk
```

### Instalar en el celular
1. Copiá el `.apk` al teléfono (WhatsApp, Drive, USB, etc.).
2. Si tenías la app vieja (`com.example…`), **desinstalala**.
3. Abrí el APK → permitir “fuentes desconocidas” si lo pide → **Instalar**.

### (Opcional) Firma propia / Play Store
Ver `docs/PLAY_STORE.md` (`key.properties`, AAB, Data Safety).

---

## B) Generar el EXE + carpeta para pendrive (varias PCs)

**Importante:** el `.exe` de Flutter **no viaja solo**. Hay que copiar **toda la carpeta** Release (DLLs + `data\`).

### 1. Compilar en una PC Windows

Abrí **CMD** o PowerShell en la carpeta del proyecto:

```bat
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

Salida interna:
```
build\windows\x64\runner\Release\
```
Ahí está `sistema_nuevo.exe` + dependencias.

### 2. Armar la carpeta para el pendrive

Todavía en Windows, en la raíz del proyecto:

```bat
scripts\preparar_instalador_windows.bat
```

Eso crea / actualiza:

```
Instalador_Windows\
  ABRIR_TATA_MANAGER.bat   ← doble clic para abrir
  LEEME.txt
  sistema_nuevo.exe
  data\
  *.dll
  ...
```

### 3. Copiar al pendrive

1. Copiá **toda** la carpeta `Instalador_Windows` al pendrive  
   (no solo el `.exe`).
2. En cada PC destino:
   - Pegá la carpeta donde quieras (ej. `C:\TataManager\`).
   - Abrí **`ABRIR_TATA_MANAGER.bat`**.
3. Si Windows bloquea: clic derecho en el `.bat` o `.exe` → Propiedades → **Desbloquear** (si aparece) → Aplicar.

### 4. Qué NO hacer
- No copies únicamente `sistema_nuevo.exe`.
- No borres la carpeta `data\` ni las DLL.
- No ejecutes el `.exe` desde dentro de un ZIP sin descomprimir.

---

## Resumen rápido

| Qué | Comando | Resultado |
|-----|---------|-----------|
| APK | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| EXE | `flutter build windows --release` | `build\windows\x64\runner\Release\` |
| Carpeta pendrive | `scripts\preparar_instalador_windows.bat` | `Instalador_Windows\` (copiar completa) |

---

## Checklist multi-PC / multi-celular

- [ ] Mismo `google-services.json` / proyecto Firebase Blaze
- [ ] Misma versión de app en todos los equipos (ideal)
- [ ] Usuarios con permisos correctos
- [ ] En Android: Bluetooth emparejado si usás impresora térmica
- [ ] En Windows: antivirus/firewall no bloqueando la carpeta

---

## Problemas frecuentes

**“Falta una DLL” / no abre el exe**  
→ Estás corriendo solo el `.exe`. Usá la carpeta `Instalador_Windows` completa.

**Dos íconos Tata en el celular**  
→ Quedó la app vieja (`com.example…`). Desinstalala.

**Login / sync falla**  
→ Revisá que Firebase tenga la app `com.eltatamanager.app` y el JSON correcto.

**Windows pide Visual C++**  
→ Instalá “Microsoft Visual C++ Redistributable” (x64) en esa PC.
