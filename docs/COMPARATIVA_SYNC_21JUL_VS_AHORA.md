# Sync 21 jul vs ahora (campo)

## 1.4.48 — qué cambió tras tu prueba

| Problema | Fix |
| --- | --- |
| Tocaste Actualizar y el EXE se cayó | Botón = **solo limpia fantasmas** (cero Firebase) |
| Lista de productos distinta PC↔celular | Productos por **soft-pull** (inc + barrido catálogo), no listener 10k |
| Deletes que no cruzaban | Tombstone ahora lleva `actualizadoEn` |
| Apply enorme fallaba entero | Apply de productos en lotes de 35 |

## Qué sigue automático

- Listeners: ventas / remitos / clientes / compras → en segundos
- Soft-pull productos cada ~12–18s + barrido catálogo cada ~8 min
- Primer pull de productos ~25s después de abrir la PC
- Stock_ops inbound con techo ≤4

## Cómo probar 1.4.48

1. Instalá EXE + APK.
2. **No uses el botón** para sincronizar (solo limpia fantasmas).
3. Esperá ~1–2 minutos con ambos abiertos: la lista debería ir alineándose sola.
4. Probá una venta: debería verse en el otro dispositivo.
5. Si el EXE se cae, anotá: ¿al abrir? ¿solo? ¿tras X minutos?
