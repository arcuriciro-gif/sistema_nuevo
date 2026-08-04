# VALIDACIÓN FINAL DEL ERP — Gate obligatorio

**Estado del producto tip:** `1.4.34+92`  
**Fecha de este documento:** 2026-07-30  
**Regla CTO:** el ERP **no** está terminado porque compile, pasen tests o sincronice una venta.  
**Solo** está terminado cuando supera una **jornada real de trabajo** (esta prueba).

Mientras falle un ítem de aprobación → **prohibido** agregar features nuevas. Primero estabilizar.

---

## 1. Prueba de campo (simulación de un día completo)

### Setup

| Requisito | Valor |
|---|---|
| PC | 1× Windows (EXE) |
| Móviles | 2–3 Android (APK) |
| Tenant | Mismo (`tata_stock` u otro real) |
| Datos | Mismos / compartidos |
| Modo | Trabajo **simultáneo** como negocio abierto |

Versión EXE = versión APK. Anotar build (`1.4.xx+yy`) al empezar.

---

### Productos

- [ ] Crear ≥ 20 productos nuevos  
- [ ] Editar varios  
- [ ] Eliminar algunos  
- [ ] Mover a papelera  
- [ ] Restaurar desde papelera  
- [ ] Buscar por código / descripción / marca / proveedor  
- [ ] Abrir fotos, zoom, cambiar fotos, varias fotos por producto  
- [ ] Fotos visibles en **todos** los dispositivos  

### Importaciones

- [ ] Importar lista **PDF**  
- [ ] Importar lista **Excel**  
- [ ] Importar lista **CSV**  
- [ ] Detección correcta: código, descripción, precio, proveedor (mínima intervención manual)

### Comparador de listas — CRÍTICO (herramienta de decisión)

Tras importar, el sistema debe informar **automáticamente**:

- [ ] Productos nuevos  
- [ ] Productos eliminados (faltan en la lista nueva)  
- [ ] Productos que aumentaron  
- [ ] Productos que bajaron  
- [ ] % de aumento / % de baja  
- [ ] Diferencia vs lista anterior  
- [ ] Diferencia vs otros proveedores  
- [ ] Proveedor con mejor precio  
- [ ] Productos con margen insuficiente  
- [ ] Productos bajo margen mínimo configurado  
- [ ] Precio sugerido para mantener el margen  
- [ ] Ganancia actual / anterior / diferencia de rentabilidad  

Criterio: **ayuda a decidir**, no obliga a comparar a mano.

### Clientes

- [ ] Crear / editar / eliminar / buscar  
- [ ] Historial / deuda / pagos / saldo  

### Cuenta corriente

- [ ] Ventas: pago total / parcial / sin pago  
- [ ] Pagos posteriores  
- [ ] Cancelar / saldar deudas  
- [ ] Saldo **igual** en todos los dispositivos  

### Ventas / remitos

- [ ] ≥ 30 ventas  
- [ ] ≥ 15 remitos  
- [ ] Descuentan stock donde corresponde  
- [ ] Historial + CC + sync OK  

### Compras

- [ ] Registrar compras  
- [ ] Actualizan costo / stock / listas  
- [ ] Sync OK  

### Stock

- [ ] Modificar stock desde distintos dispositivos  
- [ ] Ventas y compras **simultáneas**  
- [ ] Stock **idéntico** en todos (cero diferencias al final)  

### Precios

- [ ] Modificar ≥ 50 precios  
- [ ] Llegan a todos los dispositivos  
- [ ] Márgenes / sugeridos coherentes  

### Offline

- [ ] ≥ 2 h sin Internet en un dispositivo  
- [ ] Ventas, compras, precios, productos offline  
- [ ] Al reconectar: outbox vacía, sin duplicados, sin pérdidas, convergencia total  

### Estabilidad EXE

- [ ] Abierto toda la jornada  
- [ ] Sin freeze / cierre / pérdida de sync  
- [ ] Sin consumo de memoria anormal  

---

## 2. Criterios de aprobación (todos obligatorios)

| # | Criterio | Resultado campo |
|---|---|---|
| 1 | Productos sincronizados | ☐ PASS / ☐ FAIL |
| 2 | Fotos sincronizadas | ☐ PASS / ☐ FAIL |
| 3 | Stock idéntico en todos | ☐ PASS / ☐ FAIL |
| 4 | Precios idénticos en todos | ☐ PASS / ☐ FAIL |
| 5 | Facturas/remitos descuentan stock correctamente* | ☐ PASS / ☐ FAIL |
| 6 | Compras actualizan stock | ☐ PASS / ☐ FAIL |
| 7 | Cuenta corriente correcta | ☐ PASS / ☐ FAIL |
| 8 | Importación PDF / Excel / CSV | ☐ PASS / ☐ FAIL |
| 9 | Comparador genera info útil para decidir | ☐ PASS / ☐ FAIL |
| 10 | Recomienda precios y detecta ↑↓ / margen | ☐ PASS / ☐ FAIL |
| 11 | Offline sin intervención manual | ☐ PASS / ☐ FAIL |
| 12 | EXE estable toda la jornada | ☐ PASS / ☐ FAIL |
| 13 | Día completo sin errores críticos | ☐ PASS / ☐ FAIL |

\* Ver §3 — política de stock de Factura B vs Remito.

**Aprobado solo si los 13 están PASS.**  
Si alguno falla → estabilizar. **No** features nuevas.

---

## 3. Auditoría previa al campo (código tip `1.4.34`)

Esto **no** reemplaza la jornada. Solo evita sorpresas: qué puede pasar hoy vs qué ya se sabe incompleto.

### Leyenda

| Tag | Significado |
|---|---|
| LISTO PARA PROBAR | El código cubre el caso; el campo confirma |
| RIESGO | Puede fallar / hay lag / edge cases |
| BLOQUEA APROBACIÓN | Hoy el código **no** cumple el criterio escrito |

### Matriz

| Área | Tag | Nota honesta |
|---|---|---|
| Productos CRUD + papelera | LISTO PARA PROBAR | Soft-delete no toca stock; restore OK |
| Búsqueda código/desc/marca/proveedor | LISTO PARA PROBAR | En catálogo sí; en venta/remito el proveedor a veces no filtra |
| Fotos multi + zoom | RIESGO | Windows **no sube** a Storage (fotos locales). Sync fotos reales = APK↔nube. Validar sobre todo entre Androids |
| Import Excel/CSV (catálogo) | LISTO PARA PROBAR | Detecta codigo/desc/proveedor/precio/costo |
| Import PDF (comparador) | LISTO PARA PROBAR | Parser tipo lista proveedor; proveedor suele pedirse a mano |
| Import PDF en “Importar Productos” | BLOQUEA APROBACIÓN* | La página Importar **no** acepta PDF; el PDF entra por **Comparador** |
| Comparador: nuevos / ↑ / ↓ / % | LISTO PARA PROBAR | Estados `NUEVO` / `SUBIO` / `BAJO` / `IGUAL` |
| Comparador: productos eliminados | **BLOQUEA APROBACIÓN** | No detecta SKUs que faltan en la lista nueva |
| Comparador: vs otros proveedores / mejor precio | **BLOQUEA APROBACIÓN** | Un proveedor por corrida; sin matriz |
| Comparador: margen / sugerido / ganancia | **BLOQUEA APROBACIÓN** | No hay informe de margen/PVP sugerido/ganancia en el post-import |
| Remitos descuentan stock | LISTO PARA PROBAR | Canal oficial de entrega |
| Factura B descuenta stock | **NO APLICA / RIESGO de malentendido** | Política Opción B: **Factura documenta; Remito entrega**. Factura B **no** mueve stock (evita doble descuento). En campo: usar Remito o Venta Rápida (emite remito) |
| Compras suman stock | LISTO PARA PROBAR | |
| CC pago total/parcial/sin pago | LISTO PARA PROBAR | |
| CC “cancelar deuda” | RIESGO | No hay condonación limpia dedicada; saldar mal puede desalinearse del money ledger |
| Stock multi-dispositivo | RIESGO | Convergencia eventual; Windows hardCap≤4 → puede haber lag; al final del día debe ser idéntico |
| Offline outbox | LISTO PARA PROBAR | Cola única SQLite; ops `dead` requieren panel técnico |
| Estabilidad EXE jornada | RIESGO | Solo campo lo certifica |

\* Si el criterio exige “Importar Productos = PDF”, hoy falla. Si aceptamos “PDF vía Comparador”, el formato está cubierto.

### Veredicto pre-campo

> **Hoy el tip NO puede declararse terminado**, aunque sync y stock pasen la jornada, porque el **Comparador no es aún herramienta de decisión comercial** (faltan eliminados, multi-proveedor, márgenes, PVP sugerido, ganancias).  
> Además hay que alinear la expectativa de stock: **Remito mueve; Factura B no**.

Prioridad post-auditoría (solo si el campo lo exige para aprobar):

1. Completar comparador (gaps de decisión) — **antes** de “terminado”  
2. Estabilizar lo que falle en la jornada (stock/fotos/offline/EXE)  
3. Nada más

---

## 4. Protocolo de ejecución (operativo)

1. Instalar EXE + APK misma versión; login mismo tenant.  
2. Imprimir / abrir esta checklist; marcar en vivo.  
3. Empezar jornada; anotar hora inicio / fin.  
4. Ante bug: **no** seguir apilando features — reproducir, anotar dispositivo, hora, opId/panel técnico si aplica.  
5. Al final: stock sample de 20 SKUs en los 3–4 dispositivos (tabla); CC de 5 clientes; outbox vacía.  
6. Firmar §2: PASS/FAIL por criterio.  

### Plantilla rápida de stock (copiar)

| Código | EXE | APK1 | APK2 | APK3 | ¿Igual? |
|---|---|---|---|---|---|
| | | | | | |
| | | | | | |

### Plantilla CC

| Cliente | Saldo EXE | APK1 | APK2 | ¿Igual? |
|---|---|---|---|---|
| | | | | |

---

## 5. Relación con el stack de código

| Doc / PR | Rol |
|---|---|
| `docs/INFORME_ESTADO_APP_1.4.34.md` | Dónde quedó el tip vs `main` |
| Este documento | **Única definición de terminado** |
| PRs #114–#117 | Código tip a mergear **después** de jornada verde (o merge tip + jornada sobre ese build) |

**Orden correcto:** build tip → jornada → si PASS → merge a `main` / release.  
No mergear como “listo” solo porque CI está verde.

---

## 6. Firma de cierre

| Campo | Valor |
|---|---|
| Build probado | |
| Fecha jornada | |
| Operadores | |
| Resultado global | ☐ APROBADO / ☐ NO APROBADO |
| Fallos abiertos | |
| Firma | |
