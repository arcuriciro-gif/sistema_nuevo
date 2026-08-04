# Panel comparativo: sync 21 jul vs ahora (1.4.46)

Referencia de campo (tus palabras, ~21 jul):

> “envié una a la papelera y se eliminó del otro, creé un producto y se actualizó al instante”
> “el stock se actualiza en ambos dispositivos”

Eso era **sync en tiempo real** (Firestore listeners). Hoy la PC **casi no baja nada** de la nube: se priorizó que el EXE no se caiga.

---

## Resumen en una frase

| Época | Qué priorizaba | Resultado en el local |
| --- | --- | --- |
| **21 jul (~1.0.0+1 Fase 2)** | Que se vea al instante en todos los dispositivos | Productos / ventas / stock en segundos |
| **Ahora 1.4.46** | Que el EXE de Windows no se caiga | PC estable, pero **ya no sincroniza “como corresponde”** |

---

## Tabla de mecanismos

| Mecanismo | 21 jul (andaba) | Ahora 1.4.46 | Efecto |
| --- | --- | --- | --- |
| **Listeners Firestore en PC** (productos, ventas, remitos, clientes, compras…) | **ON** — cada cambio remoto llega al toque | **OFF** (`enableBusinessDocListeners → false`) | Ya no hay “en segundos” en la PC |
| **Soft-pull periódico** | No hacía falta | **OFF** | La PC no “baja” productos/stock sola |
| **Pump de fondo** | Subía cola (~40s) + listeners bajaban | Solo **sube** cola local cada **~120s** (`outboundOnlyPump`) | PC → nube lenta; nube → PC **no** |
| **Botón Actualizar / Limpiar** | **No existía** | Solo limpia fantasmas locales (cero Firebase) | No trae ventas/productos del celular |
| **Inbound stock_ops en PC** | Via listeners / apply remoto | **OFF** (`stockOpsEveryNTicks = 0`) | Stock del celular no llega a la PC |
| **Pull productos al arrancar** | Catch-up / listeners | **OFF** (`skipPrimerPullProductos`) | Catálogo puede quedar viejo en PC |
| **Prioridad de diseño** | Convergencia multi-dispositivo | Supervivencia del EXE | Trade-off consciente anti-crash |

---

## Línea de tiempo: qué se tocó después del 21 jul

```text
21 jul  — Listeners ON. Producto/papelera/stock “al instante”. (EXE a veces se cierra solo.)
23 jul  — 1.2.19: en PC se apagan listeners pesados → bombas / soft-pull (minutos, no segundos).
26 jul  — Cuarentena login, sync “ultra-light”, pendientes fantasma.
27 jul  — Nace “Actualizar ahora” (pantallazo). El botón empieza a tumbar el EXE.
27 jul  — 1.2.57: intento de volver a segundos (listeners negocio sin productos).
28–30 jul — Techos anti-crash, freeze background, soft-pull acotado.
1–3 ago — “Modo tranquilo” → supervivencia → solo-salida → inbound solo manual.
4 ago   — 1.4.45/46: botón push-only / solo local. EXE más estable. Sync “como 21 jul” perdida en PC.
```

El corte decisivo para el “en segundos” fue **apagar los listeners en Windows** (23 jul en adelante), no el botón manual. El botón empeoró las caídas; la sync lenta/rota viene del modo solo-salida.

---

## Qué sí / qué no hace cada dispositivo hoy

| Acción | Celular (APK) | PC (EXE 1.4.46) |
| --- | --- | --- |
| Crear producto / venta / comprobante | Sube y baja (listeners/pull) | Sube en segundo plano; **casi no baja** |
| Ver venta hecha en el otro dispositivo | Sí (si el otro subió) | **No en segundos** (no hay inbound) |
| Stock alineado | Puede converger | **No automáticamente** desde el celular |
| Abrir app sin caerse | OK | Objetivo #1 actual |
| Botón sync | Actualiza de verdad | Solo limpia pendientes fantasma |

---

## Por qué “rompe todo” la sync (causa raíz)

No es un bug suelto de un producto: es una **política**.

Para salvar el EXE se fueron apagando, uno a uno, los caminos que bajaban datos:

1. Listeners de negocio  
2. Soft-pull  
3. Poll de remitos / stock_ops  
4. Pull al boot  
5. Pull en el botón manual  

Quedó una PC que **casi solo escribe hacia la nube**. Por eso los productos ya no se “sienten” iguales y una venta no se refleja en segundos en la PC.

---

## Camino para recuperar el 21 jul (sin volver al crash de golpe)

Orden seguro (de menos a más riesgo):

1. **Listeners livianos solo de negocio** en PC: `remitos` + `ventas` (+ opcional `clientes`) con `docChanges` — como `1.2.57`. Eso recupera “hice una venta y se ve en segundos”.
2. **Micro soft-pull de productos** (páginas chicas, techo bajo) — no snapshot de 10.000.
3. **stock_ops inbound** con `hardCap ≤ 1` cada N minutos — no ráfagas.
4. Dejar el botón **sin pull masivo** (ya aprendido: tumba el EXE).
5. Validar jornada de campo antes de volver a listeners de productos completos.

---

## Referencias de código

- Política actual: `lib/core/sync/windows_sync_policy.dart` (`outboundOnlyPump`, `manualRefreshLocalOnly`, listeners OFF).
- Orquestación: `lib/core/sync/firestore_sync_service.dart` (`_iniciarOutboxPump`, `actualizarAhora`).
- Época que andaba: ~21 jul con `snapshots().listen` en ventas/remitos/productos (commits tipo Fase 2 / `1.0.0+1`–`1.2.18`).
- Último intento de “segundos”: `836c3bb` — `1.2.57+65` listeners negocio Windows.
