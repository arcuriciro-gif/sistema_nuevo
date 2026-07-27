# Causa raíz — crash Navigator en Productos (1.4.6+74)

## Síntoma
```
Null check operator used on a null value
StatefulElement.state → findAncestorStateOfType → Navigator.of → Navigator.push
productos_page.dart:583
```

## Flujo exacto hasta el crash

1. `ListView.builder` crea un tile con `itemBuilder: (context, index)`.
2. `onOpen` captura ese **`context` del ítem** (Element del tile).
3. Se hace `Navigator.push` a `ProductoDetallePage` pasando closures `onEdit` / `onDelete` / `onToggleFavorito` que **cierran sobre ese mismo context del ítem**.
4. Mientras la ficha está abierta, `DataRefreshHub` (sync stock/productos) llama `cargarProductos()` → `setState` → el `ListView` **reconstruye y dispone** los tiles viejos.
5. El `Element` del ítem queda **defunct** (`_state == null`).
6. El usuario toca **Editar** en la ficha → `onEdit` ejecuta `Navigator.push(context, …)` con el context **ya muerto**.
7. `Navigator.of(context)` busca `NavigatorState` vía `findAncestorStateOfType`.
8. Al tocar el `StatefulElement` defunct, el getter `state` hace `_state!` → **Null check operator**.

La línea 583 no es “un bug de push”: es el **punto de detonación**. El origen es el **ciclo de vida del BuildContext capturado en el closure**.

## Por qué `context.mounted` no salvaba el push de Edit

El check `if (context.mounted)` estaba **después** del `await Navigator.push` interno, no antes. Además, aunque se checkeara, el diseño seguiría siendo incorrecto: un context de ListView no debe usarse para navegación anidada desde otra ruta.

## Solución correcta (Flutter)

1. Abrir el detalle con el **context del `State` de `ProductosPage`** (`_abrirDetalle`), que vive mientras la página del `IndexedStack` esté montada.
2. **Eliminar callbacks de navegación** que capturen context ajeno.
3. Que `ProductoDetallePage` posea Edit / Papelera / Favorito y navegue solo con **su propio** `BuildContext` de ruta.
4. Devolver `ProductoDetalleResult` al listado para refrescar.

No se usa try/catch para ocultar el crash.
