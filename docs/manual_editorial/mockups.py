"""UI Tata.Manager — mockups, zooms anotados, hero devices e infografías."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

from design import ASSETS

ORANGE = (245, 124, 0)
ORANGE_D = (230, 81, 0)
ORANGE_L = (255, 183, 77)
BLACK = (11, 11, 11)
SIDEBAR = (0, 0, 0)
INK = (26, 26, 26)
MUTED = (107, 114, 128)
LINE = (229, 231, 235)
SOFT = (246, 247, 249)
SOFT2 = (238, 240, 243)
WHITE = (255, 255, 255)
GREEN = (22, 163, 74)
RED = (220, 38, 38)
BLUE = (37, 99, 235)
PHOTOS = ASSETS / "photos"
ZOOMS = ASSETS / "zooms"


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


def _logo_mark(draw, x, y, size=28):
    _rrect(draw, (x, y, x + size, y + size), size * 0.28, fill=ORANGE)
    f = _font(int(size * 0.42), "black")
    draw.text((x + size * 0.22, y + size * 0.22), "T", font=f, fill=WHITE)


def _icon_dot(draw, x, y, selected=False):
    fill = WHITE if selected else (107, 114, 128)
    draw.ellipse((x, y, x + 10, y + 10), fill=fill)


def _sidebar(draw, h, selected: str, w=220):
    draw.rectangle((0, 0, w, h), fill=SIDEBAR)
    _logo_mark(draw, 22, 22, 34)
    draw.text((66, 26), "Tata.Manager", font=_font(15, "bold"), fill=WHITE)
    draw.text((66, 46), "EL TATA · Comercio", font=_font(10, "med"), fill=(156, 163, 175))
    items = [
        ("Inicio", "home"), ("Dashboard", "dash"), ("Productos", "prod"),
        ("Clientes", "cli"), ("Ventas", "ven"), ("Remitos", "rem"),
        ("Compras", "com"), ("Stock", "stk"), ("Proveedores", "prv"),
        ("Reportes", "rep"), ("Archivo PDF", "pdf"), ("Usuarios", "usr"),
        ("Configuración", "cfg"), ("Chat", "chat"), ("Respaldo", "bak"),
    ]
    y = 88
    for label, key in items:
        sel = key == selected
        if sel:
            _rrect(draw, (12, y - 6, w - 12, y + 26), 10, fill=ORANGE)
        color = WHITE if sel else (209, 213, 219)
        _icon_dot(draw, 24, y + 4, sel)
        draw.text((44, y), label, font=_font(12, "med"), fill=color)
        y += 34
    draw.rectangle((0, h - 70, w, h), fill=(20, 20, 20))
    draw.ellipse((20, h - 52, 52, h - 20), fill=ORANGE)
    draw.text((28, h - 46), "A", font=_font(14, "bold"), fill=WHITE)
    draw.text((62, h - 50), "Admin", font=_font(12, "semi"), fill=WHITE)
    draw.text((62, h - 32), "En línea · Firebase", font=_font(9, "med"), fill=(107, 114, 128))
    return w


def _topbar(draw, x, y, w, title: str, breadcrumb: str = ""):
    draw.rectangle((x, y, x + w, y + 64), fill=WHITE)
    draw.line((x, y + 64, x + w, y + 64), fill=LINE, width=1)
    draw.text((x + 28, y + 16), title, font=_font(20, "bold"), fill=INK)
    if breadcrumb:
        draw.text((x + 28, y + 42), breadcrumb, font=_font(10, "med"), fill=MUTED)
    sx = x + w - 320
    _rrect(draw, (sx, y + 16, sx + 200, y + 48), 10, fill=SOFT, outline=LINE)
    draw.text((sx + 14, y + 24), "Buscar…", font=_font(11, "med"), fill=MUTED)
    draw.ellipse((x + w - 96, y + 18, x + w - 64, y + 50), fill=SOFT)
    draw.ellipse((x + w - 86, y + 28, x + w - 74, y + 42), outline=ORANGE, width=2)
    draw.ellipse((x + w - 52, y + 18, x + w - 20, y + 50), outline=ORANGE, width=2)


def _card(draw, box, title, value, subtitle, accent=ORANGE):
    x0, y0, x1, y1 = box
    _rrect(draw, box, 14, fill=WHITE, outline=LINE)
    draw.rectangle((x0, y0, x0 + 5, y1), fill=accent)
    draw.text((x0 + 18, y0 + 14), title, font=_font(11, "med"), fill=MUTED)
    draw.text((x0 + 18, y0 + 36), value, font=_font(22, "bold"), fill=INK)
    draw.text((x0 + 18, y0 + 68), subtitle, font=_font(10, "med"), fill=MUTED)


def _table(draw, x, y, w, headers, rows, col_w=None):
    h = 40
    _rrect(draw, (x, y, x + w, y + h), 10, fill=BLACK)
    draw.rectangle((x, y + 16, x + w, y + h), fill=BLACK)
    if col_w is None:
        col_w = [w // len(headers)] * len(headers)
    cx = x + 16
    for i, htxt in enumerate(headers):
        draw.text((cx, y + 12), htxt, font=_font(10, "semi"), fill=WHITE)
        cx += col_w[i]
    yy = y + h
    for ri, row in enumerate(rows):
        bg = WHITE if ri % 2 == 0 else (252, 252, 253)
        draw.rectangle((x, yy, x + w, yy + 38), fill=bg)
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


def _annotate(img: Image.Image, items: list[tuple]):
    """items: (x, y, num, label, side) side=left|right"""
    d = ImageDraw.Draw(img)
    for x, y, num, label, side in items:
        r = 16
        d.ellipse((x - r, y - r, x + r, y + r), fill=ORANGE)
        d.text((x - 6, y - 10), str(num), font=_font(16, "bold"), fill=WHITE)
        # leader
        if side == "right":
            x2 = x + 90
            d.line((x + r, y, x2, y), fill=ORANGE, width=3)
            _rrect(d, (x2, y - 16, x2 + 8 + len(label) * 8, y + 16), 8, fill=ORANGE)
            d.text((x2 + 8, y - 8), label, font=_font(12, "semi"), fill=WHITE)
        else:
            tw = len(label) * 8 + 16
            x2 = x - 90
            d.line((x - r, y, x2, y), fill=ORANGE, width=3)
            _rrect(d, (x2 - tw, y - 16, x2, y + 16), 8, fill=ORANGE)
            d.text((x2 - tw + 8, y - 8), label, font=_font(12, "semi"), fill=WHITE)
    return img


def _save(img: Image.Image, name: str) -> Path:
    path = ASSETS / name
    img.convert("RGB").save(path, quality=93)
    return path


def draw_dashboard() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "dash")
    _topbar(d, sw, 0, W - sw, "Dashboard", "Resumen operativo · Hoy")
    cards = [
        (sw + 28, 88, "Productos", "1.248", "Catálogo activo", ORANGE),
        (sw + 310, 88, "Sin stock", "12", "Requieren reposición", RED),
        (sw + 592, 88, "Ventas del mes", "$ 4.8M", "+12% vs mes ant.", GREEN),
        (sw + 874, 88, "Por cobrar", "$ 820K", "27 clientes", BLUE),
    ]
    for x, y, t, v, s, a in cards:
        _card(d, (x, y, x + 260, y + 100), t, v, s, a)
    _rrect(d, (sw + 28, 210, W - 28, 500), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 228), "Ventas mensuales", font=_font(14, "semi"), fill=INK)
    bars = [40, 55, 48, 70, 62, 85, 78, 90, 88, 95, 100, 92]
    bx = sw + 70
    for i, b in enumerate(bars):
        bh = int(b * 2.0)
        _rrect(d, (bx, 470 - bh, bx + 46, 470), 8, fill=ORANGE if i == 11 else ORANGE_L)
        d.text((bx + 10, 480), f"{i+1:02d}", font=_font(9, "med"), fill=MUTED)
        bx += 78
    _rrect(d, (sw + 28, 520, sw + 560, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 48, 538), "Top productos", font=_font(14, "semi"), fill=INK)
    _table(d, sw + 48, 570, 480, ["Producto", "Vendidos", "Monto"],
           [["Remera básica", "184", "$ 920K"], ["Jean slim", "96", "$ 1.1M"],
            ["Campera soft", "54", "$ 810K"], ["Zapatilla city", "41", "$ 615K"]],
           [200, 130, 150])
    _rrect(d, (sw + 588, 520, W - 28, H - 28), 16, fill=WHITE, outline=LINE)
    d.text((sw + 608, 538), "Alertas", font=_font(14, "semi"), fill=INK)
    ay = 580
    for t, s, c in [("Sin stock", "12 productos", RED), ("Stock bajo", "28 productos", ORANGE), ("Deudores", "$ 820K", BLUE)]:
        _rrect(d, (sw + 608, ay, W - 48, ay + 56), 12, fill=SOFT)
        d.ellipse((sw + 624, ay + 18, sw + 644, ay + 38), fill=c)
        d.text((sw + 660, ay + 10), t, font=_font(12, "semi"), fill=INK)
        d.text((sw + 660, ay + 30), s, font=_font(11, "med"), fill=MUTED)
        ay += 68
    return _save(img, "ui_dashboard.png")


def draw_dashboard_annotated() -> Path:
    img = Image.open(ASSETS / "ui_dashboard.png").convert("RGBA")
    img = _annotate(img, [
        (470, 140, "1", "KPIs", "right"),
        (900, 350, "2", "Tendencia", "right"),
        (420, 650, "3", "Top ventas", "right"),
        (1050, 650, "4", "Alertas", "left"),
    ])
    return _save(img, "ui_dashboard_ann.png")


def draw_productos() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "prod")
    _topbar(d, sw, 0, W - sw, "Productos", "Catálogo · Listas de precio")
    _rrect(d, (sw + 28, 88, W - 28, 150), 12, fill=WHITE, outline=LINE)
    _rrect(d, (sw + 44, 104, sw + 420, 134), 8, fill=SOFT, outline=LINE)
    d.text((sw + 58, 110), "Buscar código, nombre, marca…", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (sw + 440, 104, sw + 580, 134), 8, fill=SOFT, outline=LINE)
    d.text((sw + 458, 110), "Marca ▾", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (sw + 600, 104, sw + 720, 134), 8, fill=SOFT, outline=LINE)
    d.text((sw + 618, 110), "Filtros", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (sw + 740, 104, sw + 860, 134), 8, fill=SOFT, outline=ORANGE, width=2)
    d.text((sw + 758, 110), "Escanear", font=_font(11, "semi"), fill=ORANGE)
    # botón destacado (para zoom)
    _rrect(d, (W - 220, 104, W - 44, 134), 8, fill=ORANGE)
    d.text((W - 185, 110), "+ Nuevo producto", font=_font(12, "semi"), fill=WHITE)
    rows = [
        ["RM-001", "Remera algodón blanca", "Nike", "48", "$ 8.500", ("Activo", GREEN)],
        ["JN-214", "Jean slim azul", "Levi's", "22", "$ 24.900", ("Activo", GREEN)],
        ["CP-088", "Campera softshell", "Columbia", "0", "$ 68.000", ("Sin stock", RED)],
        ["ZP-331", "Zapatilla city run", "Adidas", "15", "$ 55.000", ("Activo", GREEN)],
        ["CJ-102", "Camisa jean", "Wrangler", "9", "$ 19.500", ("Bajo", ORANGE)],
        ["GT-441", "Gorra trucker", "New Era", "61", "$ 7.200", ("Activo", GREEN)],
        ["MD-019", "Medias pack x3", "Nike", "120", "$ 4.100", ("Activo", GREEN)],
        ["BL-077", "Buzo canguro", "Puma", "3", "$ 32.000", ("Bajo", ORANGE)],
        ["CF-210", "Chaleco fleece", "The North Face", "18", "$ 41.000", ("Activo", GREEN)],
    ]
    _table(d, sw + 28, 170, W - sw - 56,
           ["Código", "Descripción", "Marca", "Stock", "Precio", "Estado"],
           rows, [120, 320, 150, 100, 130, 130])
    return _save(img, "ui_productos.png")


def draw_productos_annotated() -> Path:
    img = Image.open(ASSETS / "ui_productos.png").convert("RGBA")
    img = _annotate(img, [
        (1280, 120, "1", "Nuevo producto", "left"),
        (500, 120, "2", "Buscar", "right"),
        (780, 120, "3", "Filtros", "right"),
        (900, 120, "4", "Escanear", "right"),
        (350, 280, "5", "Editar fila", "right"),
    ])
    return _save(img, "ui_productos_ann.png")


def draw_producto_form(mode="nuevo") -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "prod")
    title = "Nuevo producto" if mode == "nuevo" else "Editar producto · RM-001"
    _topbar(d, sw, 0, W - sw, title, "Ficha de catálogo")
    _rrect(d, (sw + 40, 100, W - 40, H - 40), 18, fill=WHITE, outline=LINE)
    # photo slot
    _rrect(d, (sw + 70, 140, sw + 320, 390), 14, fill=SOFT, outline=LINE)
    _logo_mark(d, sw + 165, 230, 56)
    d.text((sw + 120, 310), "Subir foto", font=_font(12, "semi"), fill=ORANGE)
    fields = [
        ("Código", "RM-001"), ("Descripción", "Remera algodón blanca"),
        ("Marca", "Nike"), ("Proveedor", "Textil Andina"),
        ("Stock", "48"), ("Costo", "$ 3.200"),
        ("Precio lista 1", "$ 8.500"), ("Precio lista 2", "$ 7.200"),
    ]
    y = 140
    for i, (lab, val) in enumerate(fields):
        col = i % 2
        row = i // 2
        x = sw + 360 + col * 420
        yy = y + row * 90
        d.text((x, yy), lab, font=_font(10, "med"), fill=MUTED)
        _rrect(d, (x, yy + 18, x + 380, yy + 56), 10, fill=SOFT, outline=LINE)
        d.text((x + 14, yy + 28), val, font=_font(13, "med"), fill=INK)
    # save button
    _rrect(d, (W - 260, H - 120, W - 70, H - 70), 12, fill=ORANGE)
    d.text((W - 200, H - 105), "Guardar", font=_font(16, "semi"), fill=WHITE)
    name = "ui_producto_nuevo.png" if mode == "nuevo" else "ui_producto_editar.png"
    return _save(img, name)


def draw_zoom_button_nuevo() -> Path:
    """Crop + flecha enorme al estilo Microsoft."""
    src = Image.open(ASSETS / "ui_productos.png").convert("RGBA")
    # crop around nuevo button
    crop = src.crop((src.width - 280, 70, src.width - 20, 180)).resize((900, 360), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (1200, 700), (*SOFT, 255))
    canvas.paste(crop, (150, 80), crop)
    d = ImageDraw.Draw(canvas)
    # huge arrow
    d.polygon([(600, 520), (640, 420), (620, 420), (620, 300), (580, 300), (580, 420), (560, 420)], fill=ORANGE)
    d.ellipse((540, 540, 660, 660), fill=ORANGE)
    d.text((575, 575), "1", font=_font(48, "black"), fill=WHITE)
    d.text((200, 600), "Tocá Nuevo producto para abrir la ficha", font=_font(18, "semi"), fill=INK)
    ZOOMS.mkdir(exist_ok=True)
    path = ZOOMS / "zoom_nuevo_producto.png"
    canvas.convert("RGB").save(path, quality=93)
    return path


def draw_zoom_guardar() -> Path:
    src = Image.open(ASSETS / "ui_producto_nuevo.png").convert("RGBA")
    crop = src.crop((src.width - 320, src.height - 180, src.width - 40, src.height - 40)).resize((800, 320), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (1200, 650), (11, 11, 11, 255))
    canvas.paste(crop, (200, 80), crop)
    d = ImageDraw.Draw(canvas)
    d.polygon([(600, 520), (650, 400), (620, 400), (620, 280), (580, 280), (580, 400), (550, 400)], fill=ORANGE)
    d.text((180, 560), "Confirmá con Guardar. El ítem queda listo para vender.", font=_font(18, "semi"), fill=WHITE)
    path = ZOOMS / "zoom_guardar.png"
    canvas.convert("RGB").save(path, quality=93)
    return path


def draw_clientes() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cli")
    _topbar(d, sw, 0, W - sw, "Clientes", "Agenda comercial")
    _rrect(d, (W - 200, 96, W - 44, 132), 10, fill=ORANGE)
    d.text((W - 160, 104), "+ Nuevo", font=_font(13, "semi"), fill=WHITE)
    clients = [
        ("Comercial Norte SA", "CUIT 30-71234567-8", "$ 245.000", "Debe"),
        ("Distribuidora Sur", "CUIT 30-69871234-1", "$ 0", "Al día"),
        ("MOSTRADOR", "Consumidor final", "$ 0", "Al día"),
        ("Textil Andina", "CUIT 33-55443322-0", "$ 89.400", "Debe"),
        ("Boutique Luna", "Cel 11 5555-2211", "$ 12.300", "Debe"),
        ("Mayorista Centro", "CUIT 30-11223344-5", "$ 0", "Al día"),
    ]
    for i, (name, meta, saldo, estado) in enumerate(clients):
        col, row = i % 3, i // 3
        x = sw + 36 + col * 360
        y = 160 + row * 200
        _rrect(d, (x, y, x + 340, y + 170), 18, fill=WHITE, outline=LINE)
        d.ellipse((x + 24, y + 28, x + 80, y + 84), fill=(255, 243, 224))
        d.text((x + 42, y + 42), name[0], font=_font(18, "bold"), fill=ORANGE)
        d.text((x + 96, y + 36), name, font=_font(14, "semi"), fill=INK)
        d.text((x + 96, y + 60), meta, font=_font(11, "med"), fill=MUTED)
        color = RED if estado == "Debe" else GREEN
        d.text((x + 24, y + 110), saldo, font=_font(18, "bold"), fill=color)
        _rrect(d, (x + 220, y + 112, x + 320, y + 142), 8,
               fill=(254, 242, 242) if estado == "Debe" else (236, 253, 245))
        d.text((x + 240, y + 118), estado, font=_font(11, "semi"), fill=color)
    return _save(img, "ui_clientes.png")


def draw_cliente_ficha() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cli")
    _topbar(d, sw, 0, W - sw, "Comercial Norte SA", "Ficha · Historial · Cuenta corriente")
    _rrect(d, (sw + 36, 100, sw + 480, 360), 18, fill=WHITE, outline=LINE)
    d.ellipse((sw + 60, 130, sw + 150, 220), fill=(255, 243, 224))
    d.text((sw + 90, 155), "C", font=_font(28, "bold"), fill=ORANGE)
    d.text((sw + 170, 145), "Comercial Norte SA", font=_font(16, "bold"), fill=INK)
    d.text((sw + 170, 175), "CUIT 30-71234567-8", font=_font(12, "med"), fill=MUTED)
    d.text((sw + 170, 200), "Tel +54 11 4000-2211", font=_font(12, "med"), fill=MUTED)
    d.text((sw + 60, 250), "Saldo actual", font=_font(11, "med"), fill=MUTED)
    d.text((sw + 60, 275), "$ 245.000", font=_font(28, "bold"), fill=RED)
    _rrect(d, (sw + 60, 320, sw + 200, 350), 8, fill=ORANGE)
    d.text((sw + 78, 326), "Cobrar", font=_font(12, "semi"), fill=WHITE)
    _rrect(d, (sw + 500, 100, W - 36, H - 40), 18, fill=WHITE, outline=LINE)
    d.text((sw + 530, 120), "Historial reciente", font=_font(14, "semi"), fill=INK)
    _table(d, sw + 530, 160, W - sw - 600,
           ["Fecha", "Doc", "Monto", "Estado"],
           [["14/07", "R-1042", "$ 245.000", ("Pendiente", ORANGE)],
            ["02/07", "R-0998", "$ 120.000", ("Cobrado", GREEN)],
            ["18/06", "V-441", "$ 88.000", ("Cobrado", GREEN)],
            ["01/06", "R-0901", "$ 56.400", ("Cobrado", GREEN)]],
           [120, 120, 140, 140])
    return _save(img, "ui_cliente_ficha.png")


def draw_ventas() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "ven")
    _topbar(d, sw, 0, W - sw, "Venta rápida", "Cliente MOSTRADOR · Lista minorista")
    _rrect(d, (sw + 28, 96, sw + 560, H - 36), 18, fill=WHITE, outline=LINE)
    d.text((sw + 52, 120), "Agregar productos", font=_font(15, "semi"), fill=INK)
    _rrect(d, (sw + 52, 156, sw + 520, 192), 10, fill=SOFT, outline=LINE)
    d.text((sw + 70, 166), "Escanear o buscar…", font=_font(12, "med"), fill=MUTED)
    iy = 220
    for name, price in [("RM-001 Remera blanca", "$ 8.500"), ("JN-214 Jean slim", "$ 24.900"),
                        ("GT-441 Gorra trucker", "$ 7.200"), ("MD-019 Medias x3", "$ 4.100"),
                        ("BL-077 Buzo canguro", "$ 32.000")]:
        _rrect(d, (sw + 52, iy, sw + 520, iy + 60), 12, fill=SOFT)
        d.text((sw + 72, iy + 18), name, font=_font(13, "med"), fill=INK)
        d.text((sw + 400, iy + 18), price, font=_font(13, "semi"), fill=ORANGE)
        iy += 74
    _rrect(d, (sw + 590, 96, W - 36, H - 36), 18, fill=WHITE, outline=LINE)
    d.text((sw + 620, 120), "Carrito", font=_font(15, "semi"), fill=INK)
    cy = 170
    for name, price in [("Remera blanca x2", "$ 17.000"), ("Jean slim x1", "$ 24.900"), ("Gorra trucker x1", "$ 7.200")]:
        d.text((sw + 620, cy), name, font=_font(13, "med"), fill=INK)
        d.text((W - 180, cy), price, font=_font(13, "semi"), fill=INK)
        cy += 40
    d.line((sw + 620, cy + 10, W - 60, cy + 10), fill=LINE, width=2)
    d.text((sw + 620, cy + 30), "Total", font=_font(14, "semi"), fill=MUTED)
    d.text((W - 220, cy + 22), "$ 49.100", font=_font(26, "bold"), fill=INK)
    _rrect(d, (sw + 620, H - 140, W - 60, H - 80), 14, fill=ORANGE)
    d.text((sw + 780, H - 122), "Confirmar venta", font=_font(16, "semi"), fill=WHITE)
    return _save(img, "ui_ventas.png")


def draw_ventas_annotated() -> Path:
    img = Image.open(ASSETS / "ui_ventas.png").convert("RGBA")
    img = _annotate(img, [
        (500, 175, "1", "Buscar / escanear", "right"),
        (500, 260, "2", "Agregar ítem", "right"),
        (1050, 200, "3", "Carrito", "left"),
        (1100, 780, "4", "Confirmar", "left"),
    ])
    return _save(img, "ui_ventas_ann.png")


def draw_remitos() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "rem")
    _topbar(d, sw, 0, W - sw, "Remitos", "Documentos de entrega")
    _rrect(d, (W - 240, 96, W - 44, 132), 10, fill=ORANGE)
    d.text((W - 210, 104), "+ Nuevo remito", font=_font(12, "semi"), fill=WHITE)
    rows = [
        ["R-1042", "14/07/2026", "Comercial Norte", "$ 245.000", ("Pendiente", ORANGE)],
        ["R-1041", "14/07/2026", "MOSTRADOR", "$ 49.100", ("Cobrado", GREEN)],
        ["R-1040", "13/07/2026", "Boutique Luna", "$ 12.300", ("Pendiente", ORANGE)],
        ["R-1039", "13/07/2026", "Distribuidora Sur", "$ 188.000", ("Cobrado", GREEN)],
        ["R-1038", "12/07/2026", "Textil Andina", "$ 89.400", ("Parcial", BLUE)],
        ["R-1037", "12/07/2026", "Mayorista Centro", "$ 320.000", ("Cobrado", GREEN)],
        ["R-1036", "11/07/2026", "Retail Pampa", "$ 67.800", ("Pendiente", ORANGE)],
    ]
    _table(d, sw + 36, 160, W - sw - 72, ["Nº", "Fecha", "Cliente", "Total", "Estado"],
           rows, [130, 160, 320, 180, 160])
    return _save(img, "ui_remitos.png")


def draw_compras() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "com")
    _topbar(d, sw, 0, W - sw, "Compras", "Ingresos de mercadería")
    _rrect(d, (sw + 36, 100, W - 36, 230), 16, fill=WHITE, outline=LINE)
    d.text((sw + 56, 120), "Nueva compra", font=_font(15, "semi"), fill=INK)
    fx = sw + 56
    for lab, val in [("Proveedor", "Textil Andina SRL"), ("Fecha", "14/07/2026"), ("Nº factura", "A-0001-458")]:
        d.text((fx, 155), lab, font=_font(10, "med"), fill=MUTED)
        _rrect(d, (fx, 175, fx + 260, 210), 10, fill=SOFT, outline=LINE)
        d.text((fx + 14, 184), val, font=_font(12, "med"), fill=INK)
        fx += 300
    _table(d, sw + 36, 260, W - sw - 72,
           ["Código", "Producto", "Cant.", "Costo", "Subtotal"],
           [["RM-001", "Remera algodón", "40", "$ 3.200", "$ 128.000"],
            ["JN-214", "Jean slim", "20", "$ 11.500", "$ 230.000"],
            ["CP-088", "Campera soft", "10", "$ 28.000", "$ 280.000"],
            ["ZP-331", "Zapatilla city", "15", "$ 22.000", "$ 330.000"]],
           [140, 340, 120, 180, 180])
    _rrect(d, (W - 300, H - 110, W - 50, H - 60), 12, fill=ORANGE)
    d.text((W - 260, H - 95), "Registrar compra", font=_font(14, "semi"), fill=WHITE)
    return _save(img, "ui_compras.png")


def draw_stock() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "stk")
    _topbar(d, sw, 0, W - sw, "Stock", "Movimientos · Alertas · Kardex")
    for i, (t, sel) in enumerate([("Movimientos", True), ("Alertas", False), ("Kardex", False)]):
        x = sw + 36 + i * 150
        if sel:
            _rrect(d, (x, 100, x + 130, 136), 10, fill=ORANGE)
            d.text((x + 20, 110), t, font=_font(12, "semi"), fill=WHITE)
        else:
            _rrect(d, (x, 100, x + 130, 136), 10, fill=WHITE, outline=LINE)
            d.text((x + 20, 110), t, font=_font(12, "med"), fill=MUTED)
    rows = [
        ["14/07 10:22", "Entrada", "Compra #458", "RM-001", "+40", "48"],
        ["14/07 11:05", "Salida", "Remito R-1042", "JN-214", "-2", "22"],
        ["14/07 11:05", "Salida", "Remito R-1042", "RM-001", "-6", "42"],
        ["13/07 16:40", "Ajuste", "Inventario", "CP-088", "-1", "0"],
        ["13/07 09:12", "Entrada", "Compra #457", "ZP-331", "+15", "15"],
        ["12/07 18:01", "Salida", "Venta rápida", "GT-441", "-3", "61"],
    ]
    _table(d, sw + 36, 160, W - sw - 72,
           ["Fecha", "Tipo", "Origen", "Producto", "Cant.", "Saldo"],
           rows, [170, 120, 220, 200, 120, 120])
    return _save(img, "ui_stock.png")


def draw_usuarios() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "usr")
    _topbar(d, sw, 0, W - sw, "Usuarios", "Accesos y roles")
    users = [
        ("Ana Pérez", "admin", "Administrador", "En línea"),
        ("Luis Gómez", "lgomez", "Encargado", "En línea"),
        ("María Ríos", "mrios", "Empleado", "Ausente"),
        ("Carlos Díaz", "cdiaz", "Empleado", "En línea"),
        ("Sofía Vega", "svega", "Encargado", "En línea"),
    ]
    y = 110
    for name, user, rol, st in users:
        _rrect(d, (sw + 36, y, W - 36, y + 100), 16, fill=WHITE, outline=LINE)
        d.ellipse((sw + 60, y + 22, sw + 118, y + 80), fill=(255, 243, 224))
        d.text((sw + 78, y + 38), name[0], font=_font(18, "bold"), fill=ORANGE)
        d.text((sw + 140, y + 28), name, font=_font(16, "semi"), fill=INK)
        d.text((sw + 140, y + 56), f"@{user} · {rol}", font=_font(12, "med"), fill=MUTED)
        color = GREEN if st == "En línea" else MUTED
        _rrect(d, (W - 200, y + 34, W - 60, y + 68), 10, fill=SOFT)
        d.ellipse((W - 184, y + 46, W - 170, y + 60), fill=color)
        d.text((W - 160, y + 42), st, font=_font(11, "semi"), fill=INK)
        y += 118
    return _save(img, "ui_usuarios.png")


def draw_roles() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "usr")
    _topbar(d, sw, 0, W - sw, "Roles", "Perfiles de acceso")
    roles = [
        ("Administrador", "Control total del sistema", ORANGE, "Todo"),
        ("Encargado", "Operación ampliada", BLUE, "Según matriz"),
        ("Empleado", "Tareas diarias", GREEN, "Limitado"),
    ]
    x = sw + 50
    for title, desc, color, scope in roles:
        _rrect(d, (x, 140, x + 340, 520), 20, fill=WHITE, outline=LINE)
        d.ellipse((x + 120, 190, x + 220, 290), fill=color)
        d.text((x + 40, 330), title, font=_font(18, "bold"), fill=INK)
        d.text((x + 40, 370), desc, font=_font(13, "med"), fill=MUTED)
        _rrect(d, (x + 40, 430, x + 300, 480), 12, fill=SOFT)
        d.text((x + 70, 445), f"Alcance: {scope}", font=_font(13, "semi"), fill=color)
        x += 370
    return _save(img, "ui_roles.png")


def draw_permisos() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "usr")
    _topbar(d, sw, 0, W - sw, "Permisos", "Matriz por rol · Encargado")
    _rrect(d, (sw + 36, 110, W - 36, H - 40), 18, fill=WHITE, outline=LINE)
    mods = ["Productos", "Ventas", "Clientes", "Compras", "Stock", "Usuarios", "Config", "Reportes"]
    roles = ["Ver", "Crear", "Editar", "Eliminar"]
    d.text((sw + 60, 140), "Módulo", font=_font(12, "semi"), fill=MUTED)
    for i, r in enumerate(roles):
        d.text((sw + 320 + i * 180, 140), r, font=_font(12, "semi"), fill=MUTED)
    pattern = [[1,1,1,0],[1,1,1,0],[1,1,1,0],[1,1,0,0],[1,1,1,0],[1,0,0,0],[1,0,0,0],[1,1,0,0]]
    y = 190
    for mi, mod in enumerate(mods):
        d.text((sw + 60, y + 10), mod, font=_font(14, "med"), fill=INK)
        for ri, ok in enumerate(pattern[mi]):
            x = sw + 330 + ri * 180
            if ok:
                _rrect(d, (x, y, x + 34, y + 34), 8, fill=ORANGE)
                d.line((x + 8, y + 18, x + 14, y + 24), fill=WHITE, width=3)
                d.line((x + 14, y + 24, x + 26, y + 10), fill=WHITE, width=3)
            else:
                _rrect(d, (x, y, x + 34, y + 34), 8, fill=SOFT, outline=LINE)
        y += 70
    return _save(img, "ui_permisos.png")


def draw_reportes() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "rep")
    _topbar(d, sw, 0, W - sw, "Reportes", "Inteligencia comercial")
    cards = [
        ("Ventas por período", "PDF · Excel"), ("Ranking de productos", "PDF"),
        ("Margen y rentabilidad", "PDF"), ("Cuentas por cobrar", "PDF · Excel"),
        ("Stock valorizado", "PDF"), ("Compras a proveedores", "PDF"),
    ]
    for i, (t, f) in enumerate(cards):
        col, row = i % 3, i // 3
        x = sw + 40 + col * 360
        y = 120 + row * 220
        _rrect(d, (x, y, x + 330, y + 190), 18, fill=WHITE, outline=LINE)
        _rrect(d, (x + 28, y + 28, x + 88, y + 88), 14, fill=(255, 243, 224))
        d.rectangle((x + 42, y + 55, x + 50, y + 75), fill=ORANGE)
        d.rectangle((x + 56, y + 45, x + 64, y + 75), fill=ORANGE_L)
        d.rectangle((x + 70, y + 35, x + 78, y + 75), fill=ORANGE_D)
        d.text((x + 28, y + 110), t, font=_font(15, "semi"), fill=INK)
        d.text((x + 28, y + 140), f, font=_font(12, "med"), fill=MUTED)
    return _save(img, "ui_reportes.png")


def draw_pdfs() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "pdf")
    _topbar(d, sw, 0, W - sw, "Archivo PDF", "Documentos por cliente")
    folders = [
        ("Comercial Norte SA", "18 PDFs"), ("Boutique Luna", "6 PDFs"),
        ("Textil Andina", "11 PDFs"), ("MOSTRADOR", "142 PDFs"),
        ("Distribuidora Sur", "9 PDFs"), ("Mayorista Centro", "22 PDFs"),
    ]
    for i, (name, count) in enumerate(folders):
        col, row = i % 3, i // 3
        x = sw + 40 + col * 360
        y = 120 + row * 220
        _rrect(d, (x, y, x + 330, y + 190), 18, fill=WHITE, outline=LINE)
        _rrect(d, (x + 105, y + 36, x + 225, y + 120), 14, fill=(255, 243, 224))
        d.text((x + 135, y + 65), "PDF", font=_font(20, "bold"), fill=ORANGE)
        d.text((x + 28, y + 140), name, font=_font(13, "semi"), fill=INK)
        d.text((x + 28, y + 164), count, font=_font(11, "med"), fill=MUTED)
    return _save(img, "ui_pdfs.png")


def draw_config() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cfg")
    _topbar(d, sw, 0, W - sw, "Configuración", "Datos del negocio")
    _rrect(d, (sw + 36, 110, W - 36, H - 40), 18, fill=WHITE, outline=LINE)
    d.text((sw + 60, 140), "Identidad comercial", font=_font(16, "semi"), fill=INK)
    y = 190
    for lab, val in [("Nombre", "EL TATA · Indumentaria"), ("Teléfono", "+54 11 4567-8900"),
                     ("Email", "ventas@eltata.com"), ("Dirección", "Av. Corrientes 1234, CABA")]:
        d.text((sw + 60, y), lab, font=_font(10, "med"), fill=MUTED)
        _rrect(d, (sw + 60, y + 18, sw + 560, y + 58), 10, fill=SOFT, outline=LINE)
        d.text((sw + 78, y + 28), val, font=_font(13, "med"), fill=INK)
        y += 80
    _rrect(d, (sw + 620, 190, W - 70, 420), 16, fill=SOFT, outline=LINE)
    _logo_mark(d, sw + 760, 240, 72)
    d.text((sw + 700, 340), "Logo del negocio", font=_font(13, "semi"), fill=INK)
    d.text((sw + 620, 460), "Firebase sync", font=_font(13, "semi"), fill=INK)
    _rrect(d, (W - 180, 456, W - 100, 492), 16, fill=ORANGE)
    d.ellipse((W - 146, 460, W - 114, 488), fill=WHITE)
    return _save(img, "ui_config.png")


def draw_chat() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "chat")
    _topbar(d, sw, 0, W - sw, "Comunicaciones", "Chat interno")
    _rrect(d, (sw + 36, 100, sw + 420, H - 40), 18, fill=WHITE, outline=LINE)
    chats = [("Luis Gómez", "¿Hay stock de jean 32?", "10:42"),
             ("María Ríos", "Remito R-1042 listo", "10:18"),
             ("Equipo ventas", "Objetivo del mes OK", "Ayer")]
    y = 130
    for i, (name, msg, t) in enumerate(chats):
        bg = (255, 243, 224) if i == 0 else WHITE
        _rrect(d, (sw + 52, y, sw + 400, y + 80), 14, fill=bg)
        d.ellipse((sw + 68, y + 16, sw + 116, y + 64), fill=ORANGE if i == 0 else LINE)
        d.text((sw + 132, y + 18), name, font=_font(13, "semi"), fill=INK)
        d.text((sw + 132, y + 44), msg, font=_font(11, "med"), fill=MUTED)
        d.text((sw + 340, y + 18), t, font=_font(10, "med"), fill=MUTED)
        y += 96
    _rrect(d, (sw + 450, 100, W - 36, H - 40), 18, fill=WHITE, outline=LINE)
    d.text((sw + 480, 125), "Luis Gómez", font=_font(16, "semi"), fill=INK)
    msgs = [(False, "Hola, el cliente pide jean 32 slim"),
            (True, "Hay 4 unidades en depósito"),
            (False, "Perfecto, armo el remito"),
            (True, "Te comparto la ficha del producto")]
    my = 180
    for mine, text in msgs:
        if mine:
            _rrect(d, (W - 520, my, W - 70, my + 56), 16, fill=ORANGE)
            d.text((W - 490, my + 16), text, font=_font(12, "med"), fill=WHITE)
        else:
            _rrect(d, (sw + 480, my, sw + 900, my + 56), 16, fill=SOFT)
            d.text((sw + 500, my + 16), text, font=_font(12, "med"), fill=INK)
        my += 76
    return _save(img, "ui_chat.png")


def draw_auditoria() -> Path:
    W, H = 1400, 860
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
        ["12/07 09:11", "Sofía Vega", "Config", "Cambió logo", "OK"],
    ]
    _table(d, sw + 36, 120, W - sw - 72,
           ["Fecha", "Usuario", "Módulo", "Acción", "Detalle"],
           rows, [160, 160, 140, 300, 220])
    return _save(img, "ui_auditoria.png")


def draw_backup() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "bak")
    _topbar(d, sw, 0, W - sw, "Respaldo", "Exportar · Importar · Seguridad")
    for i, (title, desc, cta) in enumerate([
        ("Exportar base", "Generá un archivo .db seguro con todos los datos del negocio.", "Exportar ahora"),
        ("Importar base", "Cloná datos en otra PC o celular restaurando un respaldo.", "Importar archivo"),
        ("Auto-backup", "Copias periódicas locales para no depender solo de la nube.", "Configurar"),
    ]):
        x = sw + 50 + i * 370
        _rrect(d, (x, 160, x + 340, 520), 20, fill=WHITE, outline=LINE)
        d.ellipse((x + 120, 210, x + 220, 310), fill=(255, 243, 224))
        d.rectangle((x + 145, 245, x + 195, 285), fill=ORANGE)
        d.text((x + 36, 350), title, font=_font(18, "bold"), fill=INK)
        # wrap desc manually
        words = desc.split()
        line, yy = "", 390
        for w in words:
            trial = (line + " " + w).strip()
            if len(trial) < 28:
                line = trial
            else:
                d.text((x + 36, yy), line, font=_font(12, "med"), fill=MUTED)
                yy += 22
                line = w
        if line:
            d.text((x + 36, yy), line, font=_font(12, "med"), fill=MUTED)
        _rrect(d, (x + 36, 460, x + 300, 505), 12, fill=ORANGE)
        d.text((x + 90, 472), cta, font=_font(13, "semi"), fill=WHITE)
    return _save(img, "ui_backup.png")


def draw_cc() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cli")
    _topbar(d, sw, 0, W - sw, "Cuenta corriente", "Cuentas por cobrar")
    _card(d, (sw + 36, 100, sw + 300, 210), "Total a cobrar", "$ 820.400", "27 clientes", RED)
    _card(d, (sw + 330, 100, sw + 594, 210), "Vencido", "$ 194.000", "8 clientes", ORANGE)
    _card(d, (sw + 624, 100, sw + 888, 210), "Este mes", "$ 312.000", "Cobrado", GREEN)
    rows = [
        ["Comercial Norte SA", "R-1042 + ventas", "$ 245.000", "14/07", ("Pendiente", ORANGE)],
        ["Textil Andina", "R-1038", "$ 89.400", "12/07", ("Parcial", BLUE)],
        ["Boutique Luna", "R-1040", "$ 12.300", "13/07", ("Pendiente", ORANGE)],
        ["Retail Pampa", "Fact. 881", "$ 67.800", "10/07", ("Vencido", RED)],
    ]
    _table(d, sw + 36, 240, W - sw - 72,
           ["Cliente", "Origen", "Saldo", "Último mov.", "Estado"],
           rows, [280, 240, 160, 160, 160])
    return _save(img, "ui_cc.png")


def draw_login() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (11, 11, 11, 255))
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((-220, -120, 680, 760), fill=(245, 124, 0, 45))
    od.ellipse((850, 180, 1600, 1050), fill=(245, 124, 0, 30))
    img = Image.alpha_composite(img, overlay)
    d = ImageDraw.Draw(img)
    cx, cy = W // 2, H // 2
    _rrect(d, (cx - 240, cy - 250, cx + 240, cy + 250), 28, fill=WHITE)
    _logo_mark(d, cx - 28, cy - 210, 56)
    d.text((cx - 100, cy - 130), "Tata.Manager", font=_font(22, "bold"), fill=INK)
    d.text((cx - 130, cy - 98), "Ingresá a tu espacio de trabajo", font=_font(12, "med"), fill=MUTED)
    d.text((cx - 180, cy - 50), "Usuario", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (cx - 180, cy - 28, cx + 180, cy + 12), 12, fill=SOFT, outline=LINE)
    d.text((cx - 164, cy - 18), "admin", font=_font(13, "med"), fill=INK)
    d.text((cx - 180, cy + 36), "Contraseña", font=_font(11, "med"), fill=MUTED)
    _rrect(d, (cx - 180, cy + 58, cx + 180, cy + 98), 12, fill=SOFT, outline=LINE)
    d.text((cx - 164, cy + 68), "••••••••", font=_font(13, "med"), fill=INK)
    _rrect(d, (cx - 180, cy + 130, cx + 180, cy + 180), 14, fill=ORANGE)
    d.text((cx - 48, cy + 145), "Ingresar", font=_font(15, "semi"), fill=WHITE)
    d.text((cx - 100, cy + 205), "Firebase sync activo", font=_font(11, "med"), fill=GREEN)
    return _save(img, "ui_login.png")


def draw_firebase_panel() -> Path:
    W, H = 1400, 860
    img = Image.new("RGBA", (W, H), (*SOFT, 255))
    d = ImageDraw.Draw(img)
    sw = _sidebar(d, H, "cfg")
    _topbar(d, sw, 0, W - sw, "Firebase", "Sincronización en la nube")
    _rrect(d, (sw + 40, 120, W - 40, 280), 18, fill=BLACK)
    d.text((sw + 70, 155), "Estado de sincronización", font=_font(16, "semi"), fill=WHITE)
    d.text((sw + 70, 195), "Conectado · tenant tata_stock", font=_font(22, "bold"), fill=ORANGE)
    d.text((sw + 70, 235), "Última sync · hace 12 segundos", font=_font(13, "med"), fill=(209, 213, 219))
    items = [
        ("Productos", "OK", GREEN), ("Clientes", "OK", GREEN),
        ("Remitos", "OK", GREEN), ("Fotos", "Sync…", ORANGE),
        ("PDFs", "OK", GREEN), ("Chat", "OK", GREEN),
    ]
    for i, (t, st, c) in enumerate(items):
        col, row = i % 3, i // 3
        x = sw + 40 + col * 360
        y = 320 + row * 160
        _rrect(d, (x, y, x + 330, y + 130), 16, fill=WHITE, outline=LINE)
        d.text((x + 28, y + 35), t, font=_font(16, "semi"), fill=INK)
        d.ellipse((x + 28, y + 80, x + 48, y + 100), fill=c)
        d.text((x + 60, y + 80), st, font=_font(13, "med"), fill=c)
    return _save(img, "ui_firebase.png")


def draw_module_icons() -> dict[str, Path]:
    """Iconos por módulo, Fluent-like, no genéricos repetidos."""
    out = {}
    specs = {
        "ico_productos": lambda d: (
            d.rounded_rectangle((40, 50, 160, 170), 20, fill=ORANGE),
            d.rectangle((60, 80, 140, 95), fill=WHITE),
            d.rectangle((60, 110, 120, 125), fill=WHITE),
        ),
        "ico_clientes": lambda d: (
            d.ellipse((70, 40, 130, 100), fill=ORANGE),
            d.ellipse((40, 110, 160, 190), fill=ORANGE_L),
        ),
        "ico_ventas": lambda d: (
            d.polygon([(40, 160), (80, 70), (110, 110), (160, 40), (160, 160)], fill=ORANGE),
        ),
        "ico_remitos": lambda d: (
            d.rounded_rectangle((50, 40, 150, 180), 12, fill=ORANGE),
            d.rectangle((70, 70, 130, 80), fill=WHITE),
            d.rectangle((70, 95, 130, 105), fill=WHITE),
            d.rectangle((70, 120, 110, 130), fill=WHITE),
        ),
        "ico_stock": lambda d: (
            d.polygon([(100, 40), (160, 70), (100, 100), (40, 70)], fill=ORANGE),
            d.polygon([(40, 70), (100, 100), (100, 170), (40, 140)], fill=ORANGE_D),
            d.polygon([(100, 100), (160, 70), (160, 140), (100, 170)], fill=ORANGE_L),
        ),
        "ico_compras": lambda d: (
            d.ellipse((45, 45, 155, 155), outline=ORANGE, width=12),
            d.polygon([(100, 70), (100, 130), (140, 100)], fill=ORANGE),
        ),
        "ico_usuarios": lambda d: (
            d.ellipse((75, 35, 125, 85), fill=ORANGE),
            d.ellipse((50, 100, 150, 180), fill=ORANGE),
            d.ellipse((35, 70, 65, 100), fill=ORANGE_L),
            d.ellipse((135, 70, 165, 100), fill=ORANGE_L),
        ),
        "ico_config": lambda d: (
            d.ellipse((50, 50, 150, 150), outline=ORANGE, width=14),
            d.ellipse((80, 80, 120, 120), fill=ORANGE),
            *[d.rectangle((95, 30 + i * 0, 105, 50), fill=ORANGE) for i in range(1)],
        ),
        "ico_firebase": lambda d: (
            d.polygon([(100, 40), (150, 160), (100, 130), (50, 160)], fill=ORANGE),
        ),
        "ico_chat": lambda d: (
            d.rounded_rectangle((40, 50, 160, 140), 24, fill=ORANGE),
            d.polygon([(70, 140), (90, 140), (60, 175)], fill=ORANGE),
        ),
        "ico_auditoria": lambda d: (
            d.polygon([(100, 35), (160, 70), (160, 130), (100, 175), (40, 130), (40, 70)], fill=ORANGE),
            d.line((75, 105, 95, 125), fill=WHITE, width=6),
            d.line((95, 125, 130, 80), fill=WHITE, width=6),
        ),
        "ico_pdf": lambda d: (
            d.rounded_rectangle((55, 35, 145, 175), 10, fill=ORANGE),
            d.text((72, 85), "PDF", font=_font(22, "bold"), fill=WHITE),
        ),
        "ico_backup": lambda d: (
            d.rounded_rectangle((55, 60, 145, 160), 16, fill=ORANGE),
            d.arc((70, 40, 130, 100), 200, 340, fill=WHITE, width=8),
        ),
        "ico_reportes": lambda d: (
            d.rectangle((50, 120, 80, 170), fill=ORANGE),
            d.rectangle((95, 90, 125, 170), fill=ORANGE_L),
            d.rectangle((140, 55, 170, 170), fill=ORANGE_D),
        ),
        "ico_windows": lambda d: (
            d.rectangle((40, 40, 95, 95), fill=ORANGE),
            d.rectangle((105, 40, 160, 95), fill=ORANGE_L),
            d.rectangle((40, 105, 95, 160), fill=ORANGE_L),
            d.rectangle((105, 105, 160, 160), fill=ORANGE),
        ),
        "ico_android": lambda d: (
            d.ellipse((55, 55, 145, 145), fill=ORANGE),
            d.rectangle((85, 35, 115, 55), fill=ORANGE),
            d.line((75, 45, 55, 30), fill=ORANGE, width=4),
            d.line((125, 45, 145, 30), fill=ORANGE, width=4),
        ),
        "ico_sync": lambda d: (
            d.arc((40, 40, 160, 160), 30, 200, fill=ORANGE, width=12),
            d.arc((40, 40, 160, 160), 210, 20, fill=ORANGE_L, width=12),
            d.polygon([(150, 50), (170, 70), (140, 80)], fill=ORANGE),
        ),
    }
    for key, painter in specs.items():
        im = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        painter(d)
        path = ASSETS / f"{key}.png"
        im.save(path)
        out[key] = path
    return out


def draw_infographic(name: str, labels: list[str], accent_idx: int = -1) -> Path:
    n = len(labels)
    W = max(1100, n * 150)
    H = 280
    img = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    gap = W // n
    for i, lab in enumerate(labels):
        x = 40 + i * gap
        fill = ORANGE if i == accent_idx or (accent_idx < 0 and i == n // 2) else WHITE
        tc = WHITE if fill == ORANGE else INK
        _rrect(d, (x, 90, x + 120, 170), 16, fill=fill, outline=ORANGE, width=3)
        # centered-ish label
        d.text((x + 12, 118), lab[:12], font=_font(12, "semi"), fill=tc)
        if i < n - 1:
            d.line((x + 120, 130, x + gap - 10, 130), fill=ORANGE, width=4)
            d.polygon([(x + gap - 10, 130), (x + gap - 22, 122), (x + gap - 22, 138)], fill=ORANGE)
    path = ASSETS / f"info_{name}.png"
    img.convert("RGB").save(path, quality=93)
    return path


def draw_hero_devices() -> Path:
    """Compone UI sobre foto de devices o genera render propio."""
    blank = PHOTOS / "photo_devices_blank.png"
    dash = Image.open(ASSETS / "ui_dashboard.png").convert("RGBA")
    if blank.exists():
        base = Image.open(blank).convert("RGBA")
        # darken slightly and overlay screens approximately
        base = ImageEnhance.Brightness(base).enhance(0.85)
        W, H = base.size
        # Approximate screen regions for composite (marketing style)
        screens = [
            # laptop region
            (int(W * 0.10), int(H * 0.28), int(W * 0.52), int(H * 0.62)),
            # tablet
            (int(W * 0.55), int(H * 0.18), int(W * 0.78), int(H * 0.78)),
            # phone
            (int(W * 0.80), int(H * 0.30), int(W * 0.93), int(H * 0.78)),
        ]
        for box in screens:
            x0, y0, x1, y1 = box
            sw, sh = max(1, x1 - x0), max(1, y1 - y0)
            fitted = dash.resize((sw, sh), Image.Resampling.LANCZOS)
            mask = Image.new("L", (sw, sh), 0)
            ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), 12, fill=255)
            base.paste(fitted, (x0, y0), mask)
        # orange glow accent
        glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse((int(W*0.3), int(H*0.7), int(W*0.7), int(H*1.1)), fill=(245, 124, 0, 40))
        glow = glow.filter(ImageFilter.GaussianBlur(40))
        base = Image.alpha_composite(base, glow)
        path = ASSETS / "hero_devices.png"
        base.convert("RGB").save(path, quality=95)
        return path

    # fallback render
    W, H = 1600, 1000
    img = Image.new("RGBA", (W, H), (15, 15, 17, 255))
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse((-100, 200, 700, 1100), fill=(245, 124, 0, 35))
    od.ellipse((900, -100, 1800, 700), fill=(245, 124, 0, 25))
    img = Image.alpha_composite(img, overlay)
    d = ImageDraw.Draw(img)

    def frame(box, bezel=14, radius=22):
        nonlocal img
        x0, y0, x1, y1 = box
        sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(sh)
        sd.rounded_rectangle((x0 + 10, y0 + 18, x1 + 10, y1 + 22), radius + 4, fill=(0, 0, 0, 80))
        sh = sh.filter(ImageFilter.GaussianBlur(20))
        img = Image.alpha_composite(img, sh)
        d = ImageDraw.Draw(img)
        _rrect(d, box, radius, fill=(28, 28, 30))
        sx0, sy0, sx1, sy1 = x0 + bezel, y0 + bezel, x1 - bezel, y1 - bezel
        fitted = dash.resize((sx1 - sx0, sy1 - sy0), Image.Resampling.LANCZOS)
        mask = Image.new("L", fitted.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, fitted.width - 1, fitted.height - 1), 10, fill=255)
        img.paste(fitted, (sx0, sy0), mask)

    frame((60, 140, 980, 700), 18, 22)
    d = ImageDraw.Draw(img)
    d.polygon([(40, 700), (1000, 700), (1080, 770), (0, 770)], fill=(40, 40, 42))
    frame((1040, 100, 1400, 700), 14, 28)
    frame((1420, 200, 1570, 720), 10, 30)
    path = ASSETS / "hero_devices.png"
    img.convert("RGB").save(path, quality=95)
    return path


def draw_qr_placeholder() -> Path:
    """QR estilizado hacia GitHub del repo."""
    try:
        import qrcode
        qr = qrcode.QRCode(border=1, box_size=8)
        qr.add_data("https://github.com/arcuriciro-gif/sistema_nuevo")
        qr.make(fit=True)
        img = qr.make_image(fill_color="#0B0B0B", back_color="#FFFFFF").convert("RGB")
        # orange frame
        framed = Image.new("RGB", (img.width + 40, img.height + 40), ORANGE)
        framed.paste(img, (20, 20))
        path = ASSETS / "qr_github.png"
        framed.save(path)
        return path
    except Exception:
        img = Image.new("RGB", (280, 280), WHITE)
        d = ImageDraw.Draw(img)
        _rrect(d, (10, 10, 270, 270), 16, outline=ORANGE, width=6)
        # fake matrix
        for i in range(8):
            for j in range(8):
                if (i + j) % 2 == 0:
                    d.rectangle((40 + i * 25, 40 + j * 25, 60 + i * 25, 60 + j * 25), fill=BLACK)
        path = ASSETS / "qr_github.png"
        img.save(path)
        return path


def generate_all_assets() -> dict[str, Path]:
    ASSETS.mkdir(parents=True, exist_ok=True)
    ZOOMS.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    paths["login"] = draw_login()
    paths["dashboard"] = draw_dashboard()
    paths["dashboard_ann"] = draw_dashboard_annotated()
    paths["productos"] = draw_productos()
    paths["productos_ann"] = draw_productos_annotated()
    paths["producto_nuevo"] = draw_producto_form("nuevo")
    paths["producto_editar"] = draw_producto_form("editar")
    paths["zoom_nuevo"] = draw_zoom_button_nuevo()
    paths["zoom_guardar"] = draw_zoom_guardar()
    paths["clientes"] = draw_clientes()
    paths["cliente_ficha"] = draw_cliente_ficha()
    paths["ventas"] = draw_ventas()
    paths["ventas_ann"] = draw_ventas_annotated()
    paths["remitos"] = draw_remitos()
    paths["compras"] = draw_compras()
    paths["stock"] = draw_stock()
    paths["usuarios"] = draw_usuarios()
    paths["roles"] = draw_roles()
    paths["permisos"] = draw_permisos()
    paths["reportes"] = draw_reportes()
    paths["pdfs"] = draw_pdfs()
    paths["config"] = draw_config()
    paths["chat"] = draw_chat()
    paths["auditoria"] = draw_auditoria()
    paths["backup"] = draw_backup()
    paths["cc"] = draw_cc()
    paths["firebase"] = draw_firebase_panel()
    paths["hero"] = draw_hero_devices()
    paths["qr"] = draw_qr_placeholder()
    paths.update(draw_module_icons())
    paths["info_venta"] = draw_infographic(
        "venta",
        ["Cliente", "Venta", "Remito", "Stock", "CC", "PDF", "WhatsApp", "Hist."],
        accent_idx=2,
    )
    paths["info_compra"] = draw_infographic(
        "compra",
        ["Proveedor", "Compra", "Costo", "Stock", "Firebase", "PC", "Celular", "Tablet"],
        accent_idx=4,
    )
    paths["info_login"] = draw_infographic(
        "login",
        ["Usuario", "Login", "Firebase", "Sync", "Todos"],
        accent_idx=2,
    )
    # photos
    for p in PHOTOS.glob("*.png"):
        paths[f"photo_{p.stem.replace('photo_', '')}"] = p
        paths[p.stem] = p
    return paths


if __name__ == "__main__":
    generate_all_assets()
    print("ok", len(list(ASSETS.rglob('*.png'))))
