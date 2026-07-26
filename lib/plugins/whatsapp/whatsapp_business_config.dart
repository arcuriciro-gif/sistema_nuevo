import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/secure_local_store.dart';

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
  static const _kCatalogId = 'wa_biz_catalog_id';
  static const _kCatalogAutoSync = 'wa_biz_catalog_auto_sync';
  static const _kCatalogCurrency = 'wa_biz_catalog_currency';
  static const _kCatalogUrlTpl = 'wa_biz_catalog_url_tpl';
  static const _kCatalogPriceMode = 'wa_biz_catalog_price_mode';
  static const _kCatalogPriceList = 'wa_biz_catalog_price_list';

  /// Publica y actualiza el precio en Meta al sincronizar.
  static const priceModeSync = 'sync';
  /// No actualiza el precio en WhatsApp (queda congelado); avisa “consultá precio”.
  static const priceModeHide = 'hide';

  bool enabled = false;
  bool preferApi = true;
  String accessToken = '';
  String phoneNumberId = '';
  String wabaId = '';
  String apiVersion = 'v21.0';
  /// Prefijo país sin + (ej. 54 Argentina) si el número local no lo trae.
  String defaultCountryCode = '54';

  /// Meta Commerce Catalog ID (vinculado al WABA).
  String catalogId = '';
  /// Si true, al guardar un producto se intenta subir al catálogo.
  bool catalogAutoSync = false;
  /// ISO 4217 (ARS, USD, …).
  String catalogCurrency = 'ARS';
  /// Plantilla URL producto: puede incluir {codigo} y {id}.
  String catalogProductUrlTemplate = '';
  /// [priceModeSync] o [priceModeHide].
  String catalogPriceMode = priceModeSync;
  /// Clave de lista: `1` / `2` / `3` o id de lista dinámica.
  String catalogPriceListKey = '1';

  bool get catalogSyncPrice => catalogPriceMode != priceModeHide;

  bool get listoParaApi =>
      enabled &&
      preferApi &&
      accessToken.trim().isNotEmpty &&
      phoneNumberId.trim().isNotEmpty;

  bool get listoParaCatalogo =>
      enabled &&
      accessToken.trim().isNotEmpty &&
      catalogId.trim().isNotEmpty;

  Future<void> cargar() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? false;
    preferApi = p.getBool(_kPreferApi) ?? true;
    // Token ofuscado (migra plaintext legacy).
    accessToken = await SecureLocalStore.instance.loadMigrating(_kToken);
    phoneNumberId = p.getString(_kPhoneNumberId) ?? '';
    wabaId = p.getString(_kWabaId) ?? '';
    apiVersion = p.getString(_kApiVersion) ?? 'v21.0';
    defaultCountryCode = p.getString(_kDefaultCountry) ?? '54';
    catalogId = p.getString(_kCatalogId) ?? '';
    catalogAutoSync = p.getBool(_kCatalogAutoSync) ?? false;
    catalogCurrency = p.getString(_kCatalogCurrency) ?? 'ARS';
    catalogProductUrlTemplate = p.getString(_kCatalogUrlTpl) ?? '';
    final mode = p.getString(_kCatalogPriceMode) ?? priceModeSync;
    catalogPriceMode =
        mode == priceModeHide ? priceModeHide : priceModeSync;
    catalogPriceListKey = p.getString(_kCatalogPriceList) ?? '1';
    if (catalogPriceListKey.trim().isEmpty) catalogPriceListKey = '1';
  }

  Future<void> guardar({
    bool? enabled,
    bool? preferApi,
    String? accessToken,
    String? phoneNumberId,
    String? wabaId,
    String? apiVersion,
    String? defaultCountryCode,
    String? catalogId,
    bool? catalogAutoSync,
    String? catalogCurrency,
    String? catalogProductUrlTemplate,
    String? catalogPriceMode,
    String? catalogPriceListKey,
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
      await SecureLocalStore.instance.saveEncrypted(_kToken, this.accessToken);
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
    if (catalogId != null) {
      this.catalogId = catalogId.trim();
      await p.setString(_kCatalogId, this.catalogId);
    }
    if (catalogAutoSync != null) {
      this.catalogAutoSync = catalogAutoSync;
      await p.setBool(_kCatalogAutoSync, catalogAutoSync);
    }
    if (catalogCurrency != null) {
      final c = catalogCurrency.trim().toUpperCase();
      this.catalogCurrency = c.isEmpty ? 'ARS' : c;
      await p.setString(_kCatalogCurrency, this.catalogCurrency);
    }
    if (catalogProductUrlTemplate != null) {
      this.catalogProductUrlTemplate = catalogProductUrlTemplate.trim();
      await p.setString(_kCatalogUrlTpl, this.catalogProductUrlTemplate);
    }
    if (catalogPriceMode != null) {
      this.catalogPriceMode = catalogPriceMode == priceModeHide
          ? priceModeHide
          : priceModeSync;
      await p.setString(_kCatalogPriceMode, this.catalogPriceMode);
    }
    if (catalogPriceListKey != null) {
      final k = catalogPriceListKey.trim();
      this.catalogPriceListKey = k.isEmpty ? '1' : k;
      await p.setString(_kCatalogPriceList, this.catalogPriceListKey);
    }
  }
}
