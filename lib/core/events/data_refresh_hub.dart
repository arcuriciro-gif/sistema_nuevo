import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Canal interno para refrescar datos en pantallas sin cambiar su diseño.
class DataRefreshHub extends ChangeNotifier {
  DataRefreshHub._();

  static final DataRefreshHub instance = DataRefreshHub._();

  void notifyProductos() => _notifySafe();
  void notifyVentas() => _notifySafe();
  void notifyStock() => _notifySafe();
  void notifyTodo() => _notifySafe();

  void _notifySafe() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      notifyListeners();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }
}
