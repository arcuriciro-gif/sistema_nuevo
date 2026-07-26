import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class ErpQuickAction {
  const ErpQuickAction({
    required this.label,
    required this.icon,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
}

/// Barra horizontal de acciones rápidas (Centro de operaciones).
class ErpQuickActionBar extends StatelessWidget {
  const ErpQuickActionBar({super.key, required this.actions});

  final List<ErpQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: a.onTap,
                icon: Icon(a.icon, size: 18),
                label: Text(a.label),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
