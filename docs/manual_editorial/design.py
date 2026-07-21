"""Sistema de diseño editorial — Tata.Manager Manual Profesional."""

from __future__ import annotations

from pathlib import Path

from reportlab.lib.colors import Color, HexColor, white, black
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
FONTS = ROOT / "fonts"
OUTPUT = ROOT / "Tata_Manager_Manual_Profesional.pdf"

PAGE_W, PAGE_H = A4  # 595.27 x 841.89
MARGIN_X = 18 * mm
MARGIN_TOP = 16 * mm
MARGIN_BOTTOM = 16 * mm
CONTENT_W = PAGE_W - 2 * MARGIN_X

# Paleta corporativa
ORANGE = HexColor("#F57C00")
ORANGE_DEEP = HexColor("#E65100")
ORANGE_SOFT = HexColor("#FFF3E0")
ORANGE_MID = HexColor("#FFB74D")
BLACK = HexColor("#0B0B0B")
INK = HexColor("#1A1A1A")
MUTED = HexColor("#6B7280")
LINE = HexColor("#E5E7EB")
SOFT = HexColor("#F6F7F9")
SOFT2 = HexColor("#EEF0F3")
WHITE = white
SUCCESS = HexColor("#16A34A")
WARN = HexColor("#D97706")
DANGER = HexColor("#DC2626")
INFO = HexColor("#2563EB")

VERSION = "1.0"
DATE_STR = "Julio 2026"
PRODUCT = "Tata.Manager"
SUBTITLE = "Sistema Integral de Gestión Comercial"
BRAND = "EL TATA"

_FONT_DIR = FONTS


def register_fonts() -> None:
    mapping = {
        "Outfit": "Outfit-400.ttf",
        "Outfit-Med": "Outfit-500.ttf",
        "Outfit-Semi": "Outfit-600.ttf",
        "Outfit-Bold": "Outfit-700.ttf",
        "Outfit-Black": "Outfit-800.ttf",
    }
    for name, file in mapping.items():
        path = _FONT_DIR / file
        if path.exists():
            pdfmetrics.registerFont(TTFont(name, str(path)))
        else:
            # Fallback Inter (solo si Outfit no está)
            inter = {
                "Outfit": "Inter-Regular.ttf",
                "Outfit-Med": "Inter-Medium.ttf",
                "Outfit-Semi": "Inter-SemiBold.ttf",
                "Outfit-Bold": "Inter-Bold.ttf",
                "Outfit-Black": "Inter-Bold.ttf",
            }
            pdfmetrics.registerFont(
                TTFont(name, f"/usr/share/fonts/truetype/macos/{inter[name]}")
            )


def rgba(hex_color: str, a: float) -> Color:
    c = HexColor(hex_color)
    return Color(c.red, c.green, c.blue, a)


def chapter_meta() -> list[dict]:
    """Índice editorial completo (páginas alineadas a la edición generada)."""
    return [
        {"num": "01", "title": "Bienvenida", "pages": "04"},
        {"num": "02", "title": "Introducción al sistema", "pages": "06"},
        {"num": "03", "title": "Instalación", "pages": "08"},
        {"num": "04", "title": "Primer ingreso", "pages": "10"},
        {"num": "05", "title": "Dashboard", "pages": "12"},
        {"num": "06", "title": "Productos", "pages": "14"},
        {"num": "07", "title": "Clientes", "pages": "17"},
        {"num": "08", "title": "Ventas y remitos", "pages": "19"},
        {"num": "09", "title": "Cuenta corriente", "pages": "22"},
        {"num": "10", "title": "Compras y proveedores", "pages": "24"},
        {"num": "11", "title": "Stock", "pages": "26"},
        {"num": "12", "title": "Usuarios y permisos", "pages": "28"},
        {"num": "13", "title": "Reportes y PDFs", "pages": "31"},
        {"num": "14", "title": "Configuración", "pages": "33"},
        {"num": "15", "title": "Firebase y sincronización", "pages": "35"},
        {"num": "16", "title": "Respaldo y auditoría", "pages": "38"},
        {"num": "17", "title": "Comunicación interna", "pages": "40"},
        {"num": "18", "title": "Problemas frecuentes", "pages": "42"},
        {"num": "19", "title": "Buenas prácticas", "pages": "44"},
        {"num": "20", "title": "Glosario y contacto", "pages": "46"},
    ]
