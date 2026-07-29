import '../../../models/usuario.dart';
import '../../../services/auth_service.dart';
import '../../domain/domain_bootstrap.dart';
import '../../sync/cloud_sync_throttle.dart';

/// Bootstrap de auth/dominio para el laboratorio (código real, sin Firebase).
class CertLabAuth {
  static void ensureAdmin() {
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
