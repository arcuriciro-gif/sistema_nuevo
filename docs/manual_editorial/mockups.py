"""Mockups realistas de la UI Tata.Manager — coherentes entre sí."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

from design import ASSETS

ORANGE = (245, 124, 0)
ORANGE_D = (230, 81, 0)
BLACK = (11, 11, 11)
SIDEBAR = (0, 0, 0)
INK = (26, 26, 26)
MUTED = (107, 114, 128)
LINE = (229, 231, 235)
SOFT = (246, 247, 249)
WHITE = (255, 255, 255)
GREEN = (22, 163, 74)
RED = (220, 38, 38)
BLUE = (37, 99, 235)


def _font(size: int, weight: str = "reg"):
    mapping = {
        "reg": "Outfit-400.ttf",
        "med": "Outfit-500.ttf",
        "semi": "Outfit-600.ttf",
        "bold": "Outfit-700.ttf",
        "black": "Outfit-800.ttf",
    }
    path = Path(__file__).parent / "fonts" / mapping.get(weight, mapping["reg"])
    try:
        return ImageFont.truetype(str(path), size)
    except Exception:
        return ImageFont.truetype(
            "/usr/share/fonts/truetype/macos/Inter-Regular.ttf", size
        )


def _rrect(draw, xy, r, fill=None, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=r, fill=fill, outline=outline, width=width)


def _shadow(img: Image.Image, box, radius=18, blur=12, opacity=50):
    """Sombra suave bajo un rectángulo."""
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(
        (x0 + 2, y0 + 4, x1 + 2, y1 + 6), radius=radius, fill=(0, 0, 0, opacity)
    )
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return Image.alpha_composite(img.convert("RGBA"), layer)


def _logo_mark(draw, x, y, size=28):
    _rrect(draw, (x, y, x + size, y + size), size * 0.28, fill=ORANGE)
    f = _font(int(size * 0.42), "black")
    draw.text((x + size * 0.22, y + size * 0.22), "T", font=f, fill=WHITE)


def _sidebar(draw, h, selected: str, w=220):
    draw.rectangle((0, 0, w, h), fill=SIDEBAR)
    _logo_mark(draw, 22, 22, 34)
    f_brand = _font(15, "bold")
    f_sub = _font(10, "med")
    draw.text((66, 26), "Tata.Manager", font=f_brand, fill=WHITE)
    draw.text((66, 46), "EL TATA · Comercio", font=f_sub, fill=(156, 163, 175))

    items = [
        ("Inicio", "home"),
        ("Dashboard", "dash"),
        ("Productos", "prod"),
        ("Clientes", "cli"),
        ("Ventas", "ven"),
        ("Remitos", "rem"),
        ("Compras", "com"),
        ("Stock", "stk"),
        ("Proveedores", "prv"),
        ("Reportes", "rep"),
        ("Archivo PDF", "pdf"),
        ("Usuarios", "usr"),
        ("Configuración", "cfg"),
        ("Chat", "chat"),
    ]
    y = 90
    f_item = _font(12, "med")
    for label, key in items:
        sel = key == selected
        if sel:
            _rrect(draw, (12, y - 6, w - 12, y + 26), 10, fill=ORANGE)
        color = WHITE if sel else (209, 213, 219)
        # ícono punto
        draw.ellipse((24, y + 4, 34, y + 14), fill=color if sel else (107, 114, 128))
        draw.text((44, y), label, font=f_item, fill=color)
        y += 36

    # usuario abajo
    draw.rectangle((0, h - 70, w, h), fill=(20, 20, 20))
    draw.ellipse((20, h - 52, 52, h - 20), fill=ORANGE)
    draw.text((28, h - 46), "A", font=_font(14, "bold"), fill=WHITE)
    draw.text((62, h - 50), "Admin", font=_font(12, "semi"), fill=WHITE)
    draw.text((62, h - 32), "En línea · Firebase", font=_font(9, "med"), fill=(107, 114, 128))
    return w


def _topbar(draw, x, y, w, title: str, breadcrumb: str = ""):
    draw.rectangle((x, y, x + w, y + 64), fill=WHITE)
    draw.line((x, y + 64, x + w, y + 64), fill=LINE, width=1)
    draw.text((x + 28, y + 18), title, font=_font(20, "bold"), fill=INK)
    if breadcrumb:
        draw.text((x + 28, y + 42), breadcrumb, font=_font(10, "med"), fill=MUTED)
    # search
    sx = x + w - 320
    _rrect(draw, (sx, y + 16, sx + 200, y + 48), 10, fill=SOFT, outline=LINE)
    draw.text((sx + 14, y + 24), "Buscar…", font=_font(11, "med"), fill=MUTED)
    # bell
    draw.ellipse((x + w - 96, y + 18, x + w - 64, y + 50), fill=SOFT)
    draw.ellipse((x + w - 86, y + 28, x + w - 74, y + 42), outline=ORANGE, width=2)
    draw.rectangle((x + w - 82, y + 24, x + w - 78, y + 28), fill=ORANGE)
    # refresh circle
    draw.ellipse((x + w - 52, y + 18, x + w - 20, y + 50), outline=ORANGE, width=2)
    draw.polygon(
        [(x + w - 24, y + 22), (x + w - 18, y + 30), (x + w - 28, y + 30)],
        fill=ORANGE,
    )


def _card(draw, box, title, value, subtitle, accent=ORANGE):
    x0, y0, x1, y1 = box
    _rrect(draw, box, 14, fill=WHITE, outline=LINE)
    draw.rectangle((x0, y0, x0 + 5, y1), fill=accent)
    draw.text((x0 + 18, y0 + 14), title, font=_font(11, "med"), fill=MUTED)
    draw.text((x0 + 18, y0 + 36), value, font=_font(22, "bold"), fill=INK)
    draw.text((x0 + 18, y0 + 68), subtitle, font=_font(10, "med"), fill=MUTED)


def _table(draw, x, y, w, headers, rows, col_w=None):
    h = 40
    _rrect(draw, (x, y, x + w, y + h), 10, fill=SOFT)
    # flat bottom of header
    draw.rectangle((x, y + 20, x + w, y + h), fill=SOFT)
    if col_w is None:
        col_w = [w // len(headers)] * len(headers)
    cx = x + 16
    for i, htxt in enumerate(headers):
        draw.text((cx, y + 12), htxt, font=_font(10, "semi"), fill=MUTED)
        cx += col_w[i]
    yy = y + h
    for ri, row in enumerate(rows):
        if ri % 2 == 0:
            draw.rectangle((x, yy, x + w, yy + 38), fill=WHITE)
        else:
            draw.rectangle((x, yy, x + w, yy + 38), fill=(252, 252, 253))
        draw.line((x, yy + 38, x + w, yy + 38), fill=LINE)
        cx = x + 16
        for i, cell in enumerate(row):
            color = INK
            if isinstance(cell, tuple):
                cell, color = cell
            draw.text((cx, yy + 10), str(cell), font=_font(11, "med"), fill=color)
            cx += col_w[i]
        yy += 38
    return yy


def draw_dashboard() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "dash")
    _topbar(d, sw, 0, W - sw, "Dashboard", "Resumen operativo · Hoy")
    cards = [
        (sw + 28, 88, "Productos", "1.248", "Catálogo activo", ORANGE),
        (sw + 290, 88, "Sin stock", "12", "Requieren reposición", RED),
        (sw + 552, 88, "Ventas del mes", "$ 4.8M", "+12% vs mes ant.", GREEN),
        (sw + 814, 88, "Por cobrar", "$ 820K", "27 clientes", BLUE),
    ]
    for x, y, t, v, s, a in cards:
        _card(d, (x, y, x + 240, y + 100), t, v, s, a)

    # chart card
    _rrect(d, (sw + 28, 210, W - 28, 480), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 228), "Ventas mensuales", font=_font(14, "semi"), fill=INK)
    # bars
    bars = [40, 55, 48, 70, 62, 85, 78, 90, 88, 95, 100, 92]
    bx = sw + 60
    for i, b in enumerate(bars):
        bh = int(b * 1.8)
        _rrect(
            d,
            (bx, 450 - bh, bx + 42, 450),
            8,
            fill=ORANGE if i == 11 else (255, 204, 153),
        )
        d.text((bx + 8, 458), f"{i+1:02d}", font=_font(9, "med"), fill=MUTED)
        bx += 70

    # top products
    _rrect(d, (sw + 28, 500, sw + 520, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 518), "Top productos", font=_font(14, "semi"), fill=INK)
    _table(
        d,
        sw + 48,
        550,
        440,
        ["Producto", "Vendidos", "Monto"],
        [
            ["Remera básica", "184", "$ 920K"],
            ["Jean slim", "96", "$ 1.1M"],
            ["Campera soft", "54", "$ 810K"],
            ["Zapatilla city", "41", "$ 615K"],
        ],
        [180, 120, 140],
    )

    _rrect(d, (sw + 548, 500, W - 28, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 568, 518), "Alertas", font=_font(14, "semi"), fill=INK)
    alerts = [
        ("Sin stock", "12 productos", RED),
        ("Stock bajo", "28 productos", ORANGE),
        ("Deudores", "$ 820K", BLUE),
    ]
    ay = 560
    for t, s, c in alerts:
        _rrect(d, (sw + 568, ay, W - 48, ay + 56), 12, fill=SOFT)
        d.ellipse((sw + 584, ay + 18, sw + 604, ay + 38), fill=c)
        d.text((sw + 620, ay + 10), t, font=_font(12, "semi"), fill=INK)
        d.text((sw + 620, ay + 30), s, font=_font(11, "med"), fill=MUTED)
        ay += 68

    path = ASSETS / "ui_dashboard.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_productos() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "prod")
    _topbar(d, sw, 0, W - sw, "Productos", "Catálogo · Listas de precio")
    # toolbar
    _rrect(d, (sw + 28, 88, W - 28, 140), 12, fill=WHITE, outline=LINE)
    _rrect(d, (sw + 44, 100, sw + 360, 128), 8, fill=SOFT, outline=LINE)
    d.text((sw + 58, 106), "Buscar código, nombre, marca…", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (sw + 380, 100, sw + 500, 128), 8, fill=SOFT, outline=LINE)
    d.text((sw + 398, 106), "Marca ▾", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (W - 180, 100, W - 44, 128), 8, fill=ORANGE)
    d.text((W - 150, 106), "+ Nuevo", font=_font(12, "semi"), fill=WHITE)

    rows = [
        ["RM-001", "Remera algodón blanca", "Nike", "48", "$ 8.500", ("Activo", GREEN)],
        ["JN-214", "Jean slim azul", "Levi's", "22", "$ 24.900", ("Activo", GREEN)],
        ["CP-088", "Campera softshell", "Columbia", "0", "$ 68.000", ("Sin stock", RED)],
        ["ZP-331", "Zapatilla city run", "Adidas", "15", "$ 55.000", ("Activo", GREEN)],
        ["CJ-102", "Camisa jean", "Wrangler", "9", "$ 19.500", ("Bajo", ORANGE)],
        ["GT-441", "Gorra trucker", "New Era", "61", "$ 7.200", ("Activo", GREEN)],
        ["MD-019", "Medias pack x3", "Nike", "120", "$ 4.100", ("Activo", GREEN)],
        ["BL-077", "Buzo canguro", "Puma", "3", "$ 32.000", ("Bajo", ORANGE)],
    ]
    _table(
        d,
        sw + 28,
        160,
        W - sw - 56,
        ["Código", "Descripción", "Marca", "Stock", "Precio", "Estado"],
        rows,
        [110, 280, 140, 90, 120, 120],
    )
    path = ASSETS / "ui_productos.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_clientes() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cli")
    _topbar(d, sw, 0, W - sw, "Clientes", "Agenda comercial")
    _rrect(d, (W - 180, 88, W - 44, 116), 8, fill=ORANGE)
    d.text((W - 150, 94), "+ Nuevo", font=_font(12, "semi"), fill=WHITE)

    # client cards grid
    clients = [
        ("Comercial Norte SA", "CUIT 30-71234567-8", "$ 245.000", "Debe"),
        ("Distribuidora Sur", "CUIT 30-69871234-1", "$ 0", "Al día"),
        ("MOSTRADOR", "Consumidor final", "$ 0", "Al día"),
        ("Textil Andina", "CUIT 33-55443322-0", "$ 89.400", "Debe"),
        ("Boutique Luna", "Cel 11 5555-2211", "$ 12.300", "Debe"),
        ("Mayorista Centro", "CUIT 30-11223344-5", "$ 0", "Al día"),
    ]
    x0, y0 = sw + 28, 140
    for i, (name, meta, saldo, estado) in enumerate(clients):
        col, row = i % 3, i // 3
        x = x0 + col * 330
        y = y0 + row * 170
        _rrect(d, (x, y, x + 310, y + 150), 16, fill=WHITE, outline=LINE)
        d.ellipse((x + 20, y + 24, x + 68, y + 72), fill=(255, 243, 224))
        d.text((x + 34, y + 34), name[0], font=_font(16, "bold"), fill=ORANGE)
        d.text((x + 84, y + 28), name, font=_font(13, "semi"), fill=INK)
        d.text((x + 84, y + 50), meta, font=_font(10, "med"), fill=MUTED)
        color = RED if estado == "Debe" else GREEN
        d.text((x + 20, y + 96), "Saldo", font=_font(10, "med"), fill=MUTED)
        d.text((x + 20, y + 114), saldo, font=_font(16, "bold"), fill=color)
        _rrect(d, (x + 200, y + 108, x + 290, y + 134), 8, fill=(254, 242, 242) if estado == "Debe" else (236, 253, 245))
        d.text((x + 218, y + 114), estado, font=_font(11, "semi"), fill=color)

    path = ASSETS / "ui_clientes.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_ventas() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "ven")
    _topbar(d, sw, 0, W - sw, "Venta rápida", "Cliente MOSTRADOR · Lista minorista")

    # left product picker
    _rrect(d, (sw + 28, 88, sw + 520, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 108), "Agregar productos", font=_font(14, "semi"), fill=INK)
    _rrect(d, (sw + 48, 140, sw + 480, 172), 8, fill=SOFT, outline=LINE)
    d.text((sw + 62, 148), "Escanear o buscar…", font=_font(11, "med"), fill=MUTED)
    items = [
        ("RM-001 Remera blanca", "$ 8.500"),
        ("JN-214 Jean slim", "$ 24.900"),
        ("GT-441 Gorra trucker", "$ 7.200"),
        ("MD-019 Medias x3", "$ 4.100"),
    ]
    iy = 196
    for name, price in items:
        _rrect(d, (sw + 48, iy, sw + 480, iy + 56), 10, fill=SOFT)
        d.text((sw + 68, iy + 18), name, font=_font(12, "med"), fill=INK)
        d.text((sw + 380, iy + 18), price, font=_font(12, "semi"), fill=ORANGE)
        iy += 68

    # cart
    _rrect(d, (sw + 548, 88, W - 28, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 568, 108), "Carrito", font=_font(14, "semi"), fill=INK)
    cart = [
        ("Remera blanca x2", "$ 17.000"),
        ("Jean slim x1", "$ 24.900"),
        ("Gorra trucker x1", "$ 7.200"),
    ]
    cy = 150
    for name, price in cart:
        d.text((sw + 568, cy), name, font=_font(12, "med"), fill=INK)
        d.text((W - 140, cy), price, font=_font(12, "semi"), fill=INK)
        cy += 36
    d.line((sw + 568, cy + 8, W - 48, cy + 8), fill=LINE, width=1)
    d.text((sw + 568, cy + 24), "Total", font=_font(14, "semi"), fill=MUTED)
    d.text((W - 180, cy + 18), "$ 49.100", font=_font(22, "bold"), fill=INK)
    _rrect(d, (sw + 568, H - 120, W - 48, H - 70), 12, fill=ORANGE)
    d.text((sw + 700, H - 106), "Confirmar venta", font=_font(14, "semi"), fill=WHITE)
    d.text((sw + 568, H - 56), "Genera remito + PDF + descuenta stock", font=_font(10, "med"), fill=MUTED)

    path = ASSETS / "ui_ventas.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_remitos() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "rem")
    _topbar(d, sw, 0, W - sw, "Remitos", "Documentos de entrega")
    _rrect(d, (W - 200, 88, W - 44, 116), 8, fill=ORANGE)
    d.text((W - 175, 94), "+ Nuevo remito", font=_font(11, "semi"), fill=WHITE)
    rows = [
        ["R-1042", "14/07/2026", "Comercial Norte", "$ 245.000", ("Pendiente", ORANGE)],
        ["R-1041", "14/07/2026", "MOSTRADOR", "$ 49.100", ("Cobrado", GREEN)],
        ["R-1040", "13/07/2026", "Boutique Luna", "$ 12.300", ("Pendiente", ORANGE)],
        ["R-1039", "13/07/2026", "Distribuidora Sur", "$ 188.000", ("Cobrado", GREEN)],
        ["R-1038", "12/07/2026", "Textil Andina", "$ 89.400", ("Parcial", BLUE)],
        ["R-1037", "12/07/2026", "Mayorista Centro", "$ 320.000", ("Cobrado", GREEN)],
    ]
    _table(
        d,
        sw + 28,
        140,
        W - sw - 56,
        ["Nº", "Fecha", "Cliente", "Total", "Estado"],
        rows,
        [120, 140, 280, 160, 160],
    )
    path = ASSETS / "ui_remitos.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_compras() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "com")
    _topbar(d, sw, 0, W - sw, "Compras", "Ingresos de mercadería")
    _rrect(d, (sw + 28, 88, W - 28, 200), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 108), "Nueva compra", font=_font(14, "semi"), fill=INK)
    fields = [("Proveedor", "Textil Andina SRL"), ("Fecha", "14/07/2026"), ("Nº factura", "A-0001-458")]
    fx = sw + 48
    for label, val in fields:
        d.text((fx, 145), label, font=_font(10, "med"), fill=MUTED)
        _rrect(d, (fx, 162, fx + 220, 190), 8, fill=SOFT, outline=LINE)
        d.text((fx + 12, 168), val, font=_font(11, "med"), fill=INK)
        fx += 250
    rows = [
        ["RM-001", "Remera algodón", "40", "$ 3.200", "$ 128.000"],
        ["JN-214", "Jean slim", "20", "$ 11.500", "$ 230.000"],
        ["CP-088", "Campera soft", "10", "$ 28.000", "$ 280.000"],
    ]
    _table(
        d,
        sw + 28,
        220,
        W - sw - 56,
        ["Código", "Producto", "Cant.", "Costo", "Subtotal"],
        rows,
        [120, 300, 100, 160, 160],
    )
    _rrect(d, (W - 260, H - 90, W - 44, H - 48), 10, fill=ORANGE)
    d.text((W - 230, H - 78), "Registrar compra", font=_font(12, "semi"), fill=WHITE)
    path = ASSETS / "ui_compras.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_stock() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "stk")
    _topbar(d, sw, 0, W - sw, "Stock", "Movimientos · Alertas")
    # tabs
    for i, (t, sel) in enumerate([("Movimientos", True), ("Alertas", False), ("Kardex", False)]):
        x = sw + 28 + i * 140
        if sel:
            _rrect(d, (x, 88, x + 120, 118), 8, fill=ORANGE)
            d.text((x + 18, 96), t, font=_font(11, "semi"), fill=WHITE)
        else:
            _rrect(d, (x, 88, x + 120, 118), 8, fill=WHITE, outline=LINE)
            d.text((x + 18, 96), t, font=_font(11, "med"), fill=MUTED)
    rows = [
        ["14/07 10:22", "Entrada", "Compra #458", "RM-001", "+40", "48"],
        ["14/07 11:05", "Salida", "Remito R-1042", "JN-214", "-2", "22"],
        ["14/07 11:05", "Salida", "Remito R-1042", "RM-001", "-6", "42"],
        ["13/07 16:40", "Ajuste", "Inventario", "CP-088", "-1", "0"],
        ["13/07 09:12", "Entrada", "Compra #457", "ZP-331", "+15", "15"],
    ]
    _table(
        d,
        sw + 28,
        140,
        W - sw - 56,
        ["Fecha", "Tipo", "Origen", "Producto", "Cant.", "Saldo"],
        rows,
        [150, 110, 200, 180, 100, 100],
    )
    path = ASSETS / "ui_stock.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_usuarios() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "usr")
    _topbar(d, sw, 0, W - sw, "Usuarios", "Accesos y roles")
    users = [
        ("Ana Pérez", "admin", "Administrador", "En línea"),
        ("Luis Gómez", "lgomez", "Encargado", "En línea"),
        ("María Ríos", "mrios", "Empleado", "Ausente"),
        ("Carlos Díaz", "cdiaz", "Empleado", "En línea"),
    ]
    y = 100
    for name, user, rol, st in users:
        _rrect(d, (sw + 28, y, W - 28, y + 88), 14, fill=WHITE, outline=LINE)
        d.ellipse((sw + 48, y + 20, sw + 96, y + 68), fill=(255, 243, 224))
        d.text((sw + 62, y + 32), name[0], font=_font(16, "bold"), fill=ORANGE)
        d.text((sw + 116, y + 22), name, font=_font(14, "semi"), fill=INK)
        d.text((sw + 116, y + 46), f"@{user} · {rol}", font=_font(11, "med"), fill=MUTED)
        color = GREEN if st == "En línea" else MUTED
        _rrect(d, (W - 160, y + 30, W - 48, y + 58), 8, fill=SOFT)
        d.ellipse((W - 148, y + 40, W - 136, y + 52), fill=color)
        d.text((W - 128, y + 36), st, font=_font(10, "semi"), fill=INK)
        y += 104
    path = ASSETS / "ui_usuarios.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_permisos() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "usr")
    _topbar(d, sw, 0, W - sw, "Permisos", "Matriz por rol")
    mods = ["Productos", "Ventas", "Clientes", "Compras", "Stock", "Usuarios", "Config"]
    roles = ["Ver", "Crear", "Editar", "Eliminar"]
    _rrect(d, (sw + 28, 100, W - 28, H - 40), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 120), "Rol: Encargado", font=_font(14, "semi"), fill=INK)
    # header
    d.text((sw + 48, 160), "Módulo", font=_font(11, "semi"), fill=MUTED)
    for i, r in enumerate(roles):
        d.text((sw + 280 + i * 140, 160), r, font=_font(11, "semi"), fill=MUTED)
    y = 190
    pattern = [
        [1, 1, 1, 0],
        [1, 1, 1, 0],
        [1, 1, 1, 0],
        [1, 1, 0, 0],
        [1, 1, 1, 0],
        [1, 0, 0, 0],
        [1, 0, 0, 0],
    ]
    for mi, mod in enumerate(mods):
        d.text((sw + 48, y + 8), mod, font=_font(12, "med"), fill=INK)
        for ri, ok in enumerate(pattern[mi]):
            x = sw + 290 + ri * 140
            if ok:
                _rrect(d, (x, y, x + 28, y + 28), 6, fill=ORANGE)
                d.line((x + 7, y + 14, x + 12, y + 20), fill=WHITE, width=3)
                d.line((x + 12, y + 20, x + 21, y + 8), fill=WHITE, width=3)
            else:
                _rrect(d, (x, y, x + 28, y + 28), 6, fill=SOFT, outline=LINE)
        y += 56
    path = ASSETS / "ui_permisos.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_reportes() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "rep")
    _topbar(d, sw, 0, W - sw, "Reportes", "Inteligencia comercial")
    cards = [
        ("Ventas por período", "PDF · Excel"),
        ("Ranking de productos", "PDF"),
        ("Margen y rentabilidad", "PDF"),
        ("Cuentas por cobrar", "PDF · Excel"),
        ("Stock valorizado", "PDF"),
        ("Compras a proveedores", "PDF"),
    ]
    for i, (t, f) in enumerate(cards):
        col, row = i % 3, i // 3
        x = sw + 28 + col * 330
        y = 100 + row * 180
        _rrect(d, (x, y, x + 310, y + 150), 16, fill=WHITE, outline=LINE)
        _rrect(d, (x + 24, y + 28, x + 68, y + 72), 12, fill=(255, 243, 224))
        d.rectangle((x + 34, y + 48, x + 40, y + 62), fill=ORANGE)
        d.rectangle((x + 44, y + 40, x + 50, y + 62), fill=(255, 183, 77))
        d.rectangle((x + 54, y + 34, x + 60, y + 62), fill=ORANGE_D)
        d.text((x + 24, y + 90), t, font=_font(13, "semi"), fill=INK)
        d.text((x + 24, y + 114), f, font=_font(11, "med"), fill=MUTED)
    path = ASSETS / "ui_reportes.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_pdfs() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "pdf")
    _topbar(d, sw, 0, W - sw, "Archivo PDF", "Documentos por cliente")
    folders = [
        ("Comercial Norte SA", "18 PDFs"),
        ("Boutique Luna", "6 PDFs"),
        ("Textil Andina", "11 PDFs"),
        ("MOSTRADOR", "142 PDFs"),
        ("Distribuidora Sur", "9 PDFs"),
        ("Mayorista Centro", "22 PDFs"),
    ]
    for i, (name, count) in enumerate(folders):
        col, row = i % 3, i // 3
        x = sw + 28 + col * 330
        y = 100 + row * 180
        _rrect(d, (x, y, x + 310, y + 150), 16, fill=WHITE, outline=LINE)
        _rrect(d, (x + 110, y + 28, x + 200, y + 100), 12, fill=(255, 243, 224))
        d.text((x + 136, y + 48), "PDF", font=_font(16, "bold"), fill=ORANGE)
        d.text((x + 24, y + 112), name, font=_font(12, "semi"), fill=INK)
        d.text((x + 24, y + 132), count, font=_font(10, "med"), fill=MUTED)
    path = ASSETS / "ui_pdfs.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_config() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cfg")
    _topbar(d, sw, 0, W - sw, "Configuración", "Datos del negocio")
    _rrect(d, (sw + 28, 100, W - 28, H - 40), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 124), "Identidad comercial", font=_font(14, "semi"), fill=INK)
    fields = [
        ("Nombre del negocio", "EL TATA · Indumentaria"),
        ("Teléfono", "+54 11 4567-8900"),
        ("Email", "ventas@eltata.com"),
        ("Dirección", "Av. Corrientes 1234, CABA"),
    ]
    y = 170
    for label, val in fields:
        d.text((sw + 48, y), label, font=_font(10, "med"), fill=MUTED)
        _rrect(d, (sw + 48, y + 18, sw + 520, y + 52), 8, fill=SOFT, outline=LINE)
        d.text((sw + 64, y + 26), val, font=_font(12, "med"), fill=INK)
        y += 70
    # logo preview
    _rrect(d, (sw + 580, 170, W - 60, 340), 14, fill=SOFT, outline=LINE)
    _logo_mark(d, sw + 700, 210, 64)
    d.text((sw + 660, 290), "Logo del negocio", font=_font(12, "semi"), fill=INK)
    d.text((sw + 640, 312), "PNG transparente recomendado", font=_font(10, "med"), fill=MUTED)
    # toggles
    d.text((sw + 580, 370), "Firebase sync", font=_font(12, "semi"), fill=INK)
    _rrect(d, (W - 140, 368, W - 80, 398), 14, fill=ORANGE)
    d.ellipse((W - 112, 372, W - 86, 394), fill=WHITE)
    d.text((sw + 580, 420), "Impresión B/N", font=_font(12, "semi"), fill=INK)
    _rrect(d, (W - 140, 418, W - 80, 448), 14, fill=LINE)
    d.ellipse((W - 136, 422, W - 110, 444), fill=WHITE)
    path = ASSETS / "ui_config.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_chat() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "chat")
    _topbar(d, sw, 0, W - sw, "Comunicaciones", "Chat interno")
    # list
    _rrect(d, (sw + 28, 88, sw + 360, H - 28), 16, fill=WHITE, outline=LINE)
    chats = [
        ("Luis Gómez", "¿Hay stock de jean 32?", "10:42"),
        ("María Ríos", "Remito R-1042 listo", "10:18"),
        ("Equipo ventas", "Objetivo del mes OK", "Ayer"),
    ]
    y = 110
    for i, (name, msg, t) in enumerate(chats):
        bg = (255, 243, 224) if i == 0 else WHITE
        _rrect(d, (sw + 40, y, sw + 340, y + 72), 12, fill=bg)
        d.ellipse((sw + 52, y + 16, sw + 92, y + 56), fill=ORANGE if i == 0 else LINE)
        d.text((sw + 108, y + 14), name, font=_font(12, "semi"), fill=INK)
        d.text((sw + 108, y + 38), msg, font=_font(10, "med"), fill=MUTED)
        d.text((sw + 290, y + 16), t, font=_font(9, "med"), fill=MUTED)
        y += 84
    # thread
    _rrect(d, (sw + 380, 88, W - 28, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 404, 108), "Luis Gómez", font=_font(14, "semi"), fill=INK)
    msgs = [
        (False, "Hola, el cliente pide jean 32 slim"),
        (True, "Hay 4 unidades en depósito"),
        (False, "Perfecto, armo el remito"),
        (True, "Te comparto la ficha del producto"),
    ]
    my = 160
    for mine, text in msgs:
        if mine:
            _rrect(d, (W - 380, my, W - 56, my + 48), 14, fill=ORANGE)
            d.text((W - 360, my + 14), text, font=_font(11, "med"), fill=WHITE)
        else:
            _rrect(d, (sw + 404, my, sw + 760, my + 48), 14, fill=SOFT)
            d.text((sw + 420, my + 14), text, font=_font(11, "med"), fill=INK)
        my += 64
    _rrect(d, (sw + 404, H - 90, W - 56, H - 50), 12, fill=SOFT, outline=LINE)
    d.text((sw + 420, H - 78), "Escribí un mensaje…", font=_font(11, "med"), fill=MUTED)
    path = ASSETS / "ui_chat.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_auditoria() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cfg")
    _topbar(d, sw, 0, W - sw, "Auditoría", "Trazabilidad de cambios")
    rows = [
        ["14/07 11:02", "Ana Pérez", "Producto", "Editó precio RM-001", "8.200 → 8.500"],
        ["14/07 10:55", "Luis Gómez", "Remito", "Creó R-1042", "Comercial Norte"],
        ["14/07 10:22", "Ana Pérez", "Compra", "Registró compra #458", "+70 u."],
        ["13/07 18:01", "Admin", "Usuario", "Alta María Ríos", "Rol Empleado"],
        ["13/07 16:40", "Luis Gómez", "Stock", "Ajuste CP-088", "-1"],
    ]
    _table(
        d,
        sw + 28,
        100,
        W - sw - 56,
        ["Fecha", "Usuario", "Módulo", "Acción", "Detalle"],
        rows,
        [140, 140, 120, 260, 200],
    )
    path = ASSETS / "ui_auditoria.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_cuenta_corriente() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cli")
    _topbar(d, sw, 0, W - sw, "Cuenta corriente", "Cuentas por cobrar")
    _card(d, (sw + 28, 88, sw + 268, 188), "Total a cobrar", "$ 820.400", "27 clientes", RED)
    _card(d, (sw + 290, 88, sw + 530, 188), "Vencido", "$ 194.000", "8 clientes", ORANGE)
    _card(d, (sw + 552, 88, sw + 792, 188), "Este mes", "$ 312.000", "Cobrado", GREEN)
    rows = [
        ["Comercial Norte SA", "R-1042 + ventas", "$ 245.000", "14/07", ("Pendiente", ORANGE)],
        ["Textil Andina", "R-1038", "$ 89.400", "12/07", ("Parcial", BLUE)],
        ["Boutique Luna", "R-1040", "$ 12.300", "13/07", ("Pendiente", ORANGE)],
        ["Retail Pampa", "Fact. 881", "$ 67.800", "10/07", ("Vencido", RED)],
    ]
    _table(
        d,
        sw + 28,
        220,
        W - sw - 56,
        ["Cliente", "Origen", "Saldo", "Último mov.", "Estado"],
        rows,
        [240, 200, 140, 140, 140],
    )
    path = ASSETS / "ui_cc.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_login() -> Path:
    W, H = 1280, 800
    img = Image.new("RGBA", (W, H), (11, 11, 11, 255))
    d = ImageDraw.Draw(img)
    # decorative curves
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((-200, -100, 600, 700), fill=(245, 124, 0, 40))
    od.ellipse((800, 200, 1500, 1000), fill=(245, 124, 0, 28))
    img = Image.alpha_composite(img, overlay)
    d = ImageDraw.Draw(img)
    # card
    cx, cy = W // 2, H // 2
    _rrect(d, (cx - 220, cy - 230, cx + 220, cy + 230), 24, fill=WHITE)
    _logo_mark(d, cx - 24, cy - 190, 48)
    d.text((cx - 90, cy - 120), "Tata.Manager", font=_font(20, "bold"), fill=INK)
    d.text((cx - 110, cy - 92), "Ingresá a tu espacio de trabajo", font=_font(11, "med"), fill=MUTED)
    d.text((cx - 170, cy - 50), "Usuario", font=_font(10, "med"), fill=MUTED)
    _rrect(d, (cx - 170, cy - 30, cx + 170, cy + 4), 10, fill=SOFT, outline=LINE)
    d.text((cx - 156, cy - 22), "admin", font=_font(12, "med"), fill=INK)
    d.text((cx - 170, cy + 24), "Contraseña", font=_font(10, "med"), fill=MUTED)
    _rrect(d, (cx - 170, cy + 44, cx + 170, cy + 78), 10, fill=SOFT, outline=LINE)
    d.text((cx - 156, cy + 52), "••••••••", font=_font(12, "med"), fill=INK)
    _rrect(d, (cx - 170, cy + 110, cx + 170, cy + 152), 12, fill=ORANGE)
    d.text((cx - 40, cy + 122), "Ingresar", font=_font(13, "semi"), fill=WHITE)
    d.text((cx - 90, cy + 175), "Firebase sync activo", font=_font(10, "med"), fill=GREEN)
    path = ASSETS / "ui_login.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_device_hero() -> Path:
    """Composición hero: laptop + tablet + phone con la misma UI."""
    W, H = 1600, 1000
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dash = Image.open(ASSETS / "ui_dashboard.png").convert("RGBA")

    def place_in_frame(screen, frame_box, bezel=10, radius=18):
        nonlocal img
        x0, y0, x1, y1 = frame_box
        # shadow
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        sd.rounded_rectangle((x0 + 8, y0 + 14, x1 + 8, y1 + 18), radius=radius + 4, fill=(0, 0, 0, 60))
        sh = sh.filter(ImageFilter.GaussianBlur(18))
        img = Image.alpha_composite(img, sh)
        d = ImageDraw.Draw(img)
        # chassis
        _rrect(d, (x0, y0, x1, y1), radius, fill=(28, 28, 30))
        # screen area
        sx0, sy0 = x0 + bezel, y0 + bezel
        sx1, sy1 = x1 - bezel, y1 - bezel - 4
        sw, sh_ = sx1 - sx0, sy1 - sy0
        fitted = screen.resize((sw, sh_), Image.Resampling.LANCZOS)
        # mask rounded
        mask = Image.new("L", (sw, sh_), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh_), radius=10, fill=255)
        img.paste(fitted, (sx0, sy0), mask)

    # Laptop
    place_in_frame(dash, (80, 160, 980, 720), bezel=16, radius=20)
    d = ImageDraw.Draw(img)
    # laptop base
    d.polygon([(60, 720), (1000, 720), (1060, 780), (20, 780)], fill=(40, 40, 42))
    d.ellipse((480, 735, 580, 755), fill=(60, 60, 62))

    # Tablet
    place_in_frame(dash, (1020, 120, 1380, 680), bezel=14, radius=28)

    # Phone
    place_in_frame(dash, (1400, 220, 1560, 720), bezel=10, radius=32)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((1455, 235, 1505, 245), radius=4, fill=(50, 50, 52))

    path = ASSETS / "hero_devices.png"
    img.save(path)
    return path


def draw_diagram_sync() -> Path:
    W, H = 1100, 420
    img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    nodes = [
        (80, 180, "Proveedor"),
        (260, 180, "Compra"),
        (440, 180, "Stock"),
        (620, 180, "Firebase"),
        (820, 80, "PC"),
        (820, 180, "Celular"),
        (820, 280, "Tablet"),
    ]
    # arrows base row
    for i in range(3):
        x1 = 80 + i * 180 + 120
        x2 = x1 + 60
        d.line((x1, 210, x2, 210), fill=ORANGE, width=3)
        d.polygon([(x2, 210), (x2 - 10, 204), (x2 - 10, 216)], fill=ORANGE)
    # to devices
    d.line((740, 210, 800, 210), fill=ORANGE, width=3)
    d.line((800, 110, 800, 310), fill=ORANGE, width=3)
    for y in (110, 210, 310):
        d.line((800, y, 820, y), fill=ORANGE, width=3)
        d.polygon([(820, y), (810, y - 6), (810, y + 6)], fill=ORANGE)

    for x, y, label in nodes:
        fill = ORANGE if label == "Firebase" else WHITE
        tc = WHITE if label == "Firebase" else INK
        _rrect(d, (x, y, x + 120, y + 60), 14, fill=fill, outline=ORANGE if label != "Firebase" else ORANGE)
        d.text((x + 18, y + 20), label, font=_font(13, "semi"), fill=tc)
    path = ASSETS / "diagram_sync.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_diagram_venta() -> Path:
    W, H = 1100, 280
    img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    labels = ["Cliente", "Venta", "Remito", "PDF", "WhatsApp"]
    for i, label in enumerate(labels):
        x = 60 + i * 210
        fill = ORANGE if i == 2 else WHITE
        tc = WHITE if i == 2 else INK
        _rrect(d, (x, 100, x + 150, 170), 16, fill=fill, outline=ORANGE)
        d.text((x + 35, 122), label, font=_font(14, "semi"), fill=tc)
        if i < len(labels) - 1:
            d.line((x + 150, 135, x + 210, 135), fill=ORANGE, width=3)
            d.polygon([(x + 210, 135), (x + 200, 129), (x + 200, 141)], fill=ORANGE)
    path = ASSETS / "diagram_venta.png"
    img.convert("RGB").save(path, quality=92)
    return path


def draw_illustrations() -> dict[str, Path]:
    """Ilustraciones vectoriales simples (formas, no clipart)."""
    out = {}
    specs = {
        "ill_cloud": ("Nube", lambda d, W, H: (
            d.ellipse((80, 100, 220, 220), fill=ORANGE),
            d.ellipse((140, 70, 300, 200), fill=ORANGE),
            d.ellipse((220, 110, 360, 230), fill=ORANGE),
            d.rectangle((110, 160, 330, 230), fill=ORANGE),
        )),
        "ill_stock": ("Cajas", lambda d, W, H: (
            d.polygon([(120, 90), (220, 50), (320, 90), (220, 130)], fill=ORANGE),
            d.polygon([(120, 90), (220, 130), (220, 250), (120, 210)], fill=ORANGE_D),
            d.polygon([(220, 130), (320, 90), (320, 210), (220, 250)], fill=(255, 183, 77)),
        )),
        "ill_sales": ("Ventas", lambda d, W, H: (
            d.ellipse((140, 80, 300, 240), outline=ORANGE, width=14),
            d.arc((140, 80, 300, 240), 300, 60, fill=ORANGE, width=14),
            d.polygon([(300, 120), (360, 90), (330, 160)], fill=ORANGE),
        )),
        "ill_users": ("Usuarios", lambda d, W, H: (
            d.ellipse((180, 60, 260, 140), fill=ORANGE),
            d.ellipse((120, 160, 320, 280), fill=ORANGE),
            d.ellipse((80, 90, 140, 150), fill=(255, 183, 77)),
            d.ellipse((300, 90, 360, 150), fill=(255, 183, 77)),
        )),
        "ill_report": ("Reportes", lambda d, W, H: (
            d.rounded_rectangle((120, 60, 320, 280), radius=20, fill=SOFT, outline=ORANGE, width=4),
            d.rectangle((150, 180, 180, 240), fill=ORANGE),
            d.rectangle((200, 140, 230, 240), fill=(255, 183, 77)),
            d.rectangle((250, 100, 280, 240), fill=ORANGE_D),
        )),
        "ill_shield": ("Seguridad", lambda d, W, H: (
            d.polygon([(220, 50), (340, 110), (340, 210), (220, 290), (100, 210), (100, 110)], fill=ORANGE),
            d.line((170, 160, 200, 195), fill=WHITE, width=10),
            d.line((200, 195, 280, 120), fill=WHITE, width=10),
        )),
    }
    for key, (title, painter) in specs.items():
        W, H = 420, 320
        img = Image.new("RGBA", (W, H), (255, 255, 255, 0))
        d = ImageDraw.Draw(img)
        painter(d, W, H)
        path = ASSETS / f"{key}.png"
        img.save(path)
        out[key] = path
    return out


def generate_all_assets() -> dict[str, Path]:
    ASSETS.mkdir(parents=True, exist_ok=True)
    paths = {
        "login": draw_login(),
        "dashboard": draw_dashboard(),
        "productos": draw_productos(),
        "clientes": draw_clientes(),
        "ventas": draw_ventas(),
        "remitos": draw_remitos(),
        "compras": draw_compras(),
        "stock": draw_stock(),
        "usuarios": draw_usuarios(),
        "permisos": draw_permisos(),
        "reportes": draw_reportes(),
        "pdfs": draw_pdfs(),
        "config": draw_config(),
        "chat": draw_chat(),
        "auditoria": draw_auditoria(),
        "cc": draw_cuenta_corriente(),
    }
    paths["hero"] = draw_device_hero()
    paths["diagram_sync"] = draw_diagram_sync()
    paths["diagram_venta"] = draw_diagram_venta()
    paths.update(draw_illustrations())
    return paths


if __name__ == "__main__":
    generate_all_assets()
    print("assets ok", len(list(ASSETS.glob("*"))))
