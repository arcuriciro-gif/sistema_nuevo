# Sync comercio chico — 1.4.49

## Pedido de campo
Sin actualización manual (cae el EXE). Sync automática simple: productos,
precios, ventas, comprobantes, fotos. Papelera y “sin stock” alineados.

## Referencia estable
~21 jul (Fase 2 / ~1.2.18): listeners Firestore + outbox liviano.
Ahí “al instante” funcionaba. Después se agregó motor complejo y el botón.

## 1.4.49
| Ítem | Comportamiento |
| --- | --- |
| Botón Actualizar | **Eliminado** de la UI |
| Ventas / remitos / clientes | Listeners ON |
| Productos / precios | Listener solo de **cambios** + soft-pull catálogo |
| Snapshot 10k productos | **No se aplica** en PC (anti-crash) |
| Papelera | Tombstone remoto borra fila local (aunque haya upsert fantasma) |
| Fotos | Se ven por URL (subidas desde el celular) |
| Storage en PC | Sigue OFF (putData tumbaba el EXE) |

## Cómo probar
1. Instalá 1.4.49 en PC y celular.
2. Esperá ~30–60 s con ambos abiertos.
3. Vendé / cambiá precio / mandá a papelera / borrá definitivo.
4. No busques botón de actualizar: no existe.
