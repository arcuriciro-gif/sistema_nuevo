import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Canal interno para refrescar pantallas cuando cambian datos locales o de sync.
///
/// Usa debounce para no disparar N recargas si Firestore trae varios docs seguidos.
class DataRefreshHub extends ChangeNotifier {
  DataRefreshHub._();

  static final DataRefreshHub instance = DataRefreshHub._();

  static const Duration debounce = Duration(milliseconds: 450);

  Timer? _debounce;

  void notifyProductos() => _schedule();
  void notifyVentas() => _schedule();
  void notifyStock() => _schedule();
  void notifyTodo() => _schedule();

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(debounce, _notifySafe);
  }

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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
