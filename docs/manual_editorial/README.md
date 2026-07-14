# Manual Profesional — Tata.Manager (edición editorial)

Pieza editorial / marketing de **~67 páginas A4**.

No es un documento Word. Es un manual de producto con ritmo de revista técnica:
portada tipo render, doble página de valor, héroes Apple-style, zooms anotados,
infografías, fotografías lifestyle y contratapa con QR.

## Regenerar

```bash
pip install -r requirements.txt
python3 generate_manual.py
```

## Salidas

| Archivo | Uso |
|---------|-----|
| `Tata_Manager_Manual_Profesional.pdf` | Maestro editorial |
| `../../MANUAL_DE_USO.pdf` | Copia raíz |
| `../../assets/docs/MANUAL_DE_USO.pdf` | Embebible en la app |

## Arquitectura

| Archivo | Rol |
|---------|-----|
| `design.py` | Identidad (naranja `#F57C00`, tipografía Outfit) |
| `mockups.py` | UI, zooms, iconos, infografías, hero devices |
| `generate_manual.py` | Maquetación editorial completa |
| `assets/photos/` | Fotografías e ilustraciones premium |
| `assets/zooms/` | Recortes estilo Microsoft |
| `fonts/` | Outfit |

## Contenido visual

- Portada con laptop + tablet + celular (misma UI)
- Bienvenida tipo catálogo (12 capacidades)
- Índice premium
- Portadillas de capítulo full-bleed
- Páginas hero de marketing
- Capturas anotadas (① ② ③…)
- Zooms de botón / formulario / guardar
- Diagramas Cliente→WhatsApp y Proveedor→dispositivos
- Contratapa con QR, GitHub, versión, copyright
