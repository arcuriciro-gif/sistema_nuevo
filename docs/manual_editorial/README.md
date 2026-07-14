# Manual Profesional — Tata.Manager

Generador editorial del **Manual Profesional** (PDF).

## Regenerar

```bash
pip install reportlab pillow
cd docs/manual_editorial
python3 generate_manual.py
```

Salida:

- `Tata_Manager_Manual_Profesional.pdf`
- Copia en `assets/docs/MANUAL_DE_USO.pdf`
- Copia en raíz `MANUAL_DE_USO.pdf`

## Estructura

| Archivo | Rol |
|---------|-----|
| `design.py` | Paleta, tipografía, constantes |
| `mockups.py` | UI realista + diagramas + ilustraciones |
| `generate_manual.py` | Maquetación editorial y ensamblado PDF |
| `assets/` | Imágenes generadas |
| `fonts/` | Outfit (latin) |

## Estilo

Naranja `#F57C00`, negro, blanco, grises suaves. Tipografía Outfit. ~48 páginas A4.
