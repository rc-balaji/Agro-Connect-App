import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.active,
    this.icon,
    this.activeText,
    this.inactiveText,
  });

  final String label;
  final bool active;
  final IconData? icon;
  final String? activeText;
  final String? inactiveText;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.emerald : AppTheme.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
          ] else ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Text(
            '$label · ${active ? (activeText ?? 'Online') : (inactiveText ?? 'Offline')}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
