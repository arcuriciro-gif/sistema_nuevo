#!/usr/bin/env python3
"""Genera el Manual de uso Tata.Manager (PDF compartible fuera de la app)."""

from __future__ import annotations

import os
from pathlib import Path

from fpdf import FPDF
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path("/opt/cursor/artifacts/assets")
OUT = Path("/opt/cursor/artifacts/TataManager_Manual_de_Uso_v1.2.3.pdf")
DOCS_OUT = ROOT / "docs" / "TataManager_Manual_de_Uso_v1.2.3.pdf"

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

ORANGE = (255, 122, 0)
DARK = (15, 20, 25)
GRAY = (70, 78, 88)
LIGHT = (245, 246, 248)


def prep_phone(src: Path, dest: Path, max_w: int = 420) -> Path:
    im = Image.open(src).convert("RGB")
    # Recorte suave del marco si sobra margen blanco
    w, h = im.size
    # Resize manteniendo proporción
    ratio = max_w / w
    im = im.resize((max_w, int(h * ratio)), Image.Resampling.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, "PNG", optimize=True)
    return dest


class ManualPDF(FPDF):
    def __init__(self) -> None:
        super().__init__(format="A4", unit="mm")
        self.set_auto_page_break(auto=True, margin=18)
        self.add_font("DejaVu", "", FONT)
        self.add_font("DejaVu", "B", FONT_B)
        self.set_margins(16, 16, 16)

    def header(self) -> None:
        if self.page_no() == 1:
            return
        self.set_font("DejaVu", "B", 9)
        self.set_text_color(*ORANGE)
        self.cell(0, 6, "Tata.Manager — Manual de uso", align="L")
        self.set_text_color(*GRAY)
        self.set_font("DejaVu", "", 8)
        self.cell(0, 6, "v1.2.3", align="R", new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(*ORANGE)
        self.set_line_width(0.3)
        self.line(16, self.get_y(), 194, self.get_y())
        self.ln(4)

    def footer(self) -> None:
        self.set_y(-14)
        self.set_font("DejaVu", "", 8)
        self.set_text_color(*GRAY)
        self.cell(0, 8, f"Página {self.page_no()}  ·  Uso interno / compartir con el equipo", align="C")

    def cover(self) -> None:
        self.add_page()
        self.set_fill_color(*DARK)
        self.rect(0, 0, 210, 297, "F")
        self.set_y(70)
        self.set_font("DejaVu", "B", 36)
        self.set_text_color(*ORANGE)
        self.cell(0, 16, "Tata.Manager", align="C", new_x="LMARGIN", new_y="NEXT")
        self.ln(4)
        self.set_font("DejaVu", "B", 20)
        self.set_text_color(255, 255, 255)
        self.cell(0, 10, "Manual de uso", align="C", new_x="LMARGIN", new_y="NEXT")
        self.ln(8)
        self.set_font("DejaVu", "", 12)
        self.set_text_color(200, 205, 210)
        self.multi_cell(
            0,
            7,
            "Guía detallada para PC (Windows) y celular (Android).\n"
            "Ventas, remitos, stock, usuarios, sincronización y más.",
            align="C",
        )
        self.ln(16)
        self.set_font("DejaVu", "", 11)
        self.set_text_color(*ORANGE)
        self.cell(0, 8, "Versión de la app: 1.2.3 (26)", align="C", new_x="LMARGIN", new_y="NEXT")
        self.set_text_color(160, 165, 170)
        self.cell(0, 8, "Julio 2026", align="C", new_x="LMARGIN", new_y="NEXT")
        self.set_y(250)
        self.set_font("DejaVu", "", 9)
        self.multi_cell(
            0,
            5,
            "Las capturas son ilustrativas de las pantallas principales.\n"
            "La interfaz real puede variar según el dispositivo y el menú personalizado.",
            align="C",
        )

    def h1(self, text: str) -> None:
        self.set_x(self.l_margin)
        self.ln(2)
        self.set_font("DejaVu", "B", 16)
        self.set_text_color(*ORANGE)
        self.multi_cell(self.epw, 9, text)
        self.ln(1)

    def h2(self, text: str) -> None:
        self.set_x(self.l_margin)
        self.ln(2)
        self.set_font("DejaVu", "B", 12)
        self.set_text_color(*DARK)
        self.multi_cell(self.epw, 7, text)
        self.ln(0.5)

    def p(self, text: str) -> None:
        self.set_x(self.l_margin)
        self.set_font("DejaVu", "", 10)
        self.set_text_color(30, 35, 40)
        self.multi_cell(self.epw, 5.5, text)
        self.ln(1.5)

    def bullets(self, items: list[str]) -> None:
        self.set_font("DejaVu", "", 10)
        self.set_text_color(30, 35, 40)
        for item in items:
            self.set_x(self.l_margin)
            self.multi_cell(self.epw, 5.5, f"-  {item}")
        self.ln(1.5)

    def tip(self, text: str) -> None:
        self.set_x(self.l_margin)
        self.set_font("DejaVu", "B", 9)
        self.set_text_color(*ORANGE)
        self.multi_cell(self.epw, 5, "Consejo")
        self.set_x(self.l_margin)
        self.set_font("DejaVu", "", 9)
        self.set_text_color(40, 45, 50)
        self.multi_cell(self.epw, 5, text)
        self.ln(2)

    def shot(self, path: Path, caption: str, height: float = 95) -> None:
        if not path.exists():
            self.p(f"[Imagen no disponible: {path.name}]")
            return
        self.ln(1)
        img_w = 52
        if self.get_y() > 175:
            self.add_page()
        x = (210 - img_w) / 2
        self.image(str(path), x=x, w=img_w)
        self.set_x(self.l_margin)
        self.ln(2)
        self.set_font("DejaVu", "", 8)
        self.set_text_color(*GRAY)
        self.multi_cell(self.epw, 4.5, caption, align="C")
        self.ln(2)
        self.set_x(self.l_margin)


def build() -> Path:
    tmp = Path("/tmp/manual_shots")
    shots = {
        "login": prep_phone(ASSETS / "manual_login.png", tmp / "login.png"),
        "inicio": prep_phone(ASSETS / "manual_inicio.png", tmp / "inicio.png"),
        "remitos": prep_phone(ASSETS / "manual_remitos.png", tmp / "remitos.png"),
        "usuarios": prep_phone(ASSETS / "manual_usuarios.png", tmp / "usuarios.png"),
        "pedidos": prep_phone(ASSETS / "manual_pedidos.png", tmp / "pedidos.png"),
        "chat": prep_phone(ASSETS / "manual_chat.png", tmp / "chat.png"),
    }

    pdf = ManualPDF()
    pdf.cover()

    # TOC
    pdf.add_page()
    pdf.h1("Índice")
    toc = [
        "1. Qué es Tata.Manager",
        "2. Instalación (Android y Windows)",
        "3. Iniciar sesión y pedir acceso",
        "4. Alta de usuarios (administrador)",
        "5. Pantalla de inicio y sincronización",
        "6. Productos, stock y compras",
        "7. Remitos y venta rápida",
        "8. Clientes y cuenta corriente",
        "9. Planilla de pedidos",
        "10. Comunicaciones (chat y fotos)",
        "11. Cierre de caja y reportes",
        "12. Configuración, respaldo y consejos",
        "13. Problemas frecuentes",
    ]
    pdf.bullets(toc)

    # 1
    pdf.add_page()
    pdf.h1("1. Qué es Tata.Manager")
    pdf.p(
        "Tata.Manager es el sistema de gestión del negocio (stock, ventas, remitos, "
        "clientes, pedidos a proveedores y comunicación interna). Funciona en "
        "celular Android y en PC Windows."
    )
    pdf.p(
        "Trabaja offline-first: podés operar sin internet. Cuando hay conexión, "
        "los cambios se sincronizan entre dispositivos del mismo negocio (tenant)."
    )
    pdf.h2("Roles")
    pdf.bullets(
        [
            "Administrador: usuarios, permisos, configuración, respaldos, altas.",
            "Encargado / Empleado: operación diaria según los permisos que les des.",
        ]
    )

    # 2
    pdf.h1("2. Instalación")
    pdf.h2("Android (APK)")
    pdf.bullets(
        [
            "Instalá el APK de la versión actual (ej. 1.2.3).",
            "Si el celular lo pide, permití instalación de orígenes desconocidos.",
            "Al abrir, en el login debe verse Tata.Manager v1.2.3 (26) o superior.",
        ]
    )
    pdf.h2("Windows (EXE)")
    pdf.bullets(
        [
            "No copies solo el .exe: usá la carpeta completa Instalador_Windows.",
            "Ejecutá sistema_nuevo.exe desde esa carpeta (o el acceso directo).",
            "Para actualizar: reemplazá la carpeta con el build nuevo y volvé a abrir.",
        ]
    )
    pdf.tip(
        "Android y PC deben usar la misma versión para evitar diferencias "
        "(por ejemplo eliminar remitos o ver fotos en el chat)."
    )

    # 3
    pdf.add_page()
    pdf.h1("3. Iniciar sesión y pedir acceso")
    pdf.shot(
        shots["login"],
        "Pantalla de login: Continuar con Google o Continuar con correo.",
    )
    pdf.h2("Si ya tenés usuario")
    pdf.bullets(
        [
            "Admin clásico: usuario admin + contraseña (en PC o celular).",
            "O Continuar con Google / correo si ya te dieron el alta.",
        ]
    )
    pdf.h2("Si es la primera vez (empleado o nuevo)")
    pdf.bullets(
        [
            "Tocá Continuar con Google o Continuar con correo.",
            "Se envía una solicitud: no entras todavía.",
            "El administrador te da el alta en Menú → Usuarios.",
            "Cuando te aprueben, volvé a entrar con el mismo método.",
        ]
    )
    pdf.tip(
        "No hace falta que el admin te arme usuario y clave de antemano. "
        "Ellos piden acceso; vos aprobás."
    )

    # 4
    pdf.add_page()
    pdf.h1("4. Alta de usuarios (solo administrador)")
    pdf.shot(
        shots["usuarios"],
        "Usuarios: badge PENDIENTE ALTA y botón para aprobar.",
    )
    pdf.h2("Pasos")
    pdf.bullets(
        [
            "Entrá como administrador.",
            "Menú → Usuarios (en celular: menú hamburguesa).",
            "Si hay solicitudes, al iniciar puede aparecer un aviso Ir a Usuarios.",
            "Usá el filtro Solo pendientes.",
            "Tocá el ícono de persona con tilde → elegí rol → Aprobar.",
            "La persona vuelve a entrar con Google o correo.",
        ]
    )
    pdf.h2("Rechazar")
    pdf.p("Eliminá la solicitud pendiente desde Usuarios (papelera), con confirmación.")
    pdf.h2("¿Admin desde Android o PC?")
    pdf.p(
        "Podés administrar desde ambos. Para altas y reportes la PC es más cómoda; "
        "para el día a día el celular alcanza."
    )

    # 5
    pdf.add_page()
    pdf.h1("5. Pantalla de inicio y sincronización")
    pdf.shot(
        shots["inicio"],
        "Inicio: resumen del día, alertas y estado de sincronización.",
    )
    pdf.h2("Al empezar el día")
    pdf.bullets(
        [
            "Iniciá sesión.",
            "Revisá Inicio (alertas de stock, cuentas, accesos rápidos).",
            "Mirá el indicador de sync: Sincronizado / Pendiente / Sin conexión / Error.",
        ]
    )
    pdf.h2("Sincronización PC ↔ celular")
    pdf.bullets(
        [
            "Con internet: los cambios se comparten solos.",
            "Sin internet: seguí trabajando; se guarda en el equipo.",
            "Al volver la red: se envían solos.",
            "Tocá el indicador para ver historial; mantené pulsado para reintentar si hay error.",
        ]
    )

    # 6
    pdf.h1("6. Productos, stock y compras")
    pdf.h2("Productos")
    pdf.bullets(
        [
            "Alta/edición: código, descripción, stock, costo, precios, fotos.",
            "Las fotos se suben a la nube para verse en otros dispositivos.",
            "Importación masiva: Centro de importaciones → Importar productos (Excel).",
        ]
    )
    pdf.h2("Stock")
    pdf.bullets(
        [
            "Consultá movimientos y alertas de stock bajo.",
            "Los remitos y ventas descuentan; las compras suman.",
        ]
    )
    pdf.h2("Compras")
    pdf.p(
        "Registrá compras a proveedor: sube stock y puede actualizar costo. "
        "Si te equivocás, usá Anular (revierte stock)."
    )

    # 7
    pdf.add_page()
    pdf.h1("7. Remitos y venta rápida")
    pdf.shot(
        shots["remitos"],
        "Lista de remitos: estados, cobros, compartir PDF y eliminar.",
    )
    pdf.h2("Crear un remito")
    pdf.bullets(
        [
            "Remitos → nuevo (o Venta rápida).",
            "Elegí cliente y productos/cantidades.",
            "Confirmá: baja stock y genera el documento.",
            "Podés imprimir, compartir PDF o térmica.",
        ]
    )
    pdf.h2("Si te equivocaste")
    pdf.bullets(
        [
            "Anular: revierte stock y deja el remito marcado como anulado.",
            "Eliminar (papelera): revierte stock, borra cobros asociados y lo saca de la lista.",
        ]
    )
    pdf.tip(
        "Preferí Eliminar solo cuando el remito no debería existir. "
        "Anular sirve para dejar constancia."
    )
    pdf.h2("Cobros")
    pdf.p(
        "Desde el menú del remito: Marcar como cobrado o Pago parcial. "
        "También podés cobrar desde Cuenta corriente del cliente."
    )

    # 8
    pdf.h1("8. Clientes y cuenta corriente")
    pdf.bullets(
        [
            "Clientes: alta, búsqueda, historial.",
            "Cuenta corriente: deudas de ventas/remitos y registro de pagos.",
            "Clientes deudores: vista rápida de quién debe.",
        ]
    )

    # 9
    pdf.add_page()
    pdf.h1("9. Planilla de pedidos")
    pdf.shot(
        shots["pedidos"],
        "Planilla por proveedor con exportar PDF y Excel visibles.",
    )
    pdf.bullets(
        [
            "Pedidos → planilla agrupada por proveedor (JK, Cuero Sur, etc.).",
            "Creá o editá el borrador del día.",
            "Exportá PDF o Excel: ícono compartir arriba, por proveedor o por pedido.",
            "En Windows se abre Guardar como…; en Android se comparte.",
            "Pedido sugerido: propone cantidades según stock/ventas.",
        ]
    )

    # 10
    pdf.add_page()
    pdf.h1("10. Comunicaciones (chat y fotos)")
    pdf.shot(
        shots["chat"],
        "Chat interno: textos, fotos y archivos entre el equipo.",
    )
    pdf.bullets(
        [
            "Comunicaciones: charlas 1 a 1 o de grupo interno.",
            "Podés enviar texto, cámara, galería/archivos y compartir remitos/productos.",
            "Las fotos se suben a la nube: el otro celular/PC puede verlas.",
            "Si la subida falla, la app avisa (no manda un archivo ilegible).",
            "Tocá una imagen para ampliarla; tocá un archivo para abrirlo/compartirlo.",
        ]
    )
    pdf.tip(
        "Fotos enviadas con versiones viejas pueden verse rotas en el otro "
        "dispositivo. Reenviálas con la versión 1.2.3 o superior."
    )

    # 11
    pdf.h1("11. Cierre de caja y reportes")
    pdf.h2("Cierre de caja")
    pdf.bullets(
        [
            "Resumen del día: ventas, cobros, efectivo, ganancia.",
            "Elegí el día con el calendario.",
            "Si algo falla, verás el error y un botón Reintentar (ya no pantalla negra).",
        ]
    )
    pdf.h2("Reportes")
    pdf.p(
        "Exportá listados a PDF, CSV o Excel (productos, clientes, deudores, "
        "cobros, remitos, inventario, etc.). En PC usá Guardar como…; en Android, compartir."
    )

    # 12
    pdf.add_page()
    pdf.h1("12. Configuración, respaldo y consejos")
    pdf.h2("Configuración")
    pdf.bullets(
        [
            "Datos del negocio, impresión, preferencias.",
            "Personalizar menú: qué módulos se ven en PC/celular.",
            "BORRAR TODO (solo admin): deja el sistema virgen — usalo con cuidado.",
        ]
    )
    pdf.h2("Respaldo")
    pdf.p(
        "De vez en cuando exportá un respaldo. Guardalo fuera del equipo "
        "(pendrive/nube). Sirve ante cambio de PC o fallo."
    )
    pdf.h2("Consejos rápidos")
    pdf.bullets(
        [
            "Mantené la misma versión en todos los dispositivos.",
            "Internet estable ayuda a la sync, pero podés trabajar offline.",
            "Admin en PC para altas/reportes; celular para operación.",
            "Revisá Archivo PDF para reenviar remitos/facturas guardados.",
        ]
    )

    # 13
    pdf.h1("13. Problemas frecuentes")
    pdf.h2("No puedo entrar con Google")
    pdf.bullets(
        [
            "Si es la primera vez: es normal, quedó pendiente de alta.",
            "Pedile al admin Menú → Usuarios → aprobar.",
            "Confirmá que en Firebase estén activos Google y Correo/contraseña.",
        ]
    )
    pdf.h2("No veo Usuarios en el menú")
    pdf.p("Solo el rol administrador lo ve. En celular puede estar dentro del menú lateral.")
    pdf.h2("Las fotos del chat no se ven")
    pdf.p(
        "Actualizá a 1.2.3+, con internet, y reenviá la foto. "
        "Las viejas pueden haber quedado solo en el celular que las mandó."
    )
    pdf.h2("No sincroniza entre PC y celular")
    pdf.bullets(
        [
            "Misma cuenta/negocio e internet en ambos.",
            "Revisá el indicador de sync; reintentá si dice Error.",
        ]
    )
    pdf.h2("Cierre de caja en negro")
    pdf.p("En 1.2.2+ ya no debería pasar. Actualizá y usá Reintentar si aparece un error.")

    pdf.ln(8)
    pdf.set_x(pdf.l_margin)
    pdf.set_font("DejaVu", "B", 11)
    pdf.set_text_color(*ORANGE)
    pdf.multi_cell(pdf.epw, 6, "Fin del manual — Tata.Manager v1.2.3")
    pdf.set_x(pdf.l_margin)
    pdf.set_font("DejaVu", "", 9)
    pdf.set_text_color(*GRAY)
    pdf.multi_cell(
        pdf.epw,
        5,
        "Para soporte interno: consultá también el Manual dentro de la app "
        "(menú Manual de usuario) y docs/GOOGLE_LOGIN.md para el acceso con Google.",
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(OUT))
    DOCS_OUT.parent.mkdir(parents=True, exist_ok=True)
    pdf.output(str(DOCS_OUT))
    return OUT


if __name__ == "__main__":
    path = build()
    print(f"OK {path} ({path.stat().st_size} bytes)")
    print(f"OK {DOCS_OUT}")
