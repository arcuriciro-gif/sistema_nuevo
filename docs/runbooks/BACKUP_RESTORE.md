# Runbook — Backup y restauración (Tata.Manager)

Capacidad 5 · Uso operativo

## Exportar backup

1. Iniciar sesión con usuario que tenga permiso `backup` → editar (admin siempre puede).
2. Menú **Respaldo** → exportar / compartir.
3. Se genera `eltata_backup_YYYYMMDD_HHMMSS.db` + archivo `.sha256`.
4. Se valida con `PRAGMA integrity_check` antes de entregar el archivo.
5. Se conservan los **7** backups más recientes en Documentos (poda automática).

## Restaurar (solo administrador)

1. Menú **Respaldo** → Restaurar.
2. Elegir el `.db` de backup.
3. La app hace **dry-run**: abre el archivo y exige `integrity_check = ok`.
4. Si falla → **no toca** la base viva; muestra error.
5. Si OK:
   - Copia a `eltata.db.restore_tmp` y revalida
   - Cierra la DB viva
   - Renombra viva → `eltata.db.pre_restore`
   - Promueve el tmp a `eltata.db`
   - Escribe `eltata.db.restore_meta.json`
6. **Reiniciar la app** (obligatorio).

## Si algo sale mal

- Base previa: `eltata.db.pre_restore` (junto a la DB).
- DB corrupta al abrir: se renombra a `eltata.db.bad.<timestamp>` y se crea una limpia.
- Panel técnico (admin): versión, schema, sync health, último backup/restore.

## Verificación post-restore

- [ ] Login OK
- [ ] Productos / clientes visibles
- [ ] Remito de prueba no duplica stock anómalo
- [ ] Sync: cola sin `dead` (Panel técnico)

## CI / artefacto

Tras build, verificar `SHA256SUMS.txt` dentro de `Instalador_Android` / `Instalador_Windows`.
