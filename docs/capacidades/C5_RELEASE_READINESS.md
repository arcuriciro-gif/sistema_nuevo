# Capacidad 5 — Release readiness (auditoría de entrega)

| Campo | Valor |
|---|---|
| Estado | Implementada en código — certificación sujeta a CI en `main` + drill de restore |
| Rama | `cursor/capacidad-5-release-readiness-e44b` |
| Depende de | Capacidad 4 (mergeada #34) |
| Versión app | `1.1.0+2` |

## Objetivos vs entrega (Fases E / F / G del roadmap)

| Objetivo | Estado | Evidencia |
|---|---|---|
| E1 — integrity_check al abrir + cuarentena `.bad` | Hecho | `DatabaseHelper._initDatabase` |
| E2 — restore atómico + checksum + dry-run | Hecho | `BackupService.validarArchivo` / `restaurarDesdeArchivo` |
| E3 light — ALTER no swallow-all | Hecho | `_agregarColumnas` solo ignora duplicate column |
| Retención backups | Hecho | `podarBackupsAntiguos` (keep 7) |
| F2 — CI en `main` + analyze + tests | Hecho | workflows Android/Windows |
| F3 light — SHA-256 artefactos | Hecho | `SHA256SUMS.txt` en Instalador_* |
| F6 light — script instalador + Inno unsigned | Hecho | `preparar_instalador_windows.bat` + `tata_manager.iss` |
| G1 light — panel técnico admin | Hecho | `PanelTecnicoPage` + `TechnicalHealthService` |
| Versionado visible | Hecho | `package_info_plus` en panel; `pubspec` 1.1.0+2 |
| Tests | Hecho | `test/capacidad5_backup_test.dart` |
| Runbook restore | Hecho | `docs/runbooks/BACKUP_RESTORE.md` |

## Diferido (ops / siguientes)

| Ítem | Motivo |
|---|---|
| F4 package `com.eltatamanager.app` | Requiere plan migración Play/Firebase |
| F5 R8/ProGuard | Mapping + QA release |
| F6 Authenticode / MSIX store | Certificado comercial |
| E5 backup cifrado | Crypto + UX de claves |
| G2 Sentry/Crashlytics | Cuenta + PII policy |
| F7 canal update Windows | Infra aparte |

## Checklist de certificación Capacidad 5

- [x] Restore no borra DB viva antes de validar
- [x] Integrity check en open
- [x] Panel técnico solo admin
- [x] CI branches incluyen `main` + esta rama
- [x] Checksums en artefactos
- [ ] **CI verde** en esta PR
- [ ] **Campo:** export → validar → restore → reiniciar → datos OK
- [ ] **Campo:** backup corrupto rechazado sin perder DB

## Veredicto

Capacidad 5 **lista para merge de desarrollo** tras CI verde.  
Cierra el núcleo de release readiness sin Authenticode ni renombre de package.
