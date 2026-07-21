import 'package:flutter/material.dart';

/// Indica que la página está embebida en el shell (sin AppBar duplicada).
class ShellHost extends InheritedWidget {
  const ShellHost({
    super.key,
    required this.embedded,
    required this.goHome,
    required super.child,
  });

  final bool embedded;
  final VoidCallback goHome;

  static ShellHost? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellHost>();
  }

  @override
  bool updateShouldNotify(ShellHost oldWidget) =>
      embedded != oldWidget.embedded;
}

void safePopOrHome(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  ShellHost.maybeOf(context)?.goHome();
}

/// AppBar para módulos. En el shell solo muestra acciones (sin título ni campana).
PreferredSizeWidget? buildModuleAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  final puedeVolver = Navigator.of(context).canPop();
  final host = ShellHost.maybeOf(context);
  final embedded = host?.embedded == true && !puedeVolver;

  if (embedded) {
    final acts = actions ?? const <Widget>[];
    if (acts.isEmpty && bottom == null) return null;
    return PreferredSize(
      preferredSize:
          Size.fromHeight(bottom == null ? 40 : 40 + bottom.preferredSize.height),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    ...acts,
                    const Spacer(),
                  ],
                ),
              ),
              ?bottom,
            ],
          ),
        ),
      ),
    );
  }

  return AppBar(
    title: Text(title),
    leading: IconButton(
      icon: Icon(puedeVolver ? Icons.arrow_back : Icons.home_rounded),
      tooltip: puedeVolver ? 'Volver' : 'Inicio',
      onPressed: () => safePopOrHome(context),
    ),
    automaticallyImplyLeading: false,
    actions: actions,
    bottom: bottom,
  );
}
