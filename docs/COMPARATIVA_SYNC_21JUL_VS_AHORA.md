# Panel comparativo: sync 21 jul vs ahora

> **1.4.47:** se restauró la sync automática simple (listeners + soft-pull)
> para que pruebes como el 21 jul. Si el EXE se cae, avisá qué estabas haciendo.

Referencia de campo (tus palabras, ~21 jul):

> “envié una a la papelera y se eliminó del otro, creé un producto y se actualizó al instante”
> “el stock se actualiza en ambos dispositivos”

---

## Resumen

| Época | Prioridad | Resultado |
| --- | --- | --- |
| **21 jul** | Sync al instante | Productos / ventas / stock en segundos |
| **1.4.42–1.4.46** | EXE no se cae | PC casi no bajaba nada |
| **1.4.47 (esta)** | Volver al 21 jul | Listeners + soft-pull ON otra vez |

---

## Qué se reactivó en 1.4.47

| Mecanismo | 1.4.46 | 1.4.47 |
| --- | --- | --- |
| Listeners ventas/remitos/clientes/compras | OFF | **ON** |
| Listener productos (docChanges) | OFF | **ON** |
| Soft-pull periódico | OFF | **ON (~15–25s)** |
| stock_ops inbound | OFF | **ON (techo ≤4)** |
| Primer pull productos al abrir | OFF | **ON** |
| Pump | Solo subir ~120s | Sube y baja ~30s |
| Botón Actualizar | Solo fantasmas | Opcional (sync es automática) |

---

## Cómo probar

1. Instalá EXE + APK **1.4.47**.
2. Esperá ~20s tras abrir la PC (arranque).
3. Creá/editá un producto o una venta en un dispositivo → debería verse en el otro en segundos/poco.
4. Si el EXE se cae, anotá: ¿al abrir? ¿al vender? ¿al tocar Actualizar? ¿después de cuántos minutos?
