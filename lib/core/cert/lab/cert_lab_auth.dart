import '../../../models/usuario.dart';
import '../../../services/auth_service.dart';
import '../../domain/domain_bootstrap.dart';
import '../../sync/cloud_sync_throttle.dart';

/// Bootstrap de auth/dominio para el laboratorio (código real, sin Firebase).
class CertLabAuth {
  static void ensureAdmin() {
    // Lab en lib/: necesita reset aislado entre nodos (misma API que tests).
    // ignore: invalid_use_of_visible_for_testing_member
    DomainBootstrap.resetForTests();
    DomainBootstrap.ensureInitialized();
    CloudSyncThrottle.resetForTests();
    AuthService.instance.currentUser = Usuario(
      id: 1,
      nombre: 'Cert Lab Admin',
      usuario: 'certlab',
      password: 'x',
      rol: 'admin',
      activo: true,
      email: 'certlab@test.local',
    );
  }

  static void clear() {
    AuthService.instance.currentUser = null;
    CloudSyncThrottle.resetForTests();
  }
}
