# Acceso tipo Cursor: ellos piden, vos das el alta

## Flujo

1. La persona abre la app → **Continuar con Google** o **Continuar con correo**.
2. Si es la primera vez → se crea una **solicitud pendiente** (no entra al sistema).
3. Vos (admin) entrás con `admin` → **Usuarios**.
4. Ves **PENDIENTE ALTA** → ícono de aprobar → elegís rol → **Aprobar**.
5. La persona vuelve a entrar con Google/correo → ya trabaja.

No hace falta que vos les armes usuario y clave de antemano.

## Métodos

| Método | Estado |
|--------|--------|
| Google | Listo (requiere config Firebase, ver abajo) |
| Correo + clave | Listo |
| Teléfono | Próximamente |

## Config Google (una vez)

Ver también `docs/GOOGLE_LOGIN.md`:

1. Firebase → Authentication → **Google** ON + **Correo/contraseña** ON  
2. SHA-1 de Android en la app  
3. Nuevo `google-services.json`  
4. `googleWebClientId` en `lib/firebase_options.dart`

## Admin

- Seguí entrando con usuario/clave (`admin`).
- Podés seguir creando usuarios a mano si querés.
- Rechazar = **Eliminar** la solicitud pendiente.
