# Capacidad 2 — Sincronización certificable (auditoría de entrega)

| Campo | Valor |
|---|---|
| Estado | **CERTIFICADA CONDICIONALMENTE** (desarrollo cerrado; campo multi-dispositivo abierto) |
| Rama | `cursor/capacidad-2-sync-certificable-e44b` |
| Depende de | Capacidad 1 (certificada condicionalmente) |

## Objetivos vs entrega

| Objetivo | Estado | Evidencia |
|---|---|---|
| Outbox Pattern | Hecho | Tabla `sync_outbox` + `SyncOutbox` |
| ACK explícito | Hecho | `ack()` solo tras upload/tombstone OK; no se vacía cola antes |
| Tombstones | Hecho | `deletedAt`/`tombstone` en remoto; apply borra local |
| Idempotencia | Hecho | `op_id` estable `upsert\|delete:tipo:id` |
| Cola persistente | Hecho | SQLite v26; migración desde prefs |
| Reintentos | Hecho | backoff + `reclaimStaleInflight` (crash/luz) |
| Conflictos | Hecho | LWW skip → `sync_conflicts` + resolución `remote_wins` |
| Health Check | Hecho | `SyncHealthService.snapshot()` |
| Métricas | Hecho | cycles, acks, fails, duration, pending/dead |
| Watermarks persistentes | Hecho | `sync_watermarks` (sobrevive reinicio) |
| Tests | Hecho | `test/capacidad2_sync_test.dart` |

## Checklist de certificación Capacidad 2

- [x] Compila / CI
- [x] Schema v26 forward-only
- [x] Outbox no se borra antes de ACK
- [x] Deletes offline encolan tombstone
- [x] Health refleja estado real (no “En la nube” con dead/pending)
- [ ] **Campo:** PC + APK, kill mid-sync → pendientes recuperan
- [ ] **Campo:** delete remito offline → aparece tombstone y desaparece en el otro
- [ ] **Campo:** 2 dispositivos editan cliente → conflicto registrado, sin corrupción
- [ ] **Campo:** 0 pérdida de datos en cola tras reinicio

## Limitaciones conocidas

1. Catch-up sigue limitando a 2000 docs recientes (paginación completa = mejora posterior).
2. Soft-delete cloud (`deletedAt`) no hard-borra el doc (auditoría); limpieza TTL opcional.
3. Custom claims Admin SDK siguen pendientes (C1).
4. Pruebas multi-dispositivo automatizadas E2E requieren Firebase emulator (no en este PR).

## Veredicto

Capacidad 2 **certificada condicionalmente** para avanzar a Capacidad 3.  
Certificación plena de sync sigue exigiendo las pruebas de campo del checklist.
