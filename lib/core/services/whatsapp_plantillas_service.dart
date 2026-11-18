import 'package:shared_preferences/shared_preferences.dart';

/// Plantillas locales de mensajes WhatsApp (sin API Business).
class WhatsappPlantillasService {
  WhatsappPlantillasService._();
  static final WhatsappPlantillasService instance = WhatsappPlantillasService._();

  static const _keyCobro = 'wa_tpl_cobro';
  static const _keyReactivar = 'wa_tpl_reactivar';
  static const _keyGeneral = 'wa_tpl_general';

  static const defaultCobro =
      'Hola {nombre}, te escribo por el saldo pendiente de {monto}. '
      '¿Podemos coordinar el pago? Gracias.';
  static const defaultReactivar =
      'Hola {nombre}, ¿cómo andás? Hace un tiempo no nos vemos. '
      '¿Necesitás reponer algo? Estamos a disposición.';
  static const defaultGeneral =
      'Hola {nombre}, te contacto desde {empresa}. ¿Tenés un momento?';

  String cobro = defaultCobro;
  String reactivar = defaultReactivar;
  String general = defaultGeneral;

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    cobro = p.getString(_keyCobro) ?? defaultCobro;
    reactivar = p.getString(_keyReactivar) ?? defaultReactivar;
    general = p.getString(_keyGeneral) ?? defaultGeneral;
  }

  Future<void> guardar({
    String? cobroTpl,
    String? reactivarTpl,
    String? generalTpl,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (cobroTpl != null) {
      cobro = cobroTpl.trim().isEmpty ? defaultCobro : cobroTpl.trim();
      await p.setString(_keyCobro, cobro);
    }
    if (reactivarTpl != null) {
      reactivar =
          reactivarTpl.trim().isEmpty ? defaultReactivar : reactivarTpl.trim();
      await p.setString(_keyReactivar, reactivar);
    }
    if (generalTpl != null) {
      general =
          generalTpl.trim().isEmpty ? defaultGeneral : generalTpl.trim();
      await p.setString(_keyGeneral, general);
    }
  }

  String render(
    String plantilla, {
    required String nombre,
    String monto = '',
    String empresa = '',
  }) {
    return plantilla
        .replaceAll('{nombre}', nombre)
        .replaceAll('{monto}', monto)
        .replaceAll('{empresa}', empresa);
  }
}
