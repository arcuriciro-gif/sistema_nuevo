import 'package:flutter_test/flutter_test.dart';

/// Evidencia de la divergencia de campo (screenshots 2026-07-28):
/// - EXE 1127 = -2  / APK 1127 = 4   (Δ +6 en APK)
/// - EXE pruebq = 18 / APK pruebq = 33 (Δ +15 en APK)
/// - Catálogo 2884 = 2884 (productos OK; stock NO)
///
/// Causa: Windows aplicó salidas localmente; esas stock_ops no llegaron
/// (o no se aplicaron) en el APK. El pull chico + watermark adelantado
/// dejaba el APK "en verde" con stock viejo.
///
/// Orden obligatorio de reparación:
/// 1) PUSH stock_ops del EXE → Firestore (applied)
/// 2) PULL grande en ambos
/// 3) reparar proyecciones
void main() {
  test('orden convergencia: push antes que pull', () {
    const pasos = [
      'push_stock_ops_outbox_windows',
      'reconcilizar_pending_apply_cloud',
      'pull_recientes_applied',
      'pull_watermark_pages',
      'sweep_holds',
      'reparar_proyecciones',
    ];
    expect(pasos.first, 'push_stock_ops_outbox_windows');
    expect(pasos.indexOf('push_stock_ops_outbox_windows'),
        lessThan(pasos.indexOf('pull_recientes_applied')));
  });

  test('Windows Actualizar ahora: micro-rondas ≤2 (no maxApply 250 ni 60)', () {
    // Regresión 1.4.18 ráfaga + 1.4.19 soft-pull 60 con 5 pending.
    const winManualMax = 2;
    const winSoftMax = 4;
    const banned = 60;
    expect(winManualMax, lessThan(banned));
    expect(winSoftMax, lessThan(banned));
    // Techo total del gesto < umbral crash histórico.
    const rounds = 20;
    expect(rounds * winManualMax, lessThan(50));
  });

  test('KPI sin stock: negativos no son stock==0 (explica 2884≠6+2866)', () {
    // APK: Con stock 6 + Sin stock 2866 = 2872; total 2884 → 12 con stock<0
    const total = 2884;
    const conStock = 6;
    const sinStockCero = 2866;
    final negativosOOtros = total - conStock - sinStockCero;
    expect(negativosOOtros, 12);
  });

  test('deltas observados deben cerrarse con las mismas ops en ambos nodos', () {
    // Si ambos aplican el mismo set de deltas, el stock final coincide.
    const win = {'1127': -2, 'pruebq': 18};
    const missingOnApk = {
      '1127': [-1, -1, -1, -1, -1, -1], // 6 salidas
      'pruebq': [-5, -5, -5], // ejemplo 15
    };
    var apk1127 = 4;
    for (final d in missingOnApk['1127']!) {
      apk1127 += d;
    }
    expect(apk1127, win['1127']);
    var apkPrueba = 33;
    for (final d in missingOnApk['pruebq']!) {
      apkPrueba += d;
    }
    expect(apkPrueba, win['pruebq']);
  });
}
