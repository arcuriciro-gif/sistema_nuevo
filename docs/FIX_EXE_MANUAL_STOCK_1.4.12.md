# Fix campo: crash .exe en "Actualizar ahora" + stock divergente (1.4.12+80)

## Síntoma

Tras tocar **Actualizar ahora** en el PC, el `.exe` se caía y algunos productos seguían con stock distinto respecto del celular.

## Causas

1. **Ráfaga en un solo gesto**: config + negocio + clientes + stock_ops + drain en el isolate de UI.
2. **Soft-pull encolaba ticks** mientras el anterior seguía corriendo → cola creciente.
3. **Catch-up Windows omitía `stock_ops`** → convergencia solo por soft-pull lento.
4. **Watermark** ya rebobinado en v1.4.4 (14d) podía haber dejado ops viejas sin aplicar tras crashes mid-apply.
5. **Proyección local** (`productos.stock`) podía quedar distinta del ledger si el proceso cortaba a mitad.

## Fixes

| Cambio | Efecto |
|--------|--------|
| Manual **stock-first** + micro-rondas + yield | No tumba el .exe; aplica más ops en total |
| Sin página de clientes en manual | Menos presión UI/Firestore |
| Soft-pull **busy-skip** + intervalo quieto cableado | Sin cola infinita; converge más rápido |
| Catch-up Windows con cupo mínimo stock_ops | Arranque ya acerca stock |
| Rewind watermark **30d v151** (una vez) | Reprocesa ops perdidas |
| `repararProyeccionesDivergentes` | Alinea stock local al ledger |
| Timeout badge 150s | No corta mid-apply a los 90s |

## Qué hacer en campo

1. Instalar **1.4.12+80** en PC y celular.
2. Abrir el PC, esperar ~1 min (cuarentena + soft-pull).
3. Tocar **Actualizar ahora** una o dos veces (ya no debería caerse).
4. Dejar corriendo 5–10 min; el soft-pull sigue aplicando stock_ops.
5. Comparar SKUs que divergían.

Si un SKU sigue distinto: anotar código, stock PC, stock APK y último remito/venta que lo movió.
