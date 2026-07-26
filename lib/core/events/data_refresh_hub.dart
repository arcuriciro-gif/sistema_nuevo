import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/platform_capabilities.dart';

/// Canal interno para refrescar datos en pantallas sin cambiar su diseño.
class DataRefreshHub extends ChangeNotifier {
  DataRefreshHub._();

  static final DataRefreshHub instance = DataRefreshHub._();

  Timer? _debounce;
  bool _pending = false;

  void notifyProductos() => _fire();
  void notifyVentas() => _fire();
  void notifyStock() => _fire();
  void notifyUsuarios() => _fire();
  void notifyBranding() => _fire();
  void notifyPermisos() => _fire();
  void notifyTodo() => _fire();

  void _fire() {
    // Windows: coalescer rafagas de sync (evita reload de UI que tumba el .exe).
    if (PlatformCapabilities.isWindowsDesktop) {
      _pending = true;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 2500), () {
        if (!_pending) return;
        _pending = false;
        notifyListeners();
      });
      return;
    }
    notifyListeners();
  }
}
