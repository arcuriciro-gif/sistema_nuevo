# Acceso tipo Cursor: ellos piden, vos das el alta

## Flujo

1. La persona abre la app → **Continuar con Google** o **Continuar con correo**.
2. Si es la primera vez → se crea una **solicitud pendiente** (no entra al sistema).
3. Vos (admin) entrás con usuario `admin` / clave (o tu cuenta admin) → menú **Usuarios**.
4. Ves el badge naranja **PENDIENTE ALTA** (arriba de la lista) → ícono de persona con tilde → elegís rol → **Aprobar**.
5. La persona vuelve a entrar con Google/correo → ya trabaja.

Al iniciar sesión como admin, si hay solicitudes pendientes la app te avisa con un diálogo **Ir a Usuarios**.

No hace falta que vos les armes usuario y clave de antemano.

## Métodos

| Método | Estado |
|--------|--------|
| Google | Listo (requiere config Firebase, ver abajo) |
| Correo + clave | Listo |
| Teléfono | Próximamente |

## Config Google (una vez)

1. Firebase → Authentication → **Google** ON + **Correo/contraseña** ON  
2. SHA-1 de Android en la app  
3. Nuevo `google-services.json`  
4. `googleWebClientId` en `lib/firebase_options.dart`

## Admin

- Seguí entrando con usuario/clave (`admin`) para gestionar altas.
- **Importante:** el admin en la PC debe tener **sync/nube conectada** (indicador arriba). Si no, no ve las solicitudes del celular.
- En Usuarios hay botón de nube para traer solicitudes.
- Podés filtrar **Solo pendientes** en Usuarios.
- Rechazar = **Eliminar** la solicitud pendiente.
- También podés crear usuarios a mano si preferís.
