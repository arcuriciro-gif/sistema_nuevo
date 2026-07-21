import 'package:flutter/foundation.dart';

/// Canal interno para refrescar datos en pantallas sin cambiar su diseño.
class DataRefreshHub extends ChangeNotifier {
  DataRefreshHub._();

  static final DataRefreshHub instance = DataRefreshHub._();

  void notifyProductos() => notifyListeners();
  void notifyVentas() => notifyListeners();
  void notifyStock() => notifyListeners();
  void notifyUsuarios() => notifyListeners();
  void notifyBranding() => notifyListeners();
  void notifyPermisos() => notifyListeners();
  void notifyTodo() => notifyListeners();
}
