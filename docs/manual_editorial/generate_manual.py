#!/usr/bin/env python3
"""Manual Profesional Tata.Manager — edición editorial / marketing (50–70 págs)."""

from __future__ import annotations

import math
from pathlib import Path

from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

from design import (
    ASSETS, OUTPUT, PAGE_W, PAGE_H, MARGIN_X, MARGIN_TOP, MARGIN_BOTTOM,
    CONTENT_W, ORANGE, ORANGE_DEEP, ORANGE_SOFT, BLACK, INK, MUTED, LINE,
    SOFT, SOFT2, WHITE, SUCCESS, WARN, DANGER, INFO, VERSION, DATE_STR,
    PRODUCT, SUBTITLE, BRAND, register_fonts,
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
        self.toc_plan: list[tuple[str, str]] = []  # filled after build? we set known

    # ── chrome ────────────────────────────────────────────────
    def new_page(self, chapter: str | None = None, numbered: bool = True, soft_bg=False):
        if self.page > 0:
            self.c.showPage()
        self.page += 1
        if chapter is not None:
            self.chapter = chapter
        if soft_bg:
            self.c.setFillColor(SOFT)
            self.c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        if numbered and self.page > 1:
            self.draw_chrome()

    def draw_chrome(self):
        c = self.c
        c.setStrokeColor(LINE)
        c.setLineWidth(0.7)
        c.line(MARGIN_X, PAGE_H - 11 * mm, PAGE_W - MARGIN_X, PAGE_H - 11 * mm)
        c.setFillColor(MUTED)
        c.setFont("Outfit-Med", 8)
        c.drawString(MARGIN_X, PAGE_H - 9 * mm, (self.chapter or PRODUCT).upper())
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Semi", 8)
        c.drawRightString(PAGE_W - MARGIN_X, PAGE_H - 9 * mm, PRODUCT)

        c.line(MARGIN_X, 12 * mm, PAGE_W - MARGIN_X, 12 * mm)
        c.setFillColor(ORANGE)
        c.roundRect(MARGIN_X, 5.2 * mm, 5.2 * mm, 5.2 * mm, 1.2 * mm, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 7)
        c.drawCentredString(MARGIN_X + 2.6 * mm, 6.5 * mm, "T")
        c.setFillColor(MUTED)
        c.setFont("Outfit-Med", 8)
        c.drawString(MARGIN_X + 7.5 * mm, 6.5 * mm, f"{PRODUCT}  ·  v{VERSION}  ·  {DATE_STR}")
        c.setFillColor(INK)
        c.setFont("Outfit-Semi", 9)
        c.drawRightString(PAGE_W - MARGIN_X, 6.5 * mm, f"{self.page:02d}")

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

    def body(self, text, y, size=10.5, leading=15, color=INK, width=None, x=None):
        width = width or CONTENT_W
        x = x or MARGIN_X
        self.c.setFillColor(color)
        self.c.setFont("Outfit", size)
        for line in self.wrap(text, width, "Outfit", size):
            if y < MARGIN_BOTTOM + 16 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
            self.c.drawString(x, y, line)
            y -= leading
        return y

    def h2(self, text, y):
        self.c.setFillColor(INK)
        self.c.setFont("Outfit-Bold", 18)
        self.c.drawString(MARGIN_X, y, text)
        self.c.setStrokeColor(ORANGE)
        self.c.setLineWidth(2.5)
        self.c.line(MARGIN_X, y - 3.2 * mm, MARGIN_X + 16 * mm, y - 3.2 * mm)
        return y - 10 * mm

    def bullets(self, items, y):
        for item in items:
            if y < MARGIN_BOTTOM + 16 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
            self.c.setFillColor(ORANGE)
            self.c.circle(MARGIN_X + 2.5 * mm, y + 1.2 * mm, 1.8 * mm, fill=1, stroke=0)
            self.c.setFillColor(INK)
            self.c.setFont("Outfit", 10.5)
            for i, line in enumerate(self.wrap(item, CONTENT_W - 9 * mm, "Outfit", 10.5)):
                self.c.drawString(MARGIN_X + 8 * mm, y, line)
                y -= 5 * mm
            y -= 1.8 * mm
        return y

    def callout(self, y, title, text, kind="tip"):
        palette = {
            "tip": (ORANGE_SOFT, ORANGE, "Consejo"),
            "warn": (SOFT2, WARN, "Atención"),
            "info": (SOFT, INFO, "Nota"),
            "danger": (SOFT2, DANGER, "Importante"),
            "market": (BLACK, ORANGE, "Producto"),
        }
        bg, accent, label = palette.get(kind, palette["tip"])
        lines = self.wrap(text, CONTENT_W - 18 * mm, "Outfit", 10)
        h = 15 * mm + len(lines) * 4.8 * mm
        if y - h < MARGIN_BOTTOM + 14 * mm:
            self.new_page()
            y = PAGE_H - MARGIN_TOP - 8 * mm
        self.c.setFillColor(bg)
        self.c.roundRect(MARGIN_X, y - h, CONTENT_W, h, 4 * mm, fill=1, stroke=0)
        self.c.setFillColor(accent)
        self.c.rect(MARGIN_X, y - h, 2.2 * mm, h, fill=1, stroke=0)
        self.c.setFont("Outfit-Bold", 9)
        self.c.drawString(MARGIN_X + 7 * mm, y - 6.5 * mm, (title or label).upper())
        self.c.setFillColor(WHITE if kind == "market" else INK)
        if kind == "market":
            self.c.setFillColor(WHITE)
        self.c.setFont("Outfit", 10)
        ty = y - 13 * mm
        for line in lines:
            self.c.setFillColor(WHITE if kind == "market" else INK)
            self.c.drawString(MARGIN_X + 7 * mm, ty, line)
            ty -= 4.8 * mm
        return y - h - 6 * mm

    def image(self, key, y, max_h=78 * mm, caption=None, full_bleed=False):
        path = self.assets.get(key)
        if path is None or not Path(path).exists():
            return y
        ir = ImageReader(str(path))
        iw, ih = ir.getSize()
        if full_bleed:
            # cover most page, leave chrome
            max_w = PAGE_W
            max_h = PAGE_H
            scale = max(max_w / iw, max_h / ih)
            w, h = iw * scale, ih * scale
            self.c.drawImage(ir, (PAGE_W - w) / 2, (PAGE_H - h) / 2, width=w, height=h, mask="auto")
            return 0
        max_w = CONTENT_W
        scale = min(max_w / iw, max_h / ih)
        w, h = iw * scale, ih * scale
        if y - h < MARGIN_BOTTOM + 18 * mm:
            self.new_page()
            y = PAGE_H - MARGIN_TOP - 8 * mm
        x = MARGIN_X + (CONTENT_W - w) / 2
        self.c.setFillColor(SOFT2)
        self.c.roundRect(x - 2.5 * mm, y - h - 2.5 * mm, w + 5 * mm, h + 5 * mm, 3.5 * mm, fill=1, stroke=0)
        self.c.drawImage(ir, x, y - h, width=w, height=h, mask="auto")
        y = y - h - 4 * mm
        if caption:
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit-Med", 8)
            self.c.drawCentredString(PAGE_W / 2, y - 3 * mm, caption)
            y -= 7 * mm
        return y - 3 * mm

    def steps(self, y, steps):
        for i, (title, text) in enumerate(steps, 1):
            if y < MARGIN_BOTTOM + 22 * mm:
                self.new_page()
                y = PAGE_H - MARGIN_TOP - 8 * mm
            self.c.setFillColor(ORANGE)
            self.c.circle(MARGIN_X + 4.5 * mm, y, 4.5 * mm, fill=1, stroke=0)
            self.c.setFillColor(WHITE)
            self.c.setFont("Outfit-Bold", 11)
            self.c.drawCentredString(MARGIN_X + 4.5 * mm, y - 1.8 * mm, str(i))
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Semi", 12)
            self.c.drawString(MARGIN_X + 13 * mm, y - 1 * mm, title)
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit", 9.5)
            y -= 7 * mm
            for line in self.wrap(text, CONTENT_W - 15 * mm, "Outfit", 9.5):
                self.c.drawString(MARGIN_X + 13 * mm, y, line)
                y -= 4.3 * mm
            y -= 4.5 * mm
        return y

    def table(self, y, headers, rows, col_w=None):
        n = len(headers)
        col_w = col_w or [CONTENT_W / n] * n
        row_h = 8.5 * mm
        need = row_h * (len(rows) + 1)
        if y - need < MARGIN_BOTTOM + 14 * mm:
            self.new_page()
            y = PAGE_H - MARGIN_TOP - 8 * mm
        self.c.setFillColor(BLACK)
        self.c.roundRect(MARGIN_X, y - row_h, CONTENT_W, row_h, 2.8 * mm, fill=1, stroke=0)
        self.c.setFillColor(WHITE)
        self.c.setFont("Outfit-Semi", 8.5)
        x = MARGIN_X + 3.5 * mm
        for i, h in enumerate(headers):
            self.c.drawString(x, y - 5.6 * mm, h.upper())
            x += col_w[i]
        yy = y - row_h
        for ri, row in enumerate(rows):
            yy -= row_h
            self.c.setFillColor(SOFT if ri % 2 == 0 else WHITE)
            self.c.rect(MARGIN_X, yy, CONTENT_W, row_h, fill=1, stroke=0)
            self.c.setFillColor(INK)
            self.c.setFont("Outfit", 9)
            x = MARGIN_X + 3.5 * mm
            for i, cell in enumerate(row):
                self.c.drawString(x, yy + 2.8 * mm, str(cell))
                x += col_w[i]
        self.c.setStrokeColor(ORANGE)
        self.c.setLineWidth(1.2)
        self.c.line(MARGIN_X, yy, MARGIN_X + CONTENT_W, yy)
        return yy - 7 * mm

    # ── special pages ─────────────────────────────────────────
    def cover(self):
        self.new_page(numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        # curves
        c.setFillColor(ORANGE)
        p = c.beginPath()
        p.moveTo(0, PAGE_H)
        p.curveTo(PAGE_W * 0.25, PAGE_H * 0.82, PAGE_W * 0.55, PAGE_H, PAGE_W, PAGE_H * 0.72)
        p.lineTo(PAGE_W, PAGE_H)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
        p = c.beginPath()
        p.moveTo(0, 0)
        p.curveTo(PAGE_W * 0.35, PAGE_H * 0.18, PAGE_W * 0.75, PAGE_H * 0.02, PAGE_W, PAGE_H * 0.28)
        p.lineTo(PAGE_W, 0)
        p.close()
        c.setFillColor(ORANGE_DEEP)
        c.drawPath(p, fill=1, stroke=0)

        c.setFillColor(ORANGE)
        c.roundRect(MARGIN_X, PAGE_H - 36 * mm, 13 * mm, 13 * mm, 3.2 * mm, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 18)
        c.drawCentredString(MARGIN_X + 6.5 * mm, PAGE_H - 31.5 * mm, "T")
        c.setFont("Outfit-Bold", 16)
        c.drawString(MARGIN_X + 17 * mm, PAGE_H - 31 * mm, PRODUCT)

        c.setFont("Outfit-Black", 46)
        c.drawString(MARGIN_X, PAGE_H - 58 * mm, "Manual")
        c.drawString(MARGIN_X, PAGE_H - 75 * mm, "Profesional")
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Med", 11)
        c.drawString(MARGIN_X, PAGE_H - 88 * mm, SUBTITLE.upper())

        if "hero" in self.assets:
            ir = ImageReader(str(self.assets["hero"]))
            c.drawImage(ir, 4 * mm, 48 * mm, width=PAGE_W - 8 * mm, height=112 * mm,
                        mask="auto", preserveAspectRatio=True, anchor="c")

        c.setFillColor(WHITE)
        c.setFont("Outfit-Med", 9)
        c.drawString(MARGIN_X, 28 * mm, f"Versión {VERSION}")
        c.drawString(MARGIN_X, 22 * mm, DATE_STR)
        c.setFont("Outfit-Semi", 11)
        c.drawRightString(PAGE_W - MARGIN_X, 26 * mm, BRAND)
        c.setStrokeColor(ORANGE)
        c.setLineWidth(1.4)
        c.line(PAGE_W - MARGIN_X - 32 * mm, 22 * mm, PAGE_W - MARGIN_X, 22 * mm)

    def brand_intro(self):
        self.new_page(numbered=False)
        c = self.c
        c.setFillColor(SOFT)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        c.rect(0, 0, 8 * mm, PAGE_H, fill=1, stroke=0)
        c.setFillColor(INK)
        c.setFont("Outfit-Black", 28)
        c.drawString(MARGIN_X + 6 * mm, PAGE_H - 40 * mm, "Una sola plataforma.")
        c.drawString(MARGIN_X + 6 * mm, PAGE_H - 54 * mm, "Todo bajo control.")
        c.setFillColor(MUTED)
        c.setFont("Outfit", 12)
        y = PAGE_H - 72 * mm
        for line in self.wrap(
            "Tata.Manager es el sistema integral de gestión comercial para Windows y Android. "
            "Diseñado para equipos que venden, reponen, cobran y se sincronizan sin fricción.",
            CONTENT_W - 10 * mm, "Outfit", 12,
        ):
            c.drawString(MARGIN_X + 6 * mm, y, line)
            y -= 6 * mm
        # three statement cards
        cards = [
            ("Más velocidad", "Venta rápida, remitos y PDF listos para WhatsApp."),
            ("Menos errores", "Stock, precios y permisos con trazabilidad."),
            ("Tiempo real", "Firebase conecta PC, celular y tablet."),
        ]
        for i, (t, d) in enumerate(cards):
            x = MARGIN_X + 6 * mm + i * 58 * mm
            c.setFillColor(WHITE)
            c.roundRect(x, 55 * mm, 54 * mm, 55 * mm, 4 * mm, fill=1, stroke=0)
            c.setFillColor(ORANGE)
            c.circle(x + 10 * mm, 95 * mm, 3.5 * mm, fill=1, stroke=0)
            c.setFillColor(INK)
            c.setFont("Outfit-Bold", 11)
            c.drawString(x + 6 * mm, 82 * mm, t)
            c.setFillColor(MUTED)
            c.setFont("Outfit", 8.5)
            ty = 72 * mm
            for line in self.wrap(d, 44 * mm, "Outfit", 8.5):
                c.drawString(x + 6 * mm, ty, line)
                ty -= 4 * mm
        c.setFillColor(MUTED)
        c.setFont("Outfit-Med", 9)
        c.drawString(MARGIN_X + 6 * mm, 28 * mm, f"{BRAND}  ·  {PRODUCT}  ·  v{VERSION}")

    def welcome_spread(self):
        """Doble página catálogo: ¿Por qué elegir Tata.Manager?"""
        # PAGE A
        self.new_page(chapter="Bienvenida", numbered=True, soft_bg=True)
        c = self.c
        c.setFillColor(INK)
        c.setFont("Outfit-Black", 32)
        c.drawString(MARGIN_X, PAGE_H - 35 * mm, "¿Por qué elegir")
        c.setFillColor(ORANGE)
        c.drawString(MARGIN_X, PAGE_H - 50 * mm, "Tata.Manager?")
        c.setFillColor(MUTED)
        c.setFont("Outfit", 11)
        y = PAGE_H - 65 * mm
        for line in self.wrap(
            "Porque concentra operación, control y sincronización en una experiencia limpia. "
            "Hecho para comercios reales que necesitan vender hoy y auditar mañana.",
            CONTENT_W, "Outfit", 11,
        ):
            c.drawString(MARGIN_X, y, line)
            y -= 5.5 * mm

        features = [
            ("ico_usuarios", "Multiusuario", "Roles y accesos por persona"),
            ("ico_windows", "Windows", "Desktop completo para mostrador"),
            ("ico_android", "Android", "Operación móvil en el local"),
            ("ico_firebase", "Firebase", "Nube del negocio sincronizada"),
            ("ico_reportes", "Reportes", "Decisiones con datos claros"),
            ("ico_chat", "Chat", "Equipo conectado al instante"),
        ]
        for i, (ico, title, desc) in enumerate(features):
            col, row = i % 3, i // 3
            x = MARGIN_X + col * 60 * mm
            yy = 105 * mm - row * 48 * mm
            c.setFillColor(WHITE)
            c.roundRect(x, yy, 56 * mm, 42 * mm, 4 * mm, fill=1, stroke=0)
            if ico in self.assets:
                c.drawImage(ImageReader(str(self.assets[ico])), x + 4 * mm, yy + 22 * mm,
                            width=14 * mm, height=14 * mm, mask="auto")
            c.setFillColor(INK)
            c.setFont("Outfit-Bold", 11)
            c.drawString(x + 20 * mm, yy + 28 * mm, title)
            c.setFillColor(MUTED)
            c.setFont("Outfit", 8)
            for j, line in enumerate(self.wrap(desc, 32 * mm, "Outfit", 8)[:2]):
                c.drawString(x + 6 * mm, yy + 14 * mm - j * 4 * mm, line)

        # PAGE B
        self.new_page(chapter="Bienvenida", numbered=True, soft_bg=True)
        features2 = [
            ("ico_auditoria", "Auditoría", "Quién cambió qué, y cuándo"),
            ("ico_stock", "Stock", "Entradas, salidas y alertas"),
            ("ico_pdf", "PDFs", "Archivo por cliente, listo para enviar"),
            ("ico_backup", "Backups", "Resguardo local además de la nube"),
            ("ico_usuarios", "Permisos", "Matriz fina por módulo"),
            ("ico_sync", "Sincronización", "PC · celular · tablet alineados"),
        ]
        c = self.c
        c.setFillColor(INK)
        c.setFont("Outfit-Black", 26)
        c.drawString(MARGIN_X, PAGE_H - 35 * mm, "Capacidades que")
        c.setFillColor(ORANGE)
        c.drawString(MARGIN_X, PAGE_H - 48 * mm, "sostienen el negocio.")
        for i, (ico, title, desc) in enumerate(features2):
            col, row = i % 3, i // 3
            x = MARGIN_X + col * 60 * mm
            yy = 145 * mm - row * 52 * mm
            c.setFillColor(WHITE)
            c.roundRect(x, yy, 56 * mm, 46 * mm, 4 * mm, fill=1, stroke=0)
            c.setFillColor(ORANGE)
            c.rect(x, yy, 2 * mm, 46 * mm, fill=1, stroke=0)
            if ico in self.assets:
                c.drawImage(ImageReader(str(self.assets[ico])), x + 6 * mm, yy + 26 * mm,
                            width=12 * mm, height=12 * mm, mask="auto")
            c.setFillColor(INK)
            c.setFont("Outfit-Bold", 12)
            c.drawString(x + 20 * mm, yy + 30 * mm, title)
            c.setFillColor(MUTED)
            c.setFont("Outfit", 8.5)
            for j, line in enumerate(self.wrap(desc, 42 * mm, "Outfit", 8.5)[:2]):
                c.drawString(x + 6 * mm, yy + 16 * mm - j * 4 * mm, line)
        c.setFillColor(BLACK)
        c.roundRect(MARGIN_X, 28 * mm, CONTENT_W, 28 * mm, 4 * mm, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Bold", 12)
        c.drawCentredString(PAGE_W / 2, 42 * mm, "Todo tu negocio en un solo lugar.")
        c.setFillColor(WHITE)
        c.setFont("Outfit", 9)
        c.drawCentredString(PAGE_W / 2, 34 * mm, "Más velocidad. Menos errores. Información sincronizada.")

    def toc(self):
        self.new_page(chapter="Índice", numbered=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        self.c.setFillColor(INK)
        self.c.setFont("Outfit-Black", 32)
        self.c.drawString(MARGIN_X, y, "Índice")
        y -= 8 * mm
        self.c.setStrokeColor(ORANGE)
        self.c.setLineWidth(3)
        self.c.line(MARGIN_X, y, MARGIN_X + 22 * mm, y)
        y -= 8 * mm
        self.c.setFillColor(MUTED)
        self.c.setFont("Outfit", 10)
        self.c.drawString(MARGIN_X, y, "Una lectura guiada: de la instalación al control total.")
        y -= 12 * mm

        items = [
            ("01", "Bienvenida y valor del producto", "06"),
            ("02", "Mapa del sistema", "08"),
            ("03", "Instalación", "11"),
            ("04", "Primer ingreso", "14"),
            ("05", "Dashboard", "17"),
            ("06", "Productos", "21"),
            ("07", "Clientes", "27"),
            ("08", "Ventas y remitos", "30"),
            ("09", "Cuenta corriente", "36"),
            ("10", "Compras y proveedores", "38"),
            ("11", "Stock", "41"),
            ("12", "Usuarios, roles y permisos", "43"),
            ("13", "Reportes y archivo PDF", "47"),
            ("14", "Configuración", "50"),
            ("15", "Firebase y sincronización", "52"),
            ("16", "Respaldo y auditoría", "56"),
            ("17", "Comunicación interna", "59"),
            ("18", "Problemas frecuentes", "61"),
            ("19", "Buenas prácticas", "63"),
            ("20", "Glosario y contacto", "65"),
        ]
        for num, title, pg in items:
            if y < MARGIN_BOTTOM + 18 * mm:
                self.new_page(chapter="Índice")
                y = PAGE_H - MARGIN_TOP - 8 * mm
            self.c.setFillColor(ORANGE_SOFT)
            self.c.circle(MARGIN_X + 4.5 * mm, y + 1.5 * mm, 4.5 * mm, fill=1, stroke=0)
            self.c.setFillColor(ORANGE)
            self.c.setFont("Outfit-Bold", 8)
            self.c.drawCentredString(MARGIN_X + 4.5 * mm, y, num)
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Semi", 11)
            self.c.drawString(MARGIN_X + 13 * mm, y, title)
            tw = self.c.stringWidth(title, "Outfit-Semi", 11)
            start = MARGIN_X + 15 * mm + tw
            end = PAGE_W - MARGIN_X - 14 * mm
            self.c.setFillColor(LINE)
            x = start
            while x < end:
                self.c.circle(x, y + 1.2 * mm, 0.55, fill=1, stroke=0)
                x += 3.0 * mm
            self.c.setFillColor(ORANGE)
            self.c.setFont("Outfit-Bold", 11)
            self.c.drawRightString(PAGE_W - MARGIN_X, y, pg)
            # thin separator every 5
            if num in ("05", "10", "15"):
                self.c.setStrokeColor(SOFT2)
                self.c.setLineWidth(0.8)
                self.c.line(MARGIN_X + 13 * mm, y - 3.5 * mm, PAGE_W - MARGIN_X, y - 3.5 * mm)
            y -= 9.2 * mm

    def hero(self, image_key: str, phrase: str, sub: str = ""):
        """Página tipo catálogo Apple: imagen dominante + una frase."""
        self.new_page(numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        path = self.assets.get(image_key)
        if path and Path(path).exists():
            ir = ImageReader(str(path))
            # image band
            c.drawImage(ir, 0, PAGE_H * 0.28, width=PAGE_W, height=PAGE_H * 0.55,
                        mask="auto", preserveAspectRatio=True, anchor="c")
        # gradient bars
        c.setFillColor(BLACK)
        c.rect(0, PAGE_H * 0.78, PAGE_W, PAGE_H * 0.22, fill=1, stroke=0)
        c.rect(0, 0, PAGE_W, PAGE_H * 0.30, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Med", 9)
        c.drawString(MARGIN_X, PAGE_H - 18 * mm, PRODUCT.upper())
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 26)
        # wrap phrase
        y = 48 * mm
        for line in self.wrap(phrase, CONTENT_W, "Outfit-Black", 26):
            c.drawString(MARGIN_X, y, line)
            y -= 10 * mm
        if sub:
            c.setFillColor(ORANGE)
            c.setFont("Outfit", 11)
            c.drawString(MARGIN_X, 28 * mm, sub)

    def chapter_opener(self, num: str, title: str, subtitle: str, image_key: str | None = None, ico: str | None = None):
        self.new_page(chapter=title, numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        # orange band bottom
        c.setFillColor(ORANGE)
        p = c.beginPath()
        p.moveTo(0, PAGE_H * 0.42)
        p.curveTo(PAGE_W * 0.4, PAGE_H * 0.55, PAGE_W * 0.6, PAGE_H * 0.28, PAGE_W, PAGE_H * 0.45)
        p.lineTo(PAGE_W, 0)
        p.lineTo(0, 0)
        p.close()
        c.drawPath(p, fill=1, stroke=0)

        c.setFillColor(ORANGE)
        c.setFont("Outfit-Black", 12)
        c.drawString(MARGIN_X, PAGE_H - 32 * mm, f"CAPÍTULO {num}")
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 40)
        # title may be multiline
        y = PAGE_H - 50 * mm
        for line in self.wrap(title.upper(), CONTENT_W - 10 * mm, "Outfit-Black", 40):
            c.drawString(MARGIN_X, y, line)
            y -= 14 * mm
        c.setFillColor(SOFT2)
        c.setFont("Outfit", 12)
        for line in self.wrap(f"“{subtitle}”", CONTENT_W - 10 * mm, "Outfit", 12):
            c.drawString(MARGIN_X, y - 2 * mm, line)
            y -= 6 * mm

        if image_key and image_key in self.assets:
            ir = ImageReader(str(self.assets[image_key]))
            c.setFillColor(WHITE)
            c.roundRect(MARGIN_X, 28 * mm, CONTENT_W, 78 * mm, 5 * mm, fill=1, stroke=0)
            c.drawImage(ir, MARGIN_X + 3 * mm, 31 * mm, width=CONTENT_W - 6 * mm, height=72 * mm,
                        mask="auto", preserveAspectRatio=True, anchor="c")
        elif ico and ico in self.assets:
            c.drawImage(ImageReader(str(self.assets[ico])), PAGE_W - 55 * mm, PAGE_H - 70 * mm,
                        width=32 * mm, height=32 * mm, mask="auto")

        c.setFillColor(WHITE)
        c.setFont("Outfit-Semi", 9)
        c.drawRightString(PAGE_W - MARGIN_X, 14 * mm, f"{self.page:02d}")

    # ── content chapters ──────────────────────────────────────
    def ch_mapa(self):
        self.chapter_opener("02", "Mapa del sistema", "Cada módulo tiene un propósito. Ninguno sobra.", "dashboard", "ico_reportes")
        self.new_page(chapter="Mapa del sistema", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Módulos que componen Tata.Manager", y)
        y = self.table(y, ["Módulo", "Valor para el negocio"], [
            ["Productos", "Catálogo, precios, fotos y listas"],
            ["Stock", "Movimientos, alertas y kardex"],
            ["Ventas / Remitos", "Circuito comercial completo"],
            ["Clientes / CC", "Agenda y cobranza"],
            ["Compras / Proveedores", "Reposición con costo actualizado"],
            ["Reportes / PDF", "Análisis e intercambio"],
            ["Usuarios / Permisos", "Gobierno del equipo"],
            ["Firebase / Sync", "Misma verdad en cada dispositivo"],
        ], [42 * mm, CONTENT_W - 42 * mm])
        y = self.callout(y, "Producto", "Una sola plataforma. Todo bajo control.", "market")
        self.new_page(chapter="Mapa del sistema")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Circuito comercial", y)
        y = self.image("info_venta", y, max_h=48 * mm, caption="Del cliente al historial, sin saltos de sistema")
        y = self.image("info_compra", y, max_h=48 * mm, caption="De la compra a todos los dispositivos")

    def ch_install(self):
        self.chapter_opener("03", "Instalación", "Dos plataformas. Un mismo producto.", "photo_notebook", "ico_windows")
        self.new_page(chapter="Instalación")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        if "photo_notebook" in self.assets:
            y = self.image("photo_notebook", y, max_h=55 * mm, caption="Operación desktop lista para el local")
        y = self.h2("Android", y)
        y = self.steps(y, [
            ("Instalá el APK", "Usá app-release.apk del flujo de build."),
            ("Permití el origen", "Solo si el dispositivo lo solicita."),
            ("Ingresá", "Abrí Tata.Manager y autenticate."),
        ])
        self.new_page(chapter="Instalación", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Windows", y)
        y = self.steps(y, [
            ("Copiá la carpeta Release completa", "El .exe solo no alcanza."),
            ("Ejecutá desde esa carpeta", "Conservá DLL y data folders."),
            ("No reestructures archivos", "Mover piezas sueltas rompe el arranque."),
        ])
        y = self.callout(y, "Atención", "Si en una PC nueva no abre: volvé a copiar el directorio Release entero.", "warn")

    def ch_login(self):
        self.chapter_opener("04", "Primer ingreso", "Tu identidad abre el sistema. Firebase abre la red del negocio.", "login", "ico_sync")
        self.new_page(chapter="Primer ingreso")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("login", y, max_h=70 * mm, caption="Autenticación unificada Windows / Android")
        y = self.steps(y, [
            ("Abrí la app", "Pantalla de login con marca Tata.Manager."),
            ("Usuario y contraseña", "El primer acceso suele ser admin."),
            ("Cambiá la clave si se pide", "Mínimo 6 caracteres."),
            ("Verificá sync", "Con Firebase, ese dispositivo entra a la red del negocio."),
        ])
        self.new_page(chapter="Primer ingreso")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("De un usuario a todos los dispositivos", y)
        y = self.image("info_login", y, max_h=45 * mm)
        y = self.callout(y, "Importante", "Sin login Firebase el equipo queda en base local y no ve al resto.", "danger")
        if "illu_sync_premium" in self.assets:
            y = self.image("illu_sync_premium", y, max_h=50 * mm, caption="Sincronización como capa de producto")

    def ch_dashboard(self):
        self.chapter_opener("05", "Dashboard", "El pulso del negocio, cada mañana.", "dashboard", "ico_reportes")
        self.hero("dashboard", "Controlá todo tu negocio desde un único lugar.", "Dashboard · Tata.Manager")
        self.new_page(chapter="Dashboard")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("dashboard_ann", y, max_h=85 * mm, caption="① KPIs  ② Tendencia  ③ Top ventas  ④ Alertas")
        self.new_page(chapter="Dashboard", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Qué mirar cada mañana", y)
        y = self.bullets([
            "Productos y valor de stock.",
            "Tarjeta Sin stock → listado filtrado al instante.",
            "Ventas del mes y tendencia.",
            "Cuentas por cobrar → detalle de deudores.",
        ], y)
        y = self.callout(y, "Consejo", "Actualizá con la flecha circular después de cargas grandes o cambios de red.", "tip")
        if "photo_mostrador" in self.assets:
            y = self.image("photo_mostrador", y, max_h=55 * mm, caption="El dashboard vive donde ocurre la venta")

    def ch_productos(self):
        self.chapter_opener("06", "Productos", "El catálogo es la fuente de verdad del comercio.", "productos_ann", "ico_productos")
        self.new_page(chapter="Productos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("productos_ann", y, max_h=82 * mm, caption="Pantalla anotada: alta, búsqueda, filtros y escáner")
        # ZOOM sequence
        self.new_page(chapter="Productos", numbered=False)
        c = self.c
        c.setFillColor(SOFT)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Black", 11)
        c.drawString(MARGIN_X, PAGE_H - 25 * mm, "ZOOM 01")
        c.setFillColor(INK)
        c.setFont("Outfit-Black", 26)
        c.drawString(MARGIN_X, PAGE_H - 40 * mm, "Nuevo producto")
        if "zoom_nuevo" in self.assets:
            ir = ImageReader(str(self.assets["zoom_nuevo"]))
            c.drawImage(ir, MARGIN_X, 40 * mm, width=CONTENT_W, height=140 * mm, mask="auto", preserveAspectRatio=True, anchor="c")
        c.setFillColor(MUTED)
        c.setFont("Outfit-Med", 9)
        c.drawString(MARGIN_X, 22 * mm, f"{PRODUCT}  ·  {self.page:02d}")

        self.new_page(chapter="Productos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Completá la ficha", y)
        y = self.image("producto_nuevo", y, max_h=78 * mm, caption="Formulario de alta con foto, costos y listas")
        self.new_page(chapter="Productos", numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        c.setFont("Outfit-Black", 11)
        c.drawString(MARGIN_X, PAGE_H - 25 * mm, "ZOOM 02")
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 26)
        c.drawString(MARGIN_X, PAGE_H - 40 * mm, "Guardar")
        if "zoom_guardar" in self.assets:
            ir = ImageReader(str(self.assets["zoom_guardar"]))
            c.drawImage(ir, MARGIN_X, 50 * mm, width=CONTENT_W, height=120 * mm, mask="auto", preserveAspectRatio=True, anchor="c")
        c.setFont("Outfit-Med", 9)
        c.setFillColor(MUTED)
        c.drawString(MARGIN_X, 22 * mm, f"{PRODUCT}  ·  {self.page:02d}")

        self.new_page(chapter="Productos", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Edición y resultado", y)
        y = self.image("producto_editar", y, max_h=70 * mm, caption="Editar mantiene la misma estructura de ficha")
        y = self.two_cards(y, [
            ("Papelera", "Eliminar no borra del todo: recuperá desde Papelera."),
            ("Listas de precio", "Mayorista / minorista u otras listas concurrentes."),
            ("Alerta sin stock", "Desde Dashboard tocá Sin stock para filtrar."),
            ("Fotos sync", "Subidas con login Firebase llegan a todos los equipos."),
        ])

    def two_cards(self, y, cards):
        gap = 5 * mm
        w = (CONTENT_W - gap) / 2
        for i, (title, text) in enumerate(cards):
            col, row = i % 2, i // 2
            x = MARGIN_X + col * (w + gap)
            yy = y - row * 30 * mm
            if yy - 26 * mm < MARGIN_BOTTOM + 12 * mm:
                self.new_page()
                return self.two_cards(PAGE_H - MARGIN_TOP - 8 * mm, cards[i:])
            self.c.setFillColor(WHITE)
            self.c.setStrokeColor(LINE)
            self.c.roundRect(x, yy - 24 * mm, w, 26 * mm, 3.5 * mm, fill=1, stroke=1)
            self.c.setFillColor(ORANGE)
            self.c.circle(x + 5 * mm, yy - 5 * mm, 2.2 * mm, fill=1, stroke=0)
            self.c.setFillColor(INK)
            self.c.setFont("Outfit-Semi", 11)
            self.c.drawString(x + 11 * mm, yy - 6.5 * mm, title)
            self.c.setFillColor(MUTED)
            self.c.setFont("Outfit", 8.5)
            ty = yy - 13 * mm
            for line in self.wrap(text, w - 12 * mm, "Outfit", 8.5)[:3]:
                self.c.drawString(x + 6 * mm, ty, line)
                ty -= 3.8 * mm
        return y - math.ceil(len(cards) / 2) * 30 * mm - 4 * mm

    def ch_clientes(self):
        self.chapter_opener("07", "Clientes", "Agenda comercial con saldo e historial a un toque.", "clientes", "ico_clientes")
        self.new_page(chapter="Clientes")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("clientes", y, max_h=72 * mm, caption="Fichas con estado de cuenta")
        y = self.bullets([
            "Alta con nombre, teléfono, dirección y CUIT.",
            "MOSTRADOR = consumidor final en venta rápida.",
            "Historial de documentos desde la ficha.",
        ], y)
        self.new_page(chapter="Clientes", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Ficha del cliente", y)
        y = self.image("cliente_ficha", y, max_h=78 * mm, caption="Saldo, cobranza e historial en una vista")

    def ch_ventas(self):
        self.chapter_opener("08", "Ventas", "Todo el circuito comercial en una sola pantalla.", "ventas_ann", "ico_ventas")
        self.hero("ventas", "Vendé en segundos.", "Venta rápida · Remito · PDF")
        self.new_page(chapter="Ventas y remitos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("ventas_ann", y, max_h=82 * mm, caption="① Buscar  ② Agregar  ③ Carrito  ④ Confirmar")
        self.new_page(chapter="Ventas y remitos", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Venta rápida", y)
        y = self.steps(y, [
            ("Abrí Venta rápida", "Ideal para mostrador."),
            ("Agregá productos", "Búsqueda o escáner."),
            ("Confirmá", "Remito a MOSTRADOR + baja de stock."),
            ("PDF listo", "Queda en Archivo PDF."),
        ])
        self.new_page(chapter="Ventas y remitos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Remitos", y)
        y = self.image("remitos", y, max_h=68 * mm, caption="Estados de cobro visibles de un vistazo")
        y = self.image("info_venta", y, max_h=40 * mm)
        self.new_page(chapter="Ventas y remitos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        if "photo_whatsapp_pdf" in self.assets:
            y = self.image("photo_whatsapp_pdf", y, max_h=70 * mm, caption="Del sistema al cliente, sin rehacer el PDF")
        y = self.callout(y, "Producto", "Más velocidad. Menos errores.", "market")

    def ch_cc(self):
        self.chapter_opener("09", "Cuenta corriente", "Cobranza con contexto: quién, cuánto y por qué documento.", "cc", "ico_clientes")
        self.new_page(chapter="Cuenta corriente")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("cc", y, max_h=78 * mm, caption="Priorizá vencidos y montos altos")
        y = self.bullets([
            "Incluye ventas y remitos sin cobrar.",
            "Detalle por cliente con origen del saldo.",
            "Ideal para el cierre de jornada.",
        ], y)

    def ch_compras(self):
        self.chapter_opener("10", "Compras", "Cuando llega mercadería, el stock y el costo se actualizan juntos.", "compras", "ico_compras")
        self.new_page(chapter="Compras y proveedores")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("compras", y, max_h=75 * mm)
        y = self.steps(y, [
            ("Elegí proveedor", "O crealo si es nuevo."),
            ("Cargá ítems y costos", "Cantidades reales de recepción."),
            ("Registrá", "Sube stock y actualiza costo."),
            ("Sync", "El resto de equipos lo ve con Firebase."),
        ])
        self.new_page(chapter="Compras y proveedores", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Cadena de reposición", y)
        y = self.image("info_compra", y, max_h=48 * mm)
        if "photo_deposito" in self.assets:
            y = self.image("photo_deposito", y, max_h=58 * mm, caption="Operación real de depósito y escaneo")

    def ch_stock(self):
        self.chapter_opener("11", "Stock", "Inventario vivo: movimientos con origen y alertas accionables.", "stock", "ico_stock")
        self.new_page(chapter="Stock")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("stock", y, max_h=75 * mm, caption="Cada movimiento deja rastro")
        y = self.two_cards(y, [
            ("Entradas", "Compras e ingresos controlados."),
            ("Salidas", "Ventas y remitos en tiempo real."),
            ("Ajustes", "Inventario físico documentado."),
            ("Alertas", "Cero y mínimos visibles."),
        ])
        y = self.callout(y, "Atención", "Un ajuste sin origen ensucia la auditoría. Registrá siempre el motivo.", "warn")

    def ch_usuarios(self):
        self.chapter_opener("12", "Usuarios", "Quién entra. Qué puede hacer. Cómo se presenta al equipo.", "usuarios", "ico_usuarios")
        self.new_page(chapter="Usuarios, roles y permisos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("usuarios", y, max_h=70 * mm)
        y = self.table(y, ["Rol", "Alcance"], [
            ["Admin", "Todo: usuarios, permisos, configuración, sync"],
            ["Encargado", "Operación ampliada según matriz"],
            ["Empleado", "Tareas diarias limitadas"],
        ], [35 * mm, CONTENT_W - 35 * mm])
        self.new_page(chapter="Usuarios, roles y permisos", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Roles", y)
        y = self.image("roles", y, max_h=72 * mm, caption="Perfiles claros, sin ambigüedad")
        self.new_page(chapter="Usuarios, roles y permisos")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Matriz de permisos", y)
        y = self.image("permisos", y, max_h=75 * mm, caption="Ver · Crear · Editar · Eliminar por módulo")
        y = self.callout(y, "Importante", "En el alta usá email real: sin eso no hay verificación confiable.", "danger")

    def ch_reportes(self):
        self.chapter_opener("13", "Reportes y PDFs", "De los números a la conversación con el cliente.", "reportes", "ico_pdf")
        self.new_page(chapter="Reportes y archivo PDF")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("reportes", y, max_h=68 * mm)
        y = self.h2("Archivo PDF", y)
        y = self.image("pdfs", y, max_h=58 * mm, caption="Carpetas por cliente")
        self.new_page(chapter="Reportes y archivo PDF", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.steps(y, [
            ("Generá en PC", "Remito o factura desde escritorio."),
            ("Se archiva en la nube", "Organizado por cliente."),
            ("Abrí en el celular", "Módulo Archivo PDF."),
            ("Compartí", "WhatsApp, mail u otras apps."),
        ])
        if "photo_whatsapp_pdf" in self.assets:
            y = self.image("photo_whatsapp_pdf", y, max_h=50 * mm)

    def ch_config(self):
        self.chapter_opener("14", "Configuración", "La identidad del negocio define la cara de cada documento.", "config", "ico_config")
        self.new_page(chapter="Configuración")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("config", y, max_h=78 * mm)
        y = self.bullets([
            "Nombre, logo, teléfono y email comercial.",
            "Plantilla de impresión: encabezado, pie, firma, sello, paleta.",
            "Modo impresión en blanco y negro.",
            "Vista previa PDF antes de guardar la plantilla.",
        ], y)

    def ch_firebase(self):
        self.chapter_opener("15", "Firebase", "La capa cloud que alinea PC, celular y tablet.", "firebase", "ico_firebase")
        self.hero("illu_sync_premium" if "illu_sync_premium" in self.assets else "firebase",
                  "Información sincronizada en tiempo real.", "Firebase · Tata.Manager")
        self.new_page(chapter="Firebase y sincronización")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("firebase", y, max_h=70 * mm, caption="Estado de sync por dominio de datos")
        y = self.table(y, ["Requisito", "Detalle"], [
            ["Mismo negocio", "Mismo tenant Firebase"],
            ["Login", "Cada persona en cada equipo"],
            ["Internet", "Necesaria para subir/bajar"],
            ["Misma versión", "Funciones alineadas"],
        ], [40 * mm, CONTENT_W - 40 * mm])
        self.new_page(chapter="Firebase y sincronización", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("info_compra", y, max_h=48 * mm, caption="Compra → Firebase → dispositivos")
        y = self.bullets([
            "Productos, precios, stock y fotos.",
            "Clientes, proveedores, remitos, ventas y compras.",
            "Archivo PDF y comunicaciones.",
        ], y)
        y = self.callout(y, "Atención", "Sin Firebase: usá Respaldo (.db) para clonar datos entre equipos.", "warn")

    def ch_backup(self):
        self.chapter_opener("16", "Respaldo y auditoría", "Seguridad operativa y trazabilidad de cada cambio crítico.", "backup", "ico_backup")
        self.new_page(chapter="Respaldo y auditoría")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("backup", y, max_h=72 * mm)
        y = self.callout(y, "Consejo", "Aunque uses Firebase, exportá periódicamente. Es tu red offline.", "tip")
        self.new_page(chapter="Respaldo y auditoría", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Auditoría", y)
        y = self.image("auditoria", y, max_h=70 * mm, caption="Altas, precios, usuarios y stock con autor")

    def ch_chat(self):
        self.chapter_opener("17", "Chat", "El equipo opera sin salir del sistema.", "chat", "ico_chat")
        self.new_page(chapter="Comunicación interna")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.image("chat", y, max_h=80 * mm)
        y = self.bullets([
            "Conversaciones 1:1 o de equipo.",
            "Compartí fichas de producto o remito.",
            "Notificaciones en la barra superior.",
        ], y)

    def ch_faq(self):
        self.chapter_opener("18", "Problemas frecuentes", "Diagnóstico rápido para no frenar el local.", None, "ico_auditoria")
        self.new_page(chapter="Problemas frecuentes")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.table(y, ["Síntoma", "Qué revisar"], [
            ["Celular no ve la PC", "Firebase login · misma versión · internet"],
            ["No llega mail de alta", "Email real · Auth/Templates · spam"],
            ["No abre el .exe", "Carpeta Release completa"],
            ["Fotos ausentes", "Subir foto estando logueado"],
            ["Sin stock no aparece", "Tocar tarjeta Sin stock"],
            ["Permiso denegado", "Matriz de permisos del rol"],
        ], [55 * mm, CONTENT_W - 55 * mm])

    def ch_practices(self):
        self.chapter_opener("19", "Buenas prácticas", "Una rutina simple mantiene el sistema confiable.", None, "ico_ventas")
        self.new_page(chapter="Buenas prácticas", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.steps(y, [
            ("Logueate", "Con Firebase si trabajás multi-dispositivo."),
            ("Revisá Inicio", "Sin stock y cuentas por cobrar."),
            ("Vendé", "Venta rápida o remitos."),
            ("Cobrás", "Cuenta corriente al cierre."),
            ("Compartí PDF", "Desde el celular."),
            ("Compras", "Cuando llega mercadería."),
            ("Respaldo", "De forma periódica."),
        ])

    def ch_glossary(self):
        self.chapter_opener("20", "Glosario y contacto", "Lenguaje común. Canales claros.", None, "ico_reportes")
        self.new_page(chapter="Glosario y contacto")
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.table(y, ["Término", "Significado"], [
            ["Remito", "Documento de entrega con productos y cliente"],
            ["MOSTRADOR", "Cliente genérico de venta rápida"],
            ["Lista de precio", "Tabla de precios por canal"],
            ["Tenant", "Espacio Firebase del negocio"],
            ["Papelera", "Productos eliminados recuperables"],
            ["Kardex", "Historial de movimientos de un producto"],
            ["CC", "Cuenta corriente / saldos por cobrar"],
            ["Sync", "Replicación entre dispositivos"],
        ], [40 * mm, CONTENT_W - 40 * mm])
        y -= 2 * mm
        y = self.callout(
            y, "Contacto",
            "Negocio: administrador del sistema. Técnico: responsable del repositorio / PC de desarrollo. "
            "GitHub: github.com/arcuriciro-gif/sistema_nuevo",
            "info",
        )

    def back_cover(self):
        self.new_page(numbered=False)
        c = self.c
        c.setFillColor(BLACK)
        c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
        c.setFillColor(ORANGE)
        p = c.beginPath()
        p.moveTo(0, PAGE_H * 0.38)
        p.curveTo(PAGE_W * 0.45, PAGE_H * 0.52, PAGE_W * 0.65, PAGE_H * 0.22, PAGE_W, PAGE_H * 0.4)
        p.lineTo(PAGE_W, 0)
        p.lineTo(0, 0)
        p.close()
        c.drawPath(p, fill=1, stroke=0)

        c.setFillColor(ORANGE)
        c.roundRect(MARGIN_X, PAGE_H - 40 * mm, 14 * mm, 14 * mm, 3.5 * mm, fill=1, stroke=0)
        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 18)
        c.drawCentredString(MARGIN_X + 7 * mm, PAGE_H - 35 * mm, "T")
        c.setFont("Outfit-Bold", 22)
        c.drawString(MARGIN_X + 20 * mm, PAGE_H - 35 * mm, PRODUCT)
        c.setFont("Outfit-Med", 11)
        c.setFillColor(SOFT2)
        c.drawString(MARGIN_X, PAGE_H - 52 * mm, SUBTITLE)

        # contact block
        c.setFillColor(WHITE)
        c.setFont("Outfit-Semi", 11)
        lines = [
            ("Web", "github.com/arcuriciro-gif/sistema_nuevo"),
            ("Soporte", "Administrador del sistema / equipo técnico"),
            ("Email", "Definido en Configuración del negocio"),
            ("GitHub", "arcuriciro-gif/sistema_nuevo"),
            ("Versión", f"{VERSION}  ·  {DATE_STR}"),
            ("Copyright", f"© {DATE_STR.split()[-1]} {BRAND}. Todos los derechos reservados."),
        ]
        y = PAGE_H - 75 * mm
        for lab, val in lines:
            c.setFillColor(ORANGE)
            c.setFont("Outfit-Bold", 8)
            c.drawString(MARGIN_X, y, lab.upper())
            c.setFillColor(WHITE)
            c.setFont("Outfit", 10)
            c.drawString(MARGIN_X + 28 * mm, y, val)
            y -= 8 * mm

        if "qr" in self.assets:
            c.drawImage(ImageReader(str(self.assets["qr"])), PAGE_W - 55 * mm, 55 * mm,
                        width=35 * mm, height=35 * mm, mask="auto")
            c.setFillColor(WHITE)
            c.setFont("Outfit-Med", 8)
            c.drawRightString(PAGE_W - MARGIN_X, 48 * mm, "Escaneá para el repo")

        c.setFillColor(WHITE)
        c.setFont("Outfit-Black", 14)
        c.drawString(MARGIN_X, 30 * mm, "EL TATA")
        c.setFont("Outfit", 9)
        c.setFillColor(SOFT2)
        c.drawString(MARGIN_X, 22 * mm, "Manual Profesional · Edición editorial")

    def build(self):
        self.cover()
        self.brand_intro()
        self.welcome_spread()
        self.toc()
        # Cap 01 implicit in welcome; continue map...
        self.chapter_opener("01", "Bienvenida", "Empezá por el valor. Después, la operación.",
                            "photo_mostrador" if "photo_mostrador" in self.assets else "hero",
                            "ico_ventas")
        self.new_page(chapter="Bienvenida", soft_bg=True)
        y = PAGE_H - MARGIN_TOP - 6 * mm
        y = self.h2("Qué vas a lograr", y)
        y = self.body(
            "Operar catálogo, stock, ventas, remitos, clientes, compras, reportes y comunicación "
            "interna desde una sola experiencia — en Windows y Android.",
            y, size=11, leading=16,
        )
        y -= 4 * mm
        y = self.callout(y, "Producto", "Todo tu negocio en un solo lugar.", "market")
        if "photo_notebook" in self.assets:
            y = self.image("photo_notebook", y, max_h=60 * mm)

        self.ch_mapa()
        self.ch_install()
        self.ch_login()
        self.ch_dashboard()
        self.ch_productos()
        self.ch_clientes()
        self.ch_ventas()
        self.ch_cc()
        self.ch_compras()
        self.ch_stock()
        self.ch_usuarios()
        self.ch_reportes()
        self.ch_config()
        self.ch_firebase()
        self.ch_backup()
        self.ch_chat()
        self.ch_faq()
        self.ch_practices()
        self.ch_glossary()
        self.back_cover()
        self.c.save()
        return self.path, self.page


def main():
    manual = Manual()
    path, pages = manual.build()
    print(f"OK {path} pages={pages} size_mb={path.stat().st_size/1024/1024:.2f}")
    for dest in [
        Path("/workspace/assets/docs/MANUAL_DE_USO.pdf"),
        Path("/workspace/MANUAL_DE_USO.pdf"),
        Path("/opt/cursor/artifacts/Tata_Manager_Manual_Profesional.pdf"),
    ]:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(path.read_bytes())
        print("COPIED", dest)


if __name__ == "__main__":
    main()
