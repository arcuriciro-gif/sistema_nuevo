# Walkthrough de Tester — Tata.Manager

**Fecha:** 2026-07-26  
**Complementa:** `AUDITORIA_QA_INTEGRAL_2026-07-26.md`  
**Regla:** no asumir que “compila ⇒ funciona”. Cada flujo tiene:

| Etiqueta | Significado |
|---|---|
| **PRODUCIDO** | Demostrado con test automático en esta sesión (`test/auditoria_comportamiento_adversarial_test.dart` — **11/11 OK**) |
| **OBSERVADO EN CAMPO** | Crash/comportamiento visto por el usuario/agente el 2026-07-26 |
| **HIPÓTESIS DE CÓDIGO** | Ruta leída en código; no ejecutada en UI/runtime real |
| **NO VERIFICABLE AQUÍ** | Requiere device físico / Meta / AFIP / 2 dispositivos |

---

## Cómo leer este documento

Para cada módulo: **guion mental del tester** → **qué pasó / qué pasaría** → **certeza** → **prueba concreta** si falta runtime.

---

## 0. Arranque de app

### Guion
1. Abrir `.exe` / APK  
2. Login `admin` / clave  
3. Ver Inicio  

### Qué mirar
- ¿Pide admin123 en instalación limpia?  
- ¿Modo seguro Firebase aparece tras crash?  
- ¿Tiempo hasta UI usable?  

### Certeza
- Login local / hash: **HIPÓTESIS DE CÓDIGO** (`auth_service`)  
- Safe mode tras crash sync: **OBSERVADO EN CAMPO** (diseño del marker; usuario tuvo crashes)  
- Tiempo de arranque: **NO VERIFICABLE AQUÍ**

### Prueba concreta
1. PC limpia: instalar 1.2.33+38  
2. Cronometrar hasta Inicio  
3. Forzar crash mid-sync (Task Manager) → reabrir → anotar si entra “solo local”

---

## 1. Inicio

### Guion
1. Ver KPIs del día  
2. Tocar “Nueva venta” / accesos rápidos  
3. Hacer una venta y volver  

### Qué mirar
- KPIs remitos+facturas mezclados  
- Acceso rápido sin permiso = ¿snackbar o silencio?  
- ¿La pantalla se traba al volver?  

### Certeza
- Suma remitos+ventas en analytics: **HIPÓTESIS DE CÓDIGO**  
- Quick action silenciosa si módulo oculto: **HIPÓTESIS DE CÓDIGO**  
- Jank post-venta: **NO VERIFICABLE AQUÍ** (DataRefreshHub refresca cache)

### Prueba concreta
1. Usuario empleado sin “Venta Rápida” en menú  
2. En Inicio tocar “Nueva venta”  
3. Esperado sano: mensaje “sin permiso”. Si no pasa nada → bug UX confirmado

---

## 2. Dashboard

### Guion
1. Abrir Dashboard  
2. Comparar “Valor stock” vs Excel costo×stock  
3. Contar “críticos” vs productos con stock 0  

### Certeza
- Valor = precio×stock: **HIPÓTESIS DE CÓDIGO** (`dashboard_page`)  
- Críticos incluyen sin stock: **HIPÓTESIS DE CÓDIGO**

### Prueba concreta
1. Producto stock 10, costo 100, precio 200  
2. Dashboard debe mostrar 2000 si usa precio; 1000 si usa costo  
3. Anotar cuál muestra

---

## 3. Productos

### Guion (romper)
1. Alta sin código  
2. Alta con mismo código dos veces  
3. Costo −5  
4. Precio −50  
5. Soft-delete → eliminar definitivo  
6. Foto local sin nube  

### PRODUCIDO (tests automáticos)
| Caso | Resultado real |
|---|---|
| Código vacío | **Se guarda** |
| Código duplicado | **Se permiten 2 filas** |
| Costo negativo | **Se guarda −5** |
| Precio −50 | Service **no rechaza**; calculador **sobrescribe** a precio > 0 |
| Hard-delete | **Borra local**; **0** ops `delete` en outbox |

### NO VERIFICABLE AQUÍ
- Foto sube a Storage en Windows real  
- UI del form bloquea o no el botón Guardar  

### Prueba concreta (campo)
1. Productos → Nuevo → dejar código vacío → Guardar  
2. Repetir con código `DUP` dos veces  
3. En otro device con sync: ver si `DUP` colapsa o duplica en nube  
4. Papelera → eliminar definitivo → sync → peer: ¿revive?

---

## 4. Clientes / Proveedores

### Guion
1. Cliente con límite 100  
2. Venta CC 1000  
3. Editar saldo a 9999 a mano  
4. CUIT `abc` + Factura A  

### PRODUCIDO
| Caso | Resultado |
|---|---|
| `limiteCuenta=100` + remito pendiente 1000 | **Pasa**; saldo > 100 |
| Actualizar cliente con saldo 1234 | **Persiste 1234** |

### NO VERIFICABLE AQUÍ
- UI muestra/oculta campo saldo  
- Validación CUIT en Factura A (solo no-vacío en código)

### Prueba concreta
1. Cliente límite $100  
2. Venta rápida / remito pendiente $1000  
3. Si deja guardar → bug de crédito confirmado en UI  
4. Factura A con CUIT `20-123` inválido → ¿bloquea?

---

## 5. Venta rápida

### Guion
1. Agregar ítem  
2. Subir cantidad > stock  
3. Double-tap Finalizar  
4. Cobrar  
5. Compartir PDF / Después  

### PRODUCIDO (servicio = mismo insertar que usa la página)
- Remito baja stock  
- Dos insertar seguidos = dos remitos + doble baja  

### OBSERVADO EN CAMPO
- `.exe` se cerró al finalizar (2026-07-26) → mitigado en 1.2.33+38; **re-test obligatorio**

### HIPÓTESIS DE CÓDIGO
- `_finalizando` se setea tarde → UI puede double-tap  
- Carrito no avisa stock si negativos permitidos  

### Prueba concreta (campo — checklist)
1. Instalar **1.2.33+38**  
2. Stock producto = 2  
3. Venta rápida qty 5 → ¿avisa? ¿guarda? (default negativos ON → probablemente guarda a −3)  
4. Double-tap Finalizar + confirmar dos diálogos → contar remitos  
5. Finalizar normal 10 veces seguidas en Windows → ¿crash?

---

## 6. Remitos

### Guion
1. Crear salida  
2. Anular  
3. Eliminar  
4. Imprimir/compartir  

### PRODUCIDO
- Insertar baja stock  

### HIPÓTESIS DE CÓDIGO
- Eventos ledger **después** de TX → crash mid-sale deja remito sin stock  
- Delete Windows: wipe local antes de tombstone remoto  

### Prueba concreta
1. Remito 1 unidad  
2. Matar proceso con Process Explorer **inmediatamente** tras snackbar “guardado”  
3. Reabrir: ¿stock bajó? ¿remito existe?  
4. Matriz esperada sana: ambos coherentes. Si remito sí / stock no → **C2 confirmado en campo**

---

## 7. Facturación A / B / C

### Guion
1. Factura B cobrada 3 u  
2. Ver stock  
3. Factura A con precio lista  
4. AFIP sin certificado  

### PRODUCIDO
- **Factura B no cambia stock** (10 → 10 tras vender 3)

### HIPÓTESIS DE CÓDIGO
- Factura A suma 21%  
- AFIP pendiente no bloquea  

### Prueba concreta
1. Stock 10 → Factura B qty 3 cobrada → stock sigue 10 = bug confirmado UI  
2. Precio 121 (IVA incl.) → Factura A → total ¿~146?  
3. Activar AFIP sin cert → ¿deja “guardada OK”?

---

## 8. Compras

### Guion
1. Compra 5 u costo nuevo  
2. Ver stock y costo  

### Certeza
- **HIPÓTESIS DE CÓDIGO** (evento recepción + ledger)  
- **NO VERIFICABLE AQUÍ** en esta pasada (no se escribió test de compra)

### Prueba concreta
1. Producto stock 0  
2. Compra 5 @ costo 80  
3. Esperado: stock 5, costo actualizado según reglas del servicio  
4. Anular compra → stock vuelve

---

## 9. Cuenta corriente

### PRODUCIDO
- Límite no bloquea  
- Saldo pisable  

### Prueba concreta
1. Cliente con deuda  
2. Pago parcial  
3. Recalcular  
4. Comparar con suma remitos+facturas pendientes a mano

---

## 10. Inventario / Stock

### PRODUCIDO
- Negativos default ON  
- Remito mueve; factura no  

### Prueba concreta
1. Config → desactivar stock negativo  
2. Remito qty > stock → debe fallar  
3. Reactivar negativos → debe pasar

---

## 11. Sincronización (crítico)

### Guion mental (2 devices)
| Paso | Acción | Esperado sano |
|---|---|---|
| 1 | PC crea producto | APK lo ve |
| 2 | APK vende remito | Stock baja en ambos |
| 3 | PC factura | Stock baja en ambos (**hoy falla PRODUCIDO en local**) |
| 4 | Cortar net mid-venta | Local OK; luego outbox drena |
| 5 | Kill mid-sync | Safe mode / reclaim inflight |
| 6 | Mismo SKU edit precio PC+APK | Un ganador LWW; conflicto visible |

### OBSERVADO EN CAMPO
- Sync tumba `.exe`  
- Badge 0 pending / 10 inflight  
- Mitigaciones 1.2.32–1.2.33  

### NO VERIFICABLE AQUÍ
- Convergencia real PC↔APK  
- LWW conflicto UI  
- Catch-up 10k productos  

### Prueba concreta (protocolo de campo — 45 min)
**Setup:** PC + APK misma empresa, reloj OK, build ≥ 1.2.33+38  

1. **A1** PC: alta `SYNC-A` stock 10 → esperar badge “en la nube” → APK pull → ¿existe?  
2. **A2** APK: venta rápida 2 u → PC: stock ¿8?  
3. **A3** PC: Factura B 2 u del mismo → stock ¿6 o 8? (si 8 = C1 en campo)  
4. **A4** Airplane PC: alta `SYNC-OFF` → reactivar red → ¿sube?  
5. **A5** Durante Sync en PC: Task Manager End Task → reabrir → ¿modo seguro? ¿datos rotos?  
6. **A6** Ambos editan precio de `SYNC-A` offline → online → anotar ganador + si hay conflicto en panel  
7. **A7** Hard-delete en PC → APK tras sync → ¿desapareció?

---

## 12. Outbox

### PRODUCIDO (indirecto)
- Hard-delete sin enqueue delete  

### HIPÓTESIS
- Reclaim 90s Windows  
- Dead tras 12 intentos  

### Prueba concreta
1. Airplane → 5 ventas  
2. Ver panel técnico / badge pending > 0  
3. Online → pending → 0  
4. Forzar error (token Firebase inválido) → ¿aparecen dead?

---

## 13. WhatsApp / CRM

### Certeza
- Token en prefs: **HIPÓTESIS DE CÓDIGO**  
- Catalog necesita foto https: **HIPÓTESIS DE CÓDIGO**  
- CRM local-only: **HIPÓTESIS DE CÓDIGO**  
- Envío Meta real: **NO VERIFICABLE AQUÍ**

### Prueba concreta
1. WA Business: token + Phone ID → Probar conexión  
2. Catalog ID → Probar catálogo  
3. Producto con foto solo local → Sync favoritos → debe fallar/omitir  
4. Seguimiento en PC → abrir APK → ¿hay agenda? (esperado: no)

---

## 14. Windows / Android UX

### OBSERVADO EN CAMPO (Windows)
- Crash Sync  
- Crash Venta rápida  
- Inflight stuck  

### NO VERIFICABLE AQUÍ
- Rotación Android  
- Multitarea  
- SmartScreen  
- Memoria tras 100 ventas  

### Prueba concreta Android
1. Venta rápida → rotar pantalla mid-cobro  
2. Home → volver → ¿carrito intacto?  
3. Negar permiso notificaciones → CRM “Probar aviso”

---

## 15. Seguridad (tester)

### Prueba concreta
1. Copiar `*.db` de Documentos a otra PC → ¿entra con hash crackeable?  
2. Empleado: ¿puede abrir Config por ícono?  
3. Export CSV sin permiso menú (si hay deep link)

---

## Matriz de certeza — hallazgos P0

| Hallazgo | Certeza ahora |
|---|---|
| Factura no mueve stock | **PRODUCIDO** |
| Remito mueve stock | **PRODUCIDO** |
| Double-submit servicio = 2 remitos | **PRODUCIDO** |
| Stock negativo default | **PRODUCIDO** |
| Código vacío / duplicado | **PRODUCIDO** |
| Costo negativo | **PRODUCIDO** |
| Límite CC cosmético | **PRODUCIDO** |
| Saldo CC pisable | **PRODUCIDO** |
| Hard-delete sin tombstone outbox | **PRODUCIDO** |
| Precio −50 persiste | **REFUTADO** (calculador sobrescribe) |
| Double-tap UI | **HIPÓTESIS** → prueba campo |
| Crash mid-TX ledger | **HIPÓTESIS** → prueba kill |
| Sync Windows crash | **OBSERVADO** → re-test 1.2.33 |
| LWW / 2 devices | **NO VERIFICABLE AQUÍ** |
| AFIP / Meta API | **NO VERIFICABLE AQUÍ** |

---

## Cómo correr las pruebas PRODUCIDAS

```bash
flutter test test/auditoria_comportamiento_adversarial_test.dart
```

Resultado de esta sesión: **11/11 passed**.

---

## Veredicto de tester (sin asumir UI)

Con evidencia **ejecutada** (no solo lectura):

1. El ERP tiene **dos mundos de inventario** (remito≠factura) — defectivo.  
2. Validaciones maestras (código, duplicados, costos, crédito) **no existen en dominio**.  
3. Deletes definitivos **no están listos para multi-device**.  
4. Windows tuvo fallos reales de proceso; hace falta **batería de campo** post-1.2.33.  

**Sigue: NO APTO PARA PRODUCCIÓN** hasta cerrar P0 y pasar el protocolo de campo §11.
