/// Manifiesto de capacidades del Sync Engine vistas desde el Cert Lab.
///
/// **Regla:** el laboratorio NO modifica el Sync Engine.
/// Este manifiesto se actualiza **solo** cuando hay evidencia del lab en verde
/// demostrando la capacidad. Hasta entonces permanece en `false`.
///
/// Prohibido poner `true` “porque creemos que anda”.
class CertLabEngineManifest {
  /// Windows recibe stock_ops de la nube sin depender solo de un gesto manual
  /// y sin tumbar el EXE (evidencia: P0-01 verde en soak + campo).
  static const bool windowsAutomaticStockInboundCertified = false;

  /// Triple-hop real (EXE↔Firebase↔APK) corrido fuera del protocolo lab.
  static const bool realFirebaseTripleHopCertified = false;

  /// Soak EXE ≥ 2h con sync activa sin cierre espontáneo.
  static const bool exeSoakTwoHoursCertified = false;
}
