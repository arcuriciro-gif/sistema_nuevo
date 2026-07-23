import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/models/notificacion_interna.dart';

void main() {
  test('fromMap usa fallbacks si titulo/cuerpo vienen vacíos', () {
    final n = NotificacionInterna.fromMap({
      'id': '1',
      'usuarioDestino': 'admin',
      'tipo': 'mensaje',
      'titulo': '   ',
      'cuerpo': '',
      'fecha': DateTime(2026, 7, 23).toIso8601String(),
      'leida': 0,
    });
    expect(n.titulo, 'Mensaje nuevo');
    expect(n.cuerpo, contains('Notificaciones'));
  });

  test('fromMap acepta aliases title/body', () {
    final n = NotificacionInterna.fromMap({
      'id': '2',
      'usuarioDestino': 'admin',
      'tipo': 'sistema',
      'title': 'Hola',
      'body': 'Mundo',
      'fecha': DateTime(2026, 7, 23).toIso8601String(),
    });
    expect(n.titulo, 'Hola');
    expect(n.cuerpo, 'Mundo');
  });
}
