#!/usr/bin/env python3
"""Generador del Manual Profesional Tata.Manager — pieza editorial premium."""

from __future__ import annotations

import math
from pathlib import Path

from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

from design import (
    ASSETS,
    OUTPUT,
    PAGE_W,
    PAGE_H,
    MARGIN_X,
    MARGIN_TOP,
    MARGIN_BOTTOM,
    CONTENT_W,
    ORANGE,
    ORANGE_DEEP,
    ORANGE_SOFT,
    ORANGE_MID,
    BLACK,
    INK,
    MUTED,
    LINE,
    SOFT,
    SOFT2,
    WHITE,
    SUCCESS,
    WARN,
    DANGER,
    INFO,
    VERSION,
    DATE_STR,
    PRODUCT,
    SUBTITLE,
    BRAND,
    register_fonts,
    chapter_meta,
)
from mockups import generate_all_assets


class Manual:
    def __init__(self):
        register_fonts()
        ASSETS.mkdir(parents=True, exist_ok=True)
        self.assets = generate_all_assets()
        self.path = OUTPUT
        self.c = canvas.Canvas(str(self.path), pagesize=(PAGE_W, PAGE_H))
        self.page = 0
        self.chapter = ""
        self.toc_entries: list[tuple[str, str, int]] = []

    # ── primitives ─────────────────────────────────────────────
    def new_page(self, chapter: str | None = None, numbered: bool = True):
        if self.page > 0:
            self.c.showPage()
        self.page += 1
        if chapter is not None:
            self.chapter = chapter
        if numbered and self.page > 1:
            self.draw_header_footer()

    def draw_header_footer(self):
        c = self.c
        # header
        c.setStrokeColor(LINE)
        c.setLineWidth(0.6)
        c.line(MARGIN_X, PAGE_H - 12 * mm, PAGE_W - MARGIN_X, PAGE_H - 12 * mm)
        c.setFillColor(MUTED)
        c.setFont("Outfit-Med", 8)
        c.drawString(MARGIN_X, PAGE_H - 10 * mm, self.chapter.upper() if self.chapter else PRODUCT)
        c.setFillColor(ORANGE)
        c.drawRightString(PAGE_W - MARGIN_X, PAGE_H - 10 * mm, PRODUCT)

        # footer
        c.setStrokeColor(LINE)
        c.line(MARGIN_X, 12 * mm, PAGE_W - MARGIN_X, 12 * mm)
        # mini logo
        c.setFillColor(ORANGE)
        c.roundRect(MARGIN_X, 5.5 * mm, 5 * mm, 5 * mm, 1.2 * mm, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 7)
        c.drawCentredString(MARGIN_X + 2.5 * mm, 6.8 * mm, "T")
        c.setFillColor(MUTED)
        c.setFont("Outfit-Med", 8)
        c.drawString(MARGIN_X + 7 * mm, 6.8 * mm, f"{PRODUCT}  ·  v{VERSION}  ·  {DATE_STR}")
        c.setFillColor(INK)
        c.setFont("Outfit-Semi", 9)
        c.drawRightString(PAGE_W - MARGIN_X, 6.8 * mm, f"{self.page:02d}")

    def h1(self, text, y):
        self.c.setFillColor(INK)
        self.c.setFont("Outfit-Bold", 26)
        self.c.drawString(MARGIN_X, y, text)
        return y - 12 * mm

    def h2(self, text, y):
        self.c.setFillColor(INK)
        self.c.setFont("Outfit-Semi", 16)
        self.c.drawString(MARGIN_X, y, text)
        # accent underline
        self.c.setStrokeColor(ORANGE)
        self.c.setLineWidth(2)
        self.c.line(MARGIN_X, y - 3 * mm, MARGIN_X + 18 * mm, y - 3 * mm)
        return y - 10 * mm

    def body(self, text, y, size=10.5, leading=15, color=INK, width=None):
        width = width or CONTENT_W
        self.c.setFillColor(color)
        self.c.setFont("Outfit", size)
        for line in self.wrap(text, width, "Outfit", size):
            if y < MARGIN_BOTTOM + 18 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
            self.c.drawString(MARGIN_X, y, line)
            y -= leading
        return y

    def wrap(self, text, width, font, size):
        words = text.split()
        lines, cur = [], ""
        for w in words:
            trial = (cur + " " + w).strip()
            if self.c.stringWidth(trial, font, size) <= width:
                cur = trial
            else:
                if cur:
                    lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
        return lines

    def bullets(self, items, y, accent=True):
        self.c.setFont("Outfit", 10.5)
        for item in items:
            if y < MARGIN_BOTTOM + 18 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
            if accent:
                self.c.setFillColor(ORANGE)
                self.c.circle(MARGIN_X + 2.2 * mm, y + 1.2 * mm, 1.6 * mm, fill=1, stroke=0)
            self.c.setFillColor(INK)
            x = MARGIN_X + 7 * mm
            for i, line in enumerate(self.wrap(item, CONTENT_W - 8 * mm, "Outfit", 10.5)):
                self.c.drawString(x if i == 0 else x, y, line)
                y -= 5.2 * mm
            y -= 1.5 * mm
        return y

    def callout(self, y, title, text, kind="tip"):
        palette = {
            "tip": (ORANGE_SOFT, ORANGE, "Consejo"),
            "warn": (SOFT2, WARN, "Atención"),
            "info": (SOFT, INFO, "Nota"),
            "danger": (SOFT2, DANGER, "Importante"),
        }
        bg, accent, label = palette.get(kind, palette["tip"])
        lines = self.wrap(text, CONTENT_W - 16 * mm, "Outfit", 10)
        h = 14 * mm + len(lines) * 4.8 * mm
        if y - h < MARGIN_BOTTOM + 14 * mm:
            self.new_page()
            y = PAGE_H - MARGIN_TOP - 8 * mm
        self.c.setFillColor(bg)
        self.c.roundRect(MARGIN_X, y - h, CONTENT_W, h, 4 * mm, fill=1, stroke=0)
        self.c.setFillColor(accent)
        self.c.rect(MARGIN_X, y - h, 1.8 * mm, h, fill=1, stroke=0)
        self.c.setFont("Outfit-Semi", 9)
        self.c.drawString(MARGIN_X + 6 * mm, y - 6 * mm, (title or label).upper())
        self.c.setFillColor(INK)
        self.c.setFont("Outfit", 10)
        ty = y - 12 * mm
        for line in lines:
            self.c.drawString(MARGIN_X + 6 * mm, ty, line)
            ty -= 4.8 * mm
        return y - h - 6 * mm

    def image(self, key, y, max_h=78 * mm, caption=None):
        path = self.assets.get(key) if isinstance(key, str) else key
        if isinstance(path, str):
            path = self.assets[path]
        if not Path(path).exists():
            return y
        ir = ImageReader(str(path))
        iw, ih = ir.getSize()
        max_w = CONTENT_W
        scale = min(max_w / iw, max_h / ih)
        w, h = iw * scale, ih * scale
        if y - h < MARGIN_BOTTOM + 20 * mm:
            self.new_page()
            y = PAGE_H - MARGIN_TOP - 8 * mm
        x = MARGIN_X + (CONTENT_W - w) / 2
        # soft frame
        self.c.setFillColor(SOFT)
        self.c.roundRect(x - 2 * mm, y - h - 2 * mm, w + 4 * mm, h + 4 * mm, 3 * mm, fill=1, stroke=0)
        self.c.drawImage(ir, x, y - h, width=w, height=h, mask="auto")
        y = y - h - 4 * mm
        if caption:
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit-Med", 8)
            self.c.drawCentredString(PAGE_W / 2, y - 3 * mm, caption)
            y -= 7 * mm
        return y - 4 * mm

    def chapter_opener(self, num: str, title: str, blurb: str, illu_key: str | None = None):
        # Portadilla full-bleed: sin chrome de encabezado/pie.
        self.new_page(chapter=title, numbered=False)
        self.toc_entries.append((num, title, self.page))
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        # orange curve
        c.setFillColor(ORANGE)
        p = c.beginPath()
        p.moveTo(0, PAGE_H * 0.55)
        p.curveTo(PAGE_W * 0.35, PAGE_H * 0.75, PAGE_W * 0.55, PAGE_H * 0.35, PAGE_W, PAGE_H * 0.5)
        p.lineTo(PAGE_W, 0)
        p.lineTo(0, 0)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
        # translucent white card
        c.setFillColor(WHITE)
        c.roundRect(MARGIN_X, 42 * mm, CONTENT_W, 95 * mm, 6 * mm, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Black", 11)
        c.drawString(MARGIN_X + 10 * mm, 120 * mm, f"CAPÍTULO {num}")
        c.setFillColor(INK)
        c.setFont("Outfit-Bold", 32)
        c.drawString(MARGIN_X + 10 * mm, 100 * mm, title)
        c.setFillColor(MUTED)
        c.setFont("Outfit", 11)
        y = 88 * mm
        for line in self.wrap(blurb, CONTENT_W - 24 * mm, "Outfit", 11):
            c.drawString(MARGIN_X + 10 * mm, y, line)
            y -= 5.5 * mm
        if illu_key and illu_key in self.assets:
            ir = ImageReader(str(self.assets[illu_key]))
            c.drawImage(ir, PAGE_W - 70 * mm, PAGE_H - 95 * mm, width=50 * mm, height=38 * mm, mask="auto")
        # Número de página discreto sobre la portadilla
        c.setFillColor(WHITE)
        c.setFont("Outfit-Semi", 9)
        c.drawRightString(PAGE_W - MARGIN_X, 10 * mm, f"{self.page:02d}")
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Med", 8)
        c.drawString(MARGIN_X, 10 * mm, PRODUCT)

    def kpi_row(self, y, items):
        n = len(items)
        gap = 4 * mm
        w = (CONTENT_W - gap * (n - 1)) / n
        for i, (label, value) in enumerate(items):
            x = MARGIN_X + i * (w + gap)
            self.c.setFillColor(SOFT)
            self.c.roundRect(x, y - 18 * mm, w, 22 * mm, 3 * mm, fill=1, stroke=0)
            self.c.setFillColor(ORANGE)
            self.c.rect(x, y - 18 * mm, 1.5 * mm, 22 * mm, fill=1, stroke=0)
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit-Med", 8)
            self.c.drawString(x + 4 * mm, y - 2 * mm, label.upper())
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Bold", 12)
            self.c.drawString(x + 4 * mm, y - 10 * mm, value)
        return y - 26 * mm

    def two_col_cards(self, y, cards):
        gap = 5 * mm
        w = (CONTENT_W - gap) / 2
        for i, (title, text) in enumerate(cards):
            col = i % 2
            row = i // 2
            x = MARGIN_X + col * (w + gap)
            yy = y - row * 32 * mm
            if yy - 28 * mm < MARGIN_BOTTOM + 14 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
                return self.two_col_cards(y, cards[i:])
            self.c.setFillColor(WHITE)
            self.c.setStrokeColor(LINE)
            self.c.setLineWidth(0.8)
            self.c.roundRect(x, yy - 26 * mm, w, 28 * mm, 3.5 * mm, fill=1, stroke=1)
            self.c.setFillColor(ORANGE)
            self.c.circle(x + 5 * mm, yy - 5 * mm, 2 * mm, fill=1, stroke=0)
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Semi", 11)
            self.c.drawString(x + 10 * mm, yy - 6.5 * mm, title)
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit", 9)
            ty = yy - 13 * mm
            for line in self.wrap(text, w - 14 * mm, "Outfit", 9)[:3]:
                self.c.drawString(x + 6 * mm, ty, line)
                ty -= 4 * mm
        rows = math.ceil(len(cards) / 2)
        return y - rows * 32 * mm - 4 * mm

    def elegant_table(self, y, headers, rows, col_w=None):
        n = len(headers)
        col_w = col_w or [CONTENT_W / n] * n
        row_h = 8 * mm
        h = row_h * (len(rows) + 1)
        if y - h < MARGIN_BOTTOM + 14 * mm:
            self.new_page()
            y = PAGE_H - MARGIN_TOP - 8 * mm
        # header
        self.c.setFillColor(BLACK)
        self.c.roundRect(MARGIN_X, y - row_h, CONTENT_W, row_h, 2.5 * mm, fill=1, stroke=0)
        self.c.setFillColor(WHITE)
        self.c.setFont("Outfit-Semi", 8.5)
        x = MARGIN_X + 3 * mm
        for i, htxt in enumerate(headers):
            self.c.drawString(x, y - 5.5 * mm, htxt.upper())
            x += col_w[i]
        yy = y - row_h
        for ri, row in enumerate(rows):
            yy -= row_h
            self.c.setFillColor(SOFT if ri % 2 == 0 else WHITE)
            self.c.rect(MARGIN_X, yy, CONTENT_W, row_h, fill=1, stroke=0)
            self.c.setFillColor(INK)
            self.c.setFont("Outfit", 9)
            x = MARGIN_X + 3 * mm
            for i, cell in enumerate(row):
                self.c.drawString(x, yy + 2.8 * mm, str(cell))
                x += col_w[i]
        self.c.setStrokeColor(LINE)
        self.c.setLineWidth(0.6)
        self.c.roundRect(MARGIN_X, yy, CONTENT_W, y - yy, 2.5 * mm, fill=0, stroke=1)
        return yy - 6 * mm

    def steps(self, y, steps):
        for i, (title, text) in enumerate(steps, 1):
            need = 18 * mm
            if y - need < MARGIN_BOTTOM + 14 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
            self.c.setFillColor(ORANGE)
            self.c.circle(MARGIN_X + 4 * mm, y - 1 * mm, 4 * mm, fill=1, stroke=0)
            self.c.setFillColor(WHITE)
            self.c.setFont("Outfit-Bold", 10)
            self.c.drawCentredString(MARGIN_X + 4 * mm, y - 2.5 * mm, str(i))
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Semi", 11)
            self.c.drawString(MARGIN_X + 12 * mm, y - 1 * mm, title)
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit", 9.5)
            y -= 6 * mm
            for line in self.wrap(text, CONTENT_W - 14 * mm, "Outfit", 9.5):
                self.c.drawString(MARGIN_X + 12 * mm, y, line)
                y -= 4.4 * mm
            y -= 4 * mm
        return y

    # ── pages ──────────────────────────────────────────────────
    def cover(self):
        self.new_page(chapter="", numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        # soft orange curves
        c.setFillColor(ORANGE)
        p = c.beginPath()
        p.moveTo(0, PAGE_H)
        p.curveTo(PAGE_W * 0.2, PAGE_H * 0.85, PAGE_W * 0.5, PAGE_H, PAGE_W, PAGE_H * 0.78)
        p.lineTo(PAGE_W, PAGE_H)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
        p = c.beginPath()
        p.moveTo(0, 0)
        p.curveTo(PAGE_W * 0.4, PAGE_H * 0.15, PAGE_W * 0.7, 0, PAGE_W, PAGE_H * 0.22)
        p.lineTo(PAGE_W, 0)
        p.close()
        c.setFillColor(ORANGE_DEEP)
        c.drawPath(p, fill=1, stroke=0)

        # logo
        c.setFillColor(ORANGE)
        c.roundRect(MARGIN_X, PAGE_H - 38 * mm, 12 * mm, 12 * mm, 3 * mm, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 16)
        c.drawCentredString(MARGIN_X + 6 * mm, PAGE_H - 34 * mm, "T")
        c.setFont("Outfit-Bold", 18)
        c.setFillColor(WHITE)
        c.drawString(MARGIN_X + 16 * mm, PAGE_H - 33.5 * mm, PRODUCT)

        c.setFont("Outfit-Black", 42)
        c.drawString(MARGIN_X, PAGE_H - 62 * mm, "Manual")
        c.drawString(MARGIN_X, PAGE_H - 78 * mm, "Profesional")
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Med", 12)
        c.drawString(MARGIN_X, PAGE_H - 90 * mm, SUBTITLE.upper())

        # hero devices
        if "hero" in self.assets:
            ir = ImageReader(str(self.assets["hero"]))
            c.drawImage(ir, 8 * mm, 55 * mm, width=PAGE_W - 16 * mm, height=105 * mm, mask="auto", preserveAspectRatio=True, anchor="c")

        c.setFillColor(WHITE)
        c.setFont("Outfit-Med", 9)
        c.drawString(MARGIN_X, 28 * mm, f"Versión {VERSION}")
        c.drawString(MARGIN_X, 22 * mm, DATE_STR)
        c.setFont("Outfit-Semi", 10)
        c.drawRightString(PAGE_W - MARGIN_X, 25 * mm, BRAND)
        c.setStrokeColor(ORANGE)
        c.setLineWidth(1.2)
        c.line(PAGE_W - MARGIN_X - 28 * mm, 22 * mm, PAGE_W - MARGIN_X, 22 * mm)

    def inside_cover(self):
        self.new_page(chapter="Créditos", numbered=True)
        y = PAGE_H - MARGIN_TOP - 10 * mm
        y = self.h1("Una pieza de producto", y)
        y = self.body(
            "Este manual fue diseñado como documentación comercial de Tata.Manager: "
            "clara, visual y lista para acompañar la puesta en marcha del sistema en PC Windows y dispositivos Android.",
            y,
        )
        y -= 4 * mm
        y = self.kpi_row(
            y,
            [
                ("Producto", PRODUCT),
                ("Plataformas", "Windows · Android"),
                ("Versión", VERSION),
                ("Edición", DATE_STR),
            ],
        )
        y -= 2 * mm
        y = self.h2("Cómo leer este documento", y)
        y = self.bullets(
            [
                "Cada capítulo abre con una portada propia para ubicar el tema.",
                "Las capturas muestran la interfaz real del producto, con la misma shell en todas las páginas.",
                "Los recuadros naranja sintetizan consejos operativos; los de atención marcan riesgos comunes.",
                "Los diagramas resumen flujos entre módulos, dispositivos y documentos.",
            ],
            y,
        )
        y -= 4 * mm
        y = self.callout(
            y,
            "Alcance",
            "El contenido cubre el uso diario del negocio y la configuración esencial. No reemplaza la capacitación interna sobre precios, políticas de crédito o roles definidos por el administrador.",
            "info",
        )

    def toc(self):
        self.new_page(chapter="Índice", numbered=True)
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h1("Índice", y)
        y = self.body("Navegación rápida por capítulos, con iconografía y referencia de página.", y, size=10, color=MUTED)
        y -= 4 * mm
        # provisional page numbers from chapter_meta, updated later not easy offline - we'll use actual toc_entries filled as we go
        # For TOC we pre-render approximate then rebuild? Simpler: use planned numbers from design.chapter_meta
        for item in chapter_meta():
            if y < MARGIN_BOTTOM + 20 * mm:
                self.new_page(chapter="Índice")
                y = PAGE_H - MARGIN_TOP - 8 * mm
            # icon circle
            self.c.setFillColor(ORANGE_SOFT)
            self.c.circle(MARGIN_X + 4 * mm, y + 1.5 * mm, 4 * mm, fill=1, stroke=0)
            self.c.setFillColor(ORANGE)
            self.c.setFont("Outfit-Bold", 8)
            self.c.drawCentredString(MARGIN_X + 4 * mm, y, item["num"])
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Semi", 11)
            self.c.drawString(MARGIN_X + 12 * mm, y, item["title"])
            # dotted leader
            title_w = self.c.stringWidth(item["title"], "Outfit-Semi", 11)
            start = MARGIN_X + 14 * mm + title_w
            end = PAGE_W - MARGIN_X - 12 * mm
            self.c.setFillColor(LINE)
            x = start
            while x < end:
                self.c.circle(x, y + 1.2 * mm, 0.6, fill=1, stroke=0)
                x += 3.2 * mm
            self.c.setFillColor(ORANGE)
            self.c.setFont("Outfit-Bold", 11)
            self.c.drawRightString(PAGE_W - MARGIN_X, y, item["pages"])
            y -= 9 * mm

    def welcome(self):
        self.chapter_opener(
            "01",
            "Bienvenida",
            "Empezá por aquí. En pocos minutos vas a entender qué hace Tata.Manager y cómo se usa en el día a día del negocio.",
            "ill_users",
        )
        self.new_page(chapter="Bienvenida")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Qué vas a lograr", y)
        y = self.body(
            "Tata.Manager concentra catálogo, stock, ventas, remitos, clientes, compras, reportes y comunicación interna en una sola experiencia para Windows y Android.",
            y,
        )
        y -= 3 * mm
        y = self.two_col_cards(
            y,
            [
                ("Operar con claridad", "Dashboard, alertas de stock y cuenta corriente a un vistazo."),
                ("Vender más rápido", "Venta rápida, remitos y PDF listos para compartir."),
                ("Trabajar en equipo", "Usuarios, permisos, chat interno y auditoría."),
                ("Sincronizar equipos", "PC, celular y tablet con la misma información vía Firebase."),
            ],
        )
        y = self.callout(
            y,
            "Consejo",
            "Instalá la misma versión en todos los dispositivos del negocio. Así las pantallas, permisos y sincronización coinciden.",
            "tip",
        )
        y = self.image("login", y, max_h=70 * mm, caption="Pantalla de ingreso — Tata.Manager")

    def intro(self):
        self.chapter_opener(
            "02",
            "Introducción al sistema",
            "Un mapa del producto: módulos, plataformas y la lógica que conecta compras, stock, ventas y documentos.",
            "ill_report",
        )
        self.new_page(chapter="Introducción al sistema")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Módulos principales", y)
        y = self.elegant_table(
            y,
            ["Módulo", "Para qué sirve"],
            [
                ["Productos", "Catálogo, precios, fotos, categorías y listas"],
                ["Stock", "Entradas, salidas, alertas y kardex"],
                ["Ventas / Remitos", "Operación comercial y documentos de entrega"],
                ["Clientes / CC", "Agenda y saldos por cobrar"],
                ["Compras / Proveedores", "Ingreso de mercadería y costos"],
                ["Reportes / PDF", "Análisis e intercambio de documentos"],
                ["Usuarios / Permisos", "Accesos por rol"],
                ["Firebase / Sync", "Misma data en todos los equipos"],
            ],
            [45 * mm, CONTENT_W - 45 * mm],
        )
        y -= 2 * mm
        y = self.h2("Flujo comercial", y)
        y = self.image("diagram_venta", y, max_h=42 * mm, caption="De la consulta al envío por WhatsApp")
        y = self.body(
            "El sistema está pensado para que cada operación deje rastro: actualiza stock, archiva PDF y, con Firebase activo, replica el cambio en el resto de los dispositivos.",
            y,
        )

    def install(self):
        self.chapter_opener(
            "03",
            "Instalación",
            "Puesta en marcha en Android y Windows. Dos rutas simples, un mismo producto.",
            "ill_cloud",
        )
        self.new_page(chapter="Instalación")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Android", y)
        y = self.steps(
            y,
            [
                ("Obtener el APK", "Usá el archivo app-release.apk generado por el flujo de build del proyecto."),
                ("Permitir origen", "Si el teléfono lo pide, habilitá instalación desde ese origen de forma puntual."),
                ("Abrir e ingresar", "Instalá, abrí Tata.Manager e iniciá sesión con tu usuario."),
            ],
        )
        y = self.h2("Windows", y)
        y = self.steps(
            y,
            [
                ("Copiar la carpeta Release completa", "No alcanza con el .exe. Necesitás DLL y carpetas companion."),
                ("Ejecutar sistema_nuevo.exe", "Lanzá siempre desde esa carpeta, sin mover archivos sueltos."),
                ("Conservar la estructura", "Borrar bibliotecas o data folders rompe el arranque."),
            ],
        )
        y = self.callout(
            y,
            "Atención",
            "En una PC nueva, si el ejecutable no abre, casi siempre falta la carpeta Release completa. Volvé a copiar todo el directorio.",
            "warn",
        )

    def first_login(self):
        self.chapter_opener(
            "04",
            "Primer ingreso",
            "Usuario, contraseña y la diferencia crítica entre trabajar solo en local o conectado a Firebase.",
            "ill_shield",
        )
        self.new_page(chapter="Primer ingreso")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("login", y, max_h=62 * mm, caption="Login unificado para Windows y Android")
        y = self.h2("Pasos", y)
        y = self.steps(
            y,
            [
                ("Abrí la aplicación", "Vas a ver la pantalla de autenticación con branding Tata.Manager."),
                ("Ingresá credenciales", "Usuario y contraseña. El primer acceso suele ser admin."),
                ("Cambiá la clave si se solicita", "Mínimo 6 caracteres. Definí una clave segura y propia."),
                ("Verificá Firebase", "Con login cloud, ese dispositivo entra a la sincronización del negocio."),
            ],
        )
        y = self.callout(
            y,
            "Importante",
            "Sin login Firebase, el equipo trabaja solo con su base local y no ve los cambios de los demás dispositivos.",
            "danger",
        )

    def dashboard(self):
        self.chapter_opener(
            "05",
            "Dashboard",
            "El tablero operativo: stock, ventas, alertas y cuentas por cobrar en una sola vista.",
            "ill_report",
        )
        self.new_page(chapter="Dashboard")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("dashboard", y, max_h=78 * mm, caption="Dashboard — métricas y alertas")
        y = self.h2("Qué mirar cada mañana", y)
        y = self.bullets(
            [
                "Productos y valor de stock para salud de inventario.",
                "Tarjeta Sin stock: tocá para filtrar el listado exacto.",
                "Ventas del mes y tendencia.",
                "Cuentas por cobrar → Ver detalle para gestionar deudas.",
            ],
            y,
        )
        y = self.callout(y, "Consejo", "Usá el ícono de actualizar (flecha) después de cargas grandes o al cambiar de red.", "tip")

    def productos(self):
        self.chapter_opener(
            "06",
            "Productos",
            "El catálogo vivo del negocio: códigos, precios, fotos, listas y papelera.",
            "ill_stock",
        )
        self.new_page(chapter="Productos")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("productos", y, max_h=70 * mm, caption="Listado de productos con estados de stock")
        y = self.h2("Alta y edición", y)
        y = self.steps(
            y,
            [
                ("Nuevo producto", "Menú Productos → Nuevo."),
                ("Completá ficha", "Código, descripción, marca, stock, costo y precios."),
                ("Foto", "Opcional. Si estás logueado, se sincroniza a la nube."),
                ("Guardar", "El ítem queda disponible para ventas y remitos."),
            ],
        )
        self.new_page(chapter="Productos")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Búsqueda y filtros", y)
        y = self.bullets(
            [
                "Buscá por código, barras, nombre, marca o proveedor.",
                "Filtrá por marca / proveedor.",
                "Escaneá con el lector (ícono QR) en Android.",
            ],
            y,
        )
        y = self.h2("Operaciones clave", y)
        y = self.two_col_cards(
            y,
            [
                ("Alerta sin stock", "Desde Inicio/Dashboard tocá Sin stock para ver solo esos ítems."),
                ("Papelera", "Eliminar no borra del todo: recuperá desde Papelera."),
                ("Categorías", "Organizá el catálogo para encontrar más rápido."),
                ("Listas de precio", "Mayorista, minorista u otras listas concurrentes."),
            ],
        )

    def clientes(self):
        self.chapter_opener(
            "07",
            "Clientes",
            "Agenda comercial con historial, datos fiscales y acceso directo a la cuenta corriente.",
            "ill_users",
        )
        self.new_page(chapter="Clientes")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("clientes", y, max_h=70 * mm, caption="Fichas de clientes con saldo")
        y = self.h2("Alta de cliente", y)
        y = self.bullets(
            [
                "Nombre, teléfono, dirección, CUIT y datos de contacto.",
                "Historial de remitos, ventas y pagos desde la ficha.",
                "MOSTRADOR representa consumidor final en venta rápida.",
            ],
            y,
        )
        y = self.callout(y, "Nota", "Mantener CUIT y teléfono al día acelera el envío de PDF y el seguimiento de cobranza.", "info")

    def ventas(self):
        self.chapter_opener(
            "08",
            "Ventas y remitos",
            "El corazón operativo: venta rápida, remitos, documentos y el PDF que sale del mostrador a WhatsApp.",
            "ill_sales",
        )
        self.new_page(chapter="Ventas y remitos")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("ventas", y, max_h=68 * mm, caption="Venta rápida con carrito y total")
        y = self.h2("Venta rápida", y)
        y = self.steps(
            y,
            [
                ("Abrí Venta rápida", "Ideal para mostrador."),
                ("Agregá productos", "Búsqueda o escáner."),
                ("Confirmá", "Se genera remito a MOSTRADOR y baja stock."),
                ("PDF listo", "Queda en Archivo PDF para compartir después."),
            ],
        )
        self.new_page(chapter="Ventas y remitos")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("remitos", y, max_h=62 * mm, caption="Listado de remitos con estados de cobro")
        y = self.h2("Remitos", y)
        y = self.steps(
            y,
            [
                ("Nuevo remito", "Elegí cliente y productos."),
                ("Guardar", "Actualiza stock y deja el documento rastreable."),
                ("Imprimir o compartir", "PDF, impresión o envío."),
                ("Archivo por cliente", "El PDF se organiza automáticamente."),
            ],
        )
        y = self.image("diagram_venta", y, max_h=38 * mm)

    def cuenta_corriente(self):
        self.chapter_opener(
            "09",
            "Cuenta corriente",
            "Quién debe, cuánto y por qué documento. Cobranza con contexto.",
            "ill_report",
        )
        self.new_page(chapter="Cuenta corriente")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("cc", y, max_h=70 * mm, caption="Cuentas por cobrar — resumen y detalle")
        y = self.bullets(
            [
                "Incluye ventas y remitos sin cobrar.",
                "Desde el detalle del cliente ves origen del saldo.",
                "Priorizá vencidos y montos altos al arrancar el día.",
            ],
            y,
        )
        y = self.callout(y, "Consejo", "Cruzá la campanita de notificaciones con la lista de deudores para no dejar cobranzas olvidadas.", "tip")

    def compras(self):
        self.chapter_opener(
            "10",
            "Compras y proveedores",
            "Cuando llega mercadería: registrá la compra, actualizá costo y stock, y dejá el proveedor documentado.",
            "ill_stock",
        )
        self.new_page(chapter="Compras y proveedores")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("compras", y, max_h=68 * mm, caption="Alta de compra con ítems y costos")
        y = self.h2("Registrar una compra", y)
        y = self.steps(
            y,
            [
                ("Elegí proveedor", "O crealo si es nuevo."),
                ("Cargá ítems", "Cantidades y costos unitarios."),
                ("Confirmar", "Sube stock y actualiza costo."),
                ("Sync", "Con Firebase, el resto de equipos lo ve."),
            ],
        )
        y = self.callout(y, "Nota", "Proveedores se administran en su propio módulo: datos de contacto y frecuencia de compra.", "info")

    def stock(self):
        self.chapter_opener(
            "11",
            "Stock",
            "Movimientos, alertas y trazabilidad. El inventario como fuente de verdad.",
            "ill_stock",
        )
        self.new_page(chapter="Stock")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("stock", y, max_h=68 * mm, caption="Movimientos de stock con origen")
        y = self.two_col_cards(
            y,
            [
                ("Entradas", "Compras e ingresos manuales aumentan existencias."),
                ("Salidas", "Ventas y remitos descuentan en tiempo real."),
                ("Ajustes", "Inventario físico y correcciones controladas."),
                ("Alertas", "Stock bajo o cero, listos para reponer."),
            ],
        )
        y = self.callout(y, "Atención", "Un ajuste sin motivo documentado ensucia la auditoría. Registrá el origen siempre.", "warn")

    def usuarios(self):
        self.chapter_opener(
            "12",
            "Usuarios y permisos",
            "Quién entra, qué puede hacer y cómo se presenta ante el equipo.",
            "ill_users",
        )
        self.new_page(chapter="Usuarios y permisos")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("usuarios", y, max_h=60 * mm, caption="Equipo con roles y presencia")
        y = self.h2("Roles típicos", y)
        y = self.elegant_table(
            y,
            ["Rol", "Alcance"],
            [
                ["Admin", "Todo: usuarios, permisos, configuración, sync"],
                ["Encargado", "Operación ampliada según matriz"],
                ["Empleado", "Tareas diarias limitadas por permisos"],
            ],
            [35 * mm, CONTENT_W - 35 * mm],
        )
        self.new_page(chapter="Usuarios y permisos")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("permisos", y, max_h=62 * mm, caption="Matriz de permisos por módulo")
        y = self.h2("Alta de usuario (admin)", y)
        y = self.steps(
            y,
            [
                ("Usuarios → Nuevo", "Nombre, usuario, email real, rol y clave temporal."),
                ("Confirmación", "Si Firebase Auth está bien, llega el mail."),
                ("Mi perfil", "El usuario completa foto, nombre visible y nueva clave."),
            ],
        )
        y = self.callout(
            y,
            "Importante",
            "Usá un email real en el alta. Sin eso, no hay verificación ni recupero de acceso confiable.",
            "danger",
        )

    def reportes(self):
        self.chapter_opener(
            "13",
            "Reportes y PDFs",
            "De los números a la conversación con el cliente: reportes, archivo y compartido.",
            "ill_report",
        )
        self.new_page(chapter="Reportes y PDFs")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("reportes", y, max_h=60 * mm, caption="Centro de reportes exportables")
        y = self.h2("Archivo PDF", y)
        y = self.image("pdfs", y, max_h=55 * mm, caption="Carpetas por cliente listas para compartir")
        y = self.steps(
            y,
            [
                ("Generá en PC", "Remito o factura desde el escritorio."),
                ("Se archiva en la nube", "Organizado por cliente."),
                ("Abrí en el celular", "Módulo Archivo PDF."),
                ("Compartí", "WhatsApp, mail u otras apps."),
            ],
        )

    def config(self):
        self.chapter_opener(
            "14",
            "Configuración",
            "Identidad del negocio, plantilla de impresión y preferencias que definen la cara del sistema.",
            "ill_cloud",
        )
        self.new_page(chapter="Configuración")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("config", y, max_h=68 * mm, caption="Datos del negocio y preferencias")
        y = self.bullets(
            [
                "Nombre, logo, teléfono y email comercial.",
                "Plantilla de impresión: encabezado, pie, firma, sello y paleta.",
                "Opción transparente y modo impresión en blanco y negro.",
                "Vista previa PDF antes de guardar cambios de plantilla.",
            ],
            y,
        )
        y = self.callout(y, "Consejo", "Si imprimís mucho en B/N, activá esa opción para evitar encabezados con tinta de color innecesaria.", "tip")

    def firebase(self):
        self.chapter_opener(
            "15",
            "Firebase y sincronización",
            "La capa cloud que hace que PC, celular y tablet hablen el mismo idioma de negocio.",
            "ill_cloud",
        )
        self.new_page(chapter="Firebase y sincronización")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("diagram_sync", y, max_h=52 * mm, caption="Compra → stock → Firebase → dispositivos")
        y = self.h2("Requisitos", y)
        y = self.elegant_table(
            y,
            ["Requisito", "Detalle"],
            [
                ["Mismo negocio", "Mismo tenant Firebase (p. ej. tata_stock)"],
                ["Login", "Cada persona con su usuario en cada equipo"],
                ["Internet", "Necesaria para subir y bajar cambios"],
                ["Misma versión", "Funciones alineadas entre dispositivos"],
            ],
            [40 * mm, CONTENT_W - 40 * mm],
        )
        y -= 2 * mm
        y = self.h2("Qué se sincroniza", y)
        y = self.bullets(
            [
                "Productos, precios, stock y fotos.",
                "Clientes, proveedores, remitos, ventas y compras.",
                "Archivo PDF y comunicaciones internas.",
            ],
            y,
        )
        y = self.callout(
            y,
            "Atención",
            "Si un equipo nunca se logueó a Firebase, solo tiene su base local. Para clonar sin nube usá Respaldo (.db).",
            "warn",
        )
        self.new_page(chapter="Firebase y sincronización")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Email de alta (admin técnico)", y)
        y = self.steps(
            y,
            [
                ("Firebase Console", "Proyecto del negocio (ej. tata-stock)."),
                ("Authentication", "Activá Correo/Contraseña."),
                ("Templates", "Password reset y Email verification activos."),
                ("Alta con email real", "Evitá casillas inventadas."),
            ],
        )

    def backup(self):
        self.chapter_opener(
            "16",
            "Respaldo y auditoría",
            "Seguridad operativa: copias recuperables y registro de quién cambió qué.",
            "ill_shield",
        )
        self.new_page(chapter="Respaldo y auditoría")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Respaldo", y)
        y = self.steps(
            y,
            [
                ("Menú Respaldo", "Entrá al módulo dedicado."),
                ("Exportar", "Generá el archivo .db y guardalo en un lugar seguro."),
                ("Importar", "En otro equipo, importá ese archivo para clonar datos."),
            ],
        )
        y = self.callout(y, "Consejo", "Aunque uses Firebase, hacé respaldos periódicos. Son tu red de seguridad offline.", "tip")
        y = self.h2("Auditoría", y)
        y = self.image("auditoria", y, max_h=58 * mm, caption="Historial de acciones relevantes")
        y = self.body(
            "Altas, bajas, cambios de precio y movimientos de usuarios quedan registrados para trazabilidad interna.",
            y,
        )

    def chat(self):
        self.chapter_opener(
            "17",
            "Comunicación interna",
            "Chat entre usuarios, fichas compartidas y la campanita que mantiene al equipo alineado.",
            "ill_users",
        )
        self.new_page(chapter="Comunicación interna")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.image("chat", y, max_h=72 * mm, caption="Mensajería interna entre roles")
        y = self.bullets(
            [
                "Conversaciones 1:1 o de equipo.",
                "Compartí fichas de producto, remito u otros registros.",
                "Notificaciones en la barra superior para no perder mensajes.",
            ],
            y,
        )

    def faq(self):
        self.chapter_opener(
            "18",
            "Problemas frecuentes",
            "Diagnóstico rápido de los bloqueos más comunes en campo.",
            "ill_shield",
        )
        self.new_page(chapter="Problemas frecuentes")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.elegant_table(
            y,
            ["Síntoma", "Qué revisar"],
            [
                ["Celular no ve la PC", "Firebase login en ambos · misma versión · internet"],
                ["No llega mail de alta", "Email real · Auth/Templates · spam"],
                ["No abre el .exe", "Carpeta Release completa"],
                ["Fotos ausentes en otro equipo", "Subir foto estando logueado"],
                ["Sin stock y no aparecen", "Tocar tarjeta Sin stock"],
                ["Permiso denegado", "Matriz de permisos del rol"],
            ],
            [55 * mm, CONTENT_W - 55 * mm],
        )
        y -= 2 * mm
        y = self.callout(
            y,
            "Nota",
            "Si el problema es de reglas de negocio (quién vende a cuenta, descuentos), consultá al administrador del sistema antes de tocar configuración técnica.",
            "info",
        )

    def practices(self):
        self.chapter_opener(
            "19",
            "Buenas prácticas",
            "Una rutina simple que mantiene el sistema confiable y al equipo coordinado.",
            "ill_sales",
        )
        self.new_page(chapter="Buenas prácticas")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Flujo diario sugerido", y)
        y = self.steps(
            y,
            [
                ("Abrir y loguearse", "Con Firebase si trabajás en multi-dispositivo."),
                ("Revisar Inicio", "Alertas de sin stock y cuentas por cobrar."),
                ("Vender", "Venta rápida o remitos según el caso."),
                ("Cobrar", "Cuenta corriente al cierre de jornada."),
                ("Compartir PDF", "Desde Archivo PDF en el celular."),
                ("Cargar compras", "Cuando llega mercadería."),
                ("Respaldo", "De forma periódica, no solo en emergencias."),
            ],
        )
        y = self.callout(
            y,
            "Consejo",
            "Definí un responsable de catálogo y otro de cobranzas. Claridad de roles reduce errores de precio y saldos.",
            "tip",
        )

    def glossary(self):
        self.chapter_opener(
            "20",
            "Glosario y contacto",
            "Lenguaje común del producto y canales para resolver dudas.",
            "ill_report",
        )
        self.new_page(chapter="Glosario y contacto")
        y = PAGE_H - MARGIN_TOP - 8 * mm
        y = self.h2("Glosario", y)
        y = self.elegant_table(
            y,
            ["Término", "Significado"],
            [
                ["Remito", "Documento de entrega asociado a productos y cliente"],
                ["MOSTRADOR", "Cliente genérico de venta rápida"],
                ["Lista de precio", "Tabla de precios aplicable a un canal"],
                ["Tenant", "Espacio Firebase del negocio"],
                ["Papelera", "Productos eliminados recuperables"],
                ["Kardex", "Historial de movimientos de un producto"],
                ["CC", "Cuenta corriente / saldos por cobrar"],
                ["Sync", "Replicación de datos entre dispositivos"],
            ],
            [40 * mm, CONTENT_W - 40 * mm],
        )
        y -= 3 * mm
        y = self.h2("Contacto", y)
        y = self.body(
            "Dudas de negocio (precios, roles, crédito): administrador del sistema.",
            y,
        )
        y = self.body(
            "Temas técnicos de Firebase, instalación o builds: responsable del repositorio / PC de desarrollo.",
            y,
        )
        y -= 4 * mm
        y = self.callout(
            y,
            "Marca",
            f"{PRODUCT} · {SUBTITLE}. Documento oficial de uso. {BRAND} · {DATE_STR} · v{VERSION}.",
            "info",
        )

    def back_cover(self):
        self.new_page(chapter="", numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        p = c.beginPath()
        p.moveTo(0, PAGE_H * 0.35)
        p.curveTo(PAGE_W * 0.4, PAGE_H * 0.5, PAGE_W * 0.6, PAGE_H * 0.2, PAGE_W, PAGE_H * 0.4)
        p.lineTo(PAGE_W, 0)
        p.lineTo(0, 0)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 28)
        c.drawString(MARGIN_X, PAGE_H * 0.62, PRODUCT)
        c.setFont("Outfit-Med", 12)
        c.drawString(MARGIN_X, PAGE_H * 0.57, SUBTITLE)
        c.setFont("Outfit", 10)
        c.setFillColor(SOFT2)
        c.drawString(MARGIN_X, 40 * mm, f"Versión {VERSION}  ·  {DATE_STR}")
        c.drawString(MARGIN_X, 32 * mm, BRAND)
        c.setFillColor(ORANGE)
        c.roundRect(MARGIN_X, 18 * mm, 10 * mm, 10 * mm, 2.5 * mm, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 12)
        c.drawCentredString(MARGIN_X + 5 * mm, 21.5 * mm, "T")

    def build(self):
        self.cover()
        self.inside_cover()
        self.toc()
        self.welcome()
        self.intro()
        self.install()
        self.first_login()
        self.dashboard()
        self.productos()
        self.clientes()
        self.ventas()
        self.cuenta_corriente()
        self.compras()
        self.stock()
        self.usuarios()
        self.reportes()
        self.config()
        self.firebase()
        self.backup()
        self.chat()
        self.faq()
        self.practices()
        self.glossary()
        self.back_cover()
        self.c.save()
        return self.path, self.page


def main():
    manual = Manual()
    path, pages = manual.build()
    size_mb = path.stat().st_size / (1024 * 1024)
    print(f"OK {path} pages={pages} size_mb={size_mb:.2f}")
    # copy into assets/docs for app embedding
    app_docs = Path("/workspace/assets/docs")
    app_docs.mkdir(parents=True, exist_ok=True)
    dest = app_docs / "MANUAL_DE_USO.pdf"
    dest.write_bytes(path.read_bytes())
    print(f"COPIED {dest}")
    # also root copy for convenience
    root_pdf = Path("/workspace/MANUAL_DE_USO.pdf")
    root_pdf.write_bytes(path.read_bytes())
    print(f"COPIED {root_pdf}")


if __name__ == "__main__":
    main()
