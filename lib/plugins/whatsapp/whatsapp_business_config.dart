import 'package:shared_preferences/shared_preferences.dart';

/// Configuración local del plugin WhatsApp Business (por dispositivo/tenant UI).
/// No forma parte del core de dominio ni del sync.
class WhatsappBusinessConfig {
  WhatsappBusinessConfig._();
  static final WhatsappBusinessConfig instance = WhatsappBusinessConfig._();

  static const _kEnabled = 'wa_biz_enabled';
  static const _kPreferApi = 'wa_biz_prefer_api';
  static const _kToken = 'wa_biz_token';
  static const _kPhoneNumberId = 'wa_biz_phone_number_id';
  static const _kWabaId = 'wa_biz_waba_id';
  static const _kApiVersion = 'wa_biz_api_version';
  static const _kDefaultCountry = 'wa_biz_default_country';

  bool enabled = false;
  bool preferApi = true;
  String accessToken = '';
  String phoneNumberId = '';
  String wabaId = '';
  String apiVersion = 'v21.0';
  /// Prefijo país sin + (ej. 54 Argentina) si el número local no lo trae.
  String defaultCountryCode = '54';

  bool get listoParaApi =>
      enabled &&
      preferApi &&
      accessToken.trim().isNotEmpty &&
      phoneNumberId.trim().isNotEmpty;

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? false;
    preferApi = p.getBool(_kPreferApi) ?? true;
    accessToken = p.getString(_kToken) ?? '';
    phoneNumberId = p.getString(_kPhoneNumberId) ?? '';
    wabaId = p.getString(_kWabaId) ?? '';
    apiVersion = p.getString(_kApiVersion) ?? 'v21.0';
    defaultCountryCode = p.getString(_kDefaultCountry) ?? '54';
  }

  Future<void> guardar({
    bool? enabled,
    bool? preferApi,
    String? accessToken,
    String? phoneNumberId,
    String? wabaId,
    String? apiVersion,
    String? defaultCountryCode,
  }) async {
    final p = await SharedPreferences.getInstance();
    if (enabled != null) {
      this.enabled = enabled;
      await p.setBool(_kEnabled, enabled);
    }
    if (preferApi != null) {
      this.preferApi = preferApi;
      await p.setBool(_kPreferApi, preferApi);
    }
    if (accessToken != null) {
      this.accessToken = accessToken.trim();
      await p.setString(_kToken, this.accessToken);
    }
    if (phoneNumberId != null) {
      this.phoneNumberId = phoneNumberId.trim();
      await p.setString(_kPhoneNumberId, this.phoneNumberId);
    }
    if (wabaId != null) {
      this.wabaId = wabaId.trim();
      await p.setString(_kWabaId, this.wabaId);
    }
    if (apiVersion != null) {
      this.apiVersion = apiVersion.trim().isEmpty ? 'v21.0' : apiVersion.trim();
      await p.setString(_kApiVersion, this.apiVersion);
    }
    if (defaultCountryCode != null) {
      this.defaultCountryCode =
          defaultCountryCode.replaceAll(RegExp(r'\D'), '');
      await p.setString(_kDefaultCountry, this.defaultCountryCode);
    }
  }
}
