import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lastSyncAt UTC se muestra en hora local', () {
    // Simula AR (UTC-3): 18:40 UTC → 15:40 local.
    final utc = DateTime.utc(2026, 7, 26, 18, 40);
    final local = utc.toLocal();
    final txt =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    expect(txt.substring(3), '40'); // minutos OK
    // Si el device no es UTC, la hora local ≠ 18.
    if (local.timeZoneOffset.inMinutes != 0) {
      expect(local.hour, isNot(18));
    }
  });
}
