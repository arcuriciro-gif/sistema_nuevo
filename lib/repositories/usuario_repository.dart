import '../models/usuario.dart';

abstract class UsuarioRepository {
  Future<List<Usuario>> obtenerTodos();
  Future<Usuario?> buscarPorUsuario(String usuario);
  Future<Usuario?> buscarPorFirebaseUid(String uid);
  Future<int> insertar(Usuario usuario);
  Future<int> actualizar(Usuario usuario);
  Future<int> desactivar(int id);
  /// Borra el usuario de forma permanente (SQLite).
  Future<int> eliminar(int id);
  Future<bool> existeUsuario(String usuario);
  Stream<List<Usuario>> watchTodos();
}
