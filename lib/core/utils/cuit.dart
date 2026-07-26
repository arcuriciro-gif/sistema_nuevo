/// Validación de CUIT/CUIL argentino (módulo 11).
class Cuit {
  Cuit._();

  static String soloDigitos(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  /// true si tiene 11 dígitos y dígito verificador válido.
  static bool esValido(String? raw) {
    final d = soloDigitos(raw ?? '');
    if (d.length != 11) return false;
    if (RegExp(r'^0+$').hasMatch(d)) return false;
    const mult = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += int.parse(d[i]) * mult[i];
    }
    final mod = 11 - (sum % 11);
    final digito = mod == 11 ? 0 : (mod == 10 ? 9 : mod);
    return digito == int.parse(d[10]);
  }

  static String? mensajeError(String? raw) {
    final d = soloDigitos(raw ?? '');
    if (d.isEmpty) return 'CUIT vacío';
    if (d.length != 11) return 'CUIT debe tener 11 dígitos';
    if (!esValido(d)) return 'CUIT inválido (dígito verificador)';
    return null;
  }
}
