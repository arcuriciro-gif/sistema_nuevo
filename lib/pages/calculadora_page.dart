import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/module_app_bar.dart';

/// Calculadora simple para el mostrador (sumas, restos, %, propinas, etc.).
class CalculadoraPage extends StatefulWidget {
  const CalculadoraPage({super.key});

  @override
  State<CalculadoraPage> createState() => _CalculadoraPageState();
}

class _CalculadoraPageState extends State<CalculadoraPage> {
  String _pantalla = '0';
  double? _acumulado;
  String? _operacion;
  bool _nuevoNumero = true;

  void _digito(String d) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_nuevoNumero) {
        _pantalla = d == '.' ? '0.' : d;
        _nuevoNumero = false;
      } else {
        if (d == '.' && _pantalla.contains('.')) return;
        if (_pantalla == '0' && d != '.') {
          _pantalla = d;
        } else {
          _pantalla += d;
        }
      }
    });
  }

  void _limpiar() {
    HapticFeedback.lightImpact();
    setState(() {
      _pantalla = '0';
      _acumulado = null;
      _operacion = null;
      _nuevoNumero = true;
    });
  }

  void _borrar() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_nuevoNumero || _pantalla.length <= 1) {
        _pantalla = '0';
        _nuevoNumero = true;
      } else {
        _pantalla = _pantalla.substring(0, _pantalla.length - 1);
      }
    });
  }

  void _operar(String op) {
    HapticFeedback.selectionClick();
    final valor = double.tryParse(_pantalla.replaceAll(',', '.')) ?? 0;
    setState(() {
      if (_acumulado != null && _operacion != null && !_nuevoNumero) {
        _acumulado = _calcular(_acumulado!, valor, _operacion!);
        _pantalla = _fmt(_acumulado!);
      } else {
        _acumulado = valor;
      }
      _operacion = op;
      _nuevoNumero = true;
    });
  }

  void _igual() {
    HapticFeedback.mediumImpact();
    if (_acumulado == null || _operacion == null) return;
    final valor = double.tryParse(_pantalla.replaceAll(',', '.')) ?? 0;
    setState(() {
      final r = _calcular(_acumulado!, valor, _operacion!);
      _pantalla = _fmt(r);
      _acumulado = null;
      _operacion = null;
      _nuevoNumero = true;
    });
  }

  void _porcentaje() {
    HapticFeedback.selectionClick();
    final valor = double.tryParse(_pantalla.replaceAll(',', '.')) ?? 0;
    setState(() {
      if (_acumulado != null && _operacion != null) {
        // % sobre el acumulado (ej. 200 + 10% = 220).
        final pct = _acumulado! * (valor / 100);
        _pantalla = _fmt(pct);
      } else {
        _pantalla = _fmt(valor / 100);
      }
      _nuevoNumero = true;
    });
  }

  void _toggleSigno() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_pantalla == '0') return;
      if (_pantalla.startsWith('-')) {
        _pantalla = _pantalla.substring(1);
      } else {
        _pantalla = '-$_pantalla';
      }
    });
  }

  double _calcular(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? double.nan : a / b;
      default:
        return b;
    }
  }

  String _fmt(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    var s = v.toStringAsFixed(6);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  Widget _btn(
    String label, {
    required VoidCallback onTap,
    Color? bg,
    Color? fg,
    int flex = 1,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: bg ?? cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: 58,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: fg ?? cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opBg = cs.primary;
    final opFg = cs.onPrimary;
    final utilBg = cs.secondaryContainer;
    final utilFg = cs.onSecondaryContainer;

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Calculadora'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Text(
                        _pantalla,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: _pantalla.length > 10 ? 36 : 48,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_operacion != null && _acumulado != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 4),
                    child: Text(
                      '${_fmt(_acumulado!)} $_operacion',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              Row(children: [
                _btn('C', onTap: _limpiar, bg: utilBg, fg: utilFg),
                _btn('±', onTap: _toggleSigno, bg: utilBg, fg: utilFg),
                _btn('%', onTap: _porcentaje, bg: utilBg, fg: utilFg),
                _btn('÷', onTap: () => _operar('÷'), bg: opBg, fg: opFg),
              ]),
              Row(children: [
                _btn('7', onTap: () => _digito('7')),
                _btn('8', onTap: () => _digito('8')),
                _btn('9', onTap: () => _digito('9')),
                _btn('×', onTap: () => _operar('×'), bg: opBg, fg: opFg),
              ]),
              Row(children: [
                _btn('4', onTap: () => _digito('4')),
                _btn('5', onTap: () => _digito('5')),
                _btn('6', onTap: () => _digito('6')),
                _btn('−', onTap: () => _operar('−'), bg: opBg, fg: opFg),
              ]),
              Row(children: [
                _btn('1', onTap: () => _digito('1')),
                _btn('2', onTap: () => _digito('2')),
                _btn('3', onTap: () => _digito('3')),
                _btn('+', onTap: () => _operar('+'), bg: opBg, fg: opFg),
              ]),
              Row(children: [
                _btn('0', onTap: () => _digito('0'), flex: 2),
                _btn('.', onTap: () => _digito('.')),
                _btn('=', onTap: _igual, bg: opBg, fg: opFg),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _borrar,
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  label: const Text('Borrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
